# frozen_string_literal: true

require 'bitclust/include_graph'
require 'bitclust/include_pruner'
require 'bitclust/whole_file_gate'
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

    # relpath の RRD を新パイプライン形の Markdown へ変換する
    def convert(relpath, rrd)
      reduced, front_matter = reduce(relpath, rrd)
      RRDToMarkdown.convert(reduced, extra_front_matter: front_matter)
    end

    # 変換の rd 側到達点（prune + 全体ゲート解除後の RRD）と front matter。
    # MarkdownToRRD.convert(convert(...)) はこの RRD と一致する（検証の期待値）
    def reduce(relpath, rrd)
      front_matter = (@extra[relpath] || {}).dup
      rrd = IncludePruner.prune(rrd, @prune_sites[relpath] || [])
      if (unwrapped = WholeFileGate.unwrap_for_scope(rrd, @scope))
        rrd = unwrapped[0]
        merge_gate(front_matter, unwrapped[1])
      end
      [normalize_entity_h1(rrd), front_matter]
    end

    private

    # 「=class Encoding」のようなスペース無し H1（RRDParser は受理）を
    # 正規形「= class」に直す。単一ファイル変換器は正規形のみ扱う
    def normalize_entity_h1(rrd)
      return rrd unless rrd =~ /^=(?:class|module|object|reopen|redefine)\b/
      rrd.gsub(/^=((?:class|module|object|reopen|redefine)\b)/, '= \1')
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
