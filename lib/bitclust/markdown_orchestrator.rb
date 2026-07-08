# frozen_string_literal: true

require 'pathname'

require 'bitclust/include_graph'
require 'bitclust/rrd_to_markdown'
require 'bitclust/include_pruner'
require 'bitclust/whole_file_gate'
require 'bitclust/entity_splitter'
require 'bitclust/rrd_to_markdown'

module BitClust
  # RRD ツリー → Markdown ツリー変換のクロスファイル方針を束ねるオーケストレータ。
  #
  # 単一ファイル記法変換（RRDToMarkdown）はそのままに、include グラフの解析結果から
  # 各ファイルへ次を適用する:
  # - grouping include の prune（エンティティ取り込みは front matter 発見へ移行）
  # - ファイル全体を包む版ゲートの解除（front matter の since/until へ移行）
  # - front matter 注入（member: library/構造ゲート、library ルート: type/版ゲート）
  #
  # スコープ（対象版範囲）はパラメータ。旧版サルベージ時は別スコープで再実行する。
  class MarkdownOrchestrator
    attr_reader :scope, :graph

    def initialize(src_root, scope: IncludeGraph::Scope.new('3.0', '4.2'))
      @graph = IncludeGraph.analyze(src_root)
      @scope = scope
      @extra = @graph.front_matter_map(scope)
      @graph.library_front_matter_map(scope).each do |path, fm|
        (@extra[path] ||= {}).merge!(fm)
      end
      @prune_sites = @graph.grouping_include_sites
    end

    def warnings
      @graph.warnings
    end

    # 変換対象か。LIBRARIES は front matter による発見に置き換わるため対象外
    def convert?(relpath)
      relpath != 'LIBRARIES'
    end

    # 1つの出力 .md ファイルに対応する単位。
    # path = 出力相対パス、rrd = rd 側到達点（md→rd 検証の期待値）、
    # front_matter = 注入する front matter
    Unit = Struct.new(:path, :rrd, :front_matter)

    # relpath の RRD を出力単位の列に還元する。
    # ヘッダ関係（include/extend/alias）を持つマルチエンティティファイルは
    # エンティティ単位に分割する（関係の front matter 一元化のため）。
    # 関係を持たない束ね（Errno 族等）と lib+単一エンティティ兼用ファイルは
    # 1 単位のまま。ライブラリファイルの分割ではエンティティを <libname>/ 配下に
    # 置き、library と版ゲートを注入する
    def units(relpath, rrd)
      reduced, front_matter = reduce(relpath, rrd)
      # スコープ外ファイル（front matter 注入なし）は分割しない。
      # サルベージは別スコープの再実行で扱う
      segments = front_matter.empty? ? nil : split_segments(reduced)
      return [Unit.new(output_path(relpath, front_matter), reduced, front_matter)] unless segments

      library = front_matter['type'] == 'library'
      dir = library ? relpath.sub(/\.rd\z/, '') : File.dirname(relpath)
      entity_fm =
        if library
          fm = { 'library' => relpath.sub(/\.rd\z/, '') }
          %w[since until].each { |k| fm[k] = front_matter[k] if front_matter[k] }
          fm
        else
          front_matter
        end

      source_dir = File.dirname(relpath)
      units = segments.map do |name, text|
        next Unit.new(output_path(relpath, front_matter), text, front_matter) if name.nil?   # 概要部

        fm = entity_fm.dup
        if (unwrapped = WholeFileGate.unwrap_for_scope(text, @scope))
          text = unwrapped[0]
          merge_gate(fm, unwrapped[1])
        end
        text = rewrite_includes(text, source_dir, dir)
        filename = "#{EntitySplitter.entity_filename(name)}.md"
        Unit.new(dir == '.' ? filename : File.join(dir, filename), text, fm)
      end
      if library && segments.none? { |name, _| name.nil? }
        # 概要部が無くてもライブラリ自体が発見から消えないよう front matter のみ合成
        units.unshift(Unit.new(output_path(relpath, front_matter), '', front_matter))
      end
      units
    end

    def convert_unit(unit)
      RRDToMarkdown.convert(unit.rrd, extra_front_matter: unit.front_matter)
    end

    # relpath の RRD を新パイプライン形の Markdown へ変換する（分割なしファイル用）
    def convert(relpath, rrd)
      us = units(relpath, rrd)
      raise ArgumentError, "#{relpath} splits into #{us.size} files, use units" if us.size > 1
      convert_unit(us.first)
    end

    # 変換の rd 側到達点（prune + 全体ゲート解除 + 定数 H1 ゲート解決後の RRD）と
    # front matter。MarkdownToRRD.convert(convert(...)) はこの RRD と一致する
    def reduce(relpath, rrd)
      front_matter = (@extra[relpath] || {}).dup
      rrd = IncludePruner.prune(rrd, @prune_sites[relpath] || [])
      if (unwrapped = WholeFileGate.unwrap_for_scope(rrd, @scope))
        rrd = unwrapped[0]
        merge_gate(front_matter, unwrapped[1])
      end
      rrd = EntitySplitter.resolve_header_gates(rrd, @scope)
      rrd = normalize_entity_h1(rrd)
      rrd = normalize_signature_spacing(rrd)
      rrd = RRDToMarkdown.normalize_dlist_colon_spacing(rrd)
      rrd = rrd.sub(/\A(?:[ \t]*\n)+/, '')   # 先頭空行（ゲート解決の残り）を除去
      [normalize_header_regions(rrd), front_matter]
    end

    private

    # 分割すべきならセグメント列を、そうでなければ nil を返す。
    # 条件: エンティティ（名前付きセグメント）が2つ以上 + いずれかがヘッダ関係を持つ。
    # lib+単一エンティティ兼用（pathname 型、仕様が認める形）は分割しない
    def split_segments(reduced)
      return nil unless EntitySplitter.header_relations?(reduced)
      segments = EntitySplitter.segments(reduced)
      return nil unless segments
      segments.count { |name, _| name } >= 2 ? segments : nil
    end

    # セグメントの置き場所が元ファイルと異なるディレクトリになる場合
    # （lib 分割 → <libname>/ 配下）、相対 #@include を新ディレクトリから
    # 解決できるよう書き換える
    def rewrite_includes(text, source_dir, new_dir)
      return text if source_dir == new_dir || text !~ /\#@include/
      base = File.expand_path(new_dir, '/')
      text.gsub(/^(\#@include\s*\()(.*?)(\))/) do
        pre, target, post = $1, $2, $3
        abs = File.expand_path(source_dir == '.' ? target : File.join(source_dir, target), '/')
        "#{pre}#{Pathname.new(abs).relative_path_from(base)}#{post}"
      end
    end

    # 出力 .md の相対パス（.rd は差し替え、その他は付加）
    def md_path(relpath)
      relpath.end_with?('.rd') ? relpath.sub(/\.rd\z/, '.md') : "#{relpath}.md"
    end

    # ライブラリファイルの出力パス。他ファイルの出力と大文字小文字のみで
    # 衝突する場合（rdoc/rdoc.md と rdoc/RDoc.md）は basename に .lib を挟んで
    # 回避する（macOS/Windows の case-insensitive FS でチェックアウト不能に
    # なるため）。名前がパスから導出できなくなるので front matter の name: で保持する
    def output_path(relpath, front_matter)
      path = md_path(relpath)
      return path unless front_matter['type'] == 'library'
      collides = @extra.keys.any? { |other|
        next false if other == relpath
        op = md_path(other)
        op != path && op.casecmp?(path)
      }
      return path unless collides
      front_matter['name'] = relpath.sub(/\.rd\z/, '')
      path.sub(/\.md\z/, '.lib.md')
    end

    RELATION_RE = /\A(?:include|extend|alias)\s+\S/
    HEADER_DIR_RE = /\A\#@(?:since|until|if|else|end)\b/
    BLANK_LINE_RE = /\A\s*\z/

    # H1 直後のヘッダ関係領域を md→rd の再生成形に正規化する:
    # 最後の関係行までの空行を除き、関係行の末尾空白を落とす。
    # 関係を持たない H1 の直後や本文の空行・散文ゲートは触らない
    def normalize_header_regions(rrd)
      lines = rrd.lines
      out = []
      i = 0
      while i < lines.length
        line = lines[i]
        out << line
        i += 1
        next unless line =~ EntitySplitter::H1_RE
        region = []
        while i < lines.length &&
              (lines[i] =~ RELATION_RE || lines[i] =~ HEADER_DIR_RE || lines[i] =~ BLANK_LINE_RE)
          region << lines[i]
          i += 1
        end
        last_rel = region.rindex { |l| l =~ RELATION_RE }
        if last_rel
          head = region[0..last_rel].reject { |l| l =~ BLANK_LINE_RE }
                                    .map { |l| l =~ RELATION_RE ? "#{l.rstrip}\n" : l }
          out.concat(head)
          out.concat(region[(last_rel + 1)..])
        else
          out.concat(region)
        end
      end
      out.join
    end

    # 「=class Encoding」のようなスペース無し H1（RRDParser は受理）を
    # 正規形「= class」に直す。単一ファイル変換器は正規形のみ扱う
    def normalize_entity_h1(rrd)
      return rrd unless rrd =~ /^=(?:class|module|object|reopen|redefine)\b/
      rrd.gsub(/^=((?:class|module|object|reopen|redefine)\b)/, '= \1')
    end

    # 「---critical=(bool)」のようなスペース無しシグネチャ（RDCompiler は
    # /\A---/ で受理）を正規形「--- name」に直す。コードブロック内に
    # 行頭 --- は現れない前提（roundtrip 検証が破れを検出する）
    def normalize_signature_spacing(rrd)
      rrd.gsub(/^---(?=[^\s-])/, '--- ')
    end

    # ファイル全体ゲートと注入済みゲート（include サイト / LIBRARIES 由来）の交差を取る
    # （since は max、until は min。両者は同じ制約の別表現なので通常は一致する）
    def merge_gate(front_matter, gate)
      if (v = gate[:since])
        front_matter['since'] = [front_matter['since'], v].compact
                                  .max_by { |x| Gem::Version.new(x) }
      end
      if (v = gate[:until])
        front_matter['until'] = [front_matter['until'], v].compact
                                  .min_by { |x| Gem::Version.new(x) }
      end
    end
  end
end
