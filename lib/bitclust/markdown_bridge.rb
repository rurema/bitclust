# frozen_string_literal: true

require 'fileutils'
require 'pathname'

require 'bitclust/markdown_tree'
require 'bitclust/markdown_to_rrd'

module BitClust
  # md ツリー → 旧形式の rd ツリー（LIBRARIES + .rd）を生成するブリッジ。
  #
  # 既存の update 機構（LIBRARIES → RRDParser/Preprocessor）を一切変更せずに
  # md ツリーから DB を組み立てるための変換層。MarkdownTree の発見結果から:
  # - LIBRARIES を再生成（ライブラリの since/until は #@ ゲートとして再具現化）
  # - ライブラリ .rd = 変換済み本文 + メンバーへの #@include を再生成
  # - メンバー = 変換済み本文を front matter の since/until で #@ ラップ
  #   （版指定ビルドで構造ゲートが効くように）
  # - 断片 = そのまま変換
  # 出力ファイル名は「md 名から .md を剥いだもの」（ライブラリのみ .rd 付き）に
  # 統一し、本文中の #@include ターゲットも emit 名へ書き換える
  # （Preprocessor はリテラルパスで解決するため）。
  class MarkdownBridge
    INCLUDE_RE = /^(\#@include\s*\()(.*?)(\))/

    def self.build(md_root, out_root)
      new(md_root, out_root).build
    end

    # doc（散文ページ）の md ツリー → 旧形式の doc/*.rd。
    # - クロスツリー include（api 断片の transclude）は旧レイアウト
    #   （../api/src/）へ戻す（ブリッジの api ツリーは api/src に置かれるため）
    # - doc 内ローカル include から参照される断片（spec/regexp19 等）は
    #   拡張子なしで emit する（copy_doc は **/*.rd だけをページとして読む）
    # 戻り値は source_map（出力相対パス => 入力 md 相対パス）
    def self.build_doc(md_doc_root, out_doc_root)
      require 'bitclust/markdown_to_rrd'
      files = Dir.glob('**/*.md', base: md_doc_root).sort
      referenced = files.flat_map { |f|
        base = File.dirname(f)
        File.read(File.join(md_doc_root, f)).scan(/^\#@include\((?!(?:\.\.\/)+api\/)(.*?)\)/)
            .map { |t| File.expand_path(base == '.' ? t[0] : File.join(base, t[0]), '/')
                           .delete_prefix('/') }
      }.to_h { |t| [t, true] }

      files.to_h do |f|
        rrd = MarkdownToRRD.convert(File.read(File.join(md_doc_root, f)))
        rrd = rrd.gsub(%r{^(\#@include\((?:\.\./)+api/)(?!src/)}, '\1src/')
        name = f.sub(/\.md\z/, '')
        rel = referenced[name] ? name : "#{name}.rd"
        full = File.join(out_doc_root, rel)
        FileUtils.mkdir_p(File.dirname(full))
        File.write(full, rrd)
        [rel, f]
      end
    end

    attr_reader :warnings

    # 出力相対パス（emit 名） => 入力 md 相対パス。
    # source_location を manual/ の md へ再マップするために使う
    attr_reader :source_map

    def initialize(md_root, out_root)
      @md_root = md_root
      @out_root = out_root
      @tree = MarkdownTree.scan(md_root)
      @warnings = @tree.warnings.dup
      @source_map = {}
      # 名前はパス由来とは限らない（ファイル名衝突回避で改名された
      # rdoc/rdoc.lib.md は front matter の name: が正）ので、パスから引く
      @lib_by_path = @tree.libraries.to_h { |name, lib| [lib[:path], name] }
    end

    def build
      files = Dir.glob('**/*.md', base: @md_root).sort
      @dirs = files.flat_map { |f|
        parts = File.dirname(f).split('/')
        (1..parts.size).map { |n| parts.first(n).join('/') }
      }.uniq - ['.']
      emitted = files.to_h { |f| [f, emit_name(f)] }
      @source_map = emitted.invert

      files.each do |f|
        rrd = MarkdownToRRD.convert(File.read(File.join(@md_root, f)))
        rrd = rewrite_includes(rrd, f, emitted)
        if (libname = @lib_by_path[f])
          rrd << member_includes(libname, emitted)
        elsif (entity = @tree.entities[f])
          rrd = wrap_gate(rrd, entity)
        end
        write(emitted[f], rrd)
      end
      write('LIBRARIES', libraries_manifest)
      self
    end

    private

    # ライブラリは <name>.rd（update_by_stdlibtree の解決規約）。
    # 非ライブラリは拡張子なし（doc ツリーが `../api/src/_builtin/pack-template` の
    # ように元式の拡張子なし名で断片を transclude しているため）。
    # ただし同名ディレクトリと衝突する場合は .rd を付ける（scanf.md と scanf/）
    def emit_name(f)
      return "#{@lib_by_path[f]}.rd" if @lib_by_path[f]
      name = f.sub(/\.md\z/, '')
      return "#{name}.rd" if @dirs.include?(name)
      name
    end

    # LIBRARIES: 名前順。ライブラリの版ゲートは #@ で再具現化する
    def libraries_manifest
      @tree.libraries.sort.map { |name, lib|
        entry = "#{name}\n"
        entry = "\#@since #{lib[:since]}\n#{entry}\#@end\n" if lib[:since]
        entry = "\#@until #{lib[:until]}\n#{entry}\#@end\n" if lib[:until]
        entry
      }.join
    end

    # ライブラリのメンバー（membership がこのライブラリを指すエンティティ）への
    # #@include をライブラリ .rd のディレクトリ相対で再生成する。
    # reopen/redefine だけのファイルは後ろに並べる（reopen が dynamic include する
    # module は同ライブラリ内で先に定義されている必要がある: json/rake）。
    # 多重所属（ゲート付き library リスト）は membership のゲートで
    # include サイトをラップする（旧 LIBRARIES 世界のゲート付き include と同義）
    def member_includes(libname, emitted)
      base = File.dirname("#{libname}.rd")
      members = @tree.entities.select { |path, e|
        e[:memberships].any? { |m| m[:library] == libname }
      }
      return '' if members.empty?

      sorted = members.keys.sort_by do |path|
        reopen_only = members[path][:kinds].all? { |kind, _| %w[reopen redefine].include?(kind) }
        [reopen_only ? 1 : 0, path]
      end
      "\n" + sorted.map { |path|
        m = members[path][:memberships].find { |mm| mm[:library] == libname }
        inc = "\#@include(#{relative(emitted[path], base)})\n"
        inc = "\#@since #{m[:since]}\n#{inc}\#@end\n" if m[:since]
        inc = "\#@until #{m[:until]}\n#{inc}\#@end\n" if m[:until]
        inc
      }.join
    end

    # front matter の構造ゲート（since/until）を #@ ラッパーとして再具現化する
    def wrap_gate(rrd, entity)
      rrd = "\#@since #{entity[:since]}\n#{rrd}\#@end\n" if entity[:since]
      rrd = "\#@until #{entity[:until]}\n#{rrd}\#@end\n" if entity[:until]
      rrd
    end

    # 本文中の #@include ターゲットを emit 名（相対）へ書き換える。
    # 解決できないターゲットはそのまま（発見段階で警告済み）
    def rewrite_includes(rrd, md_file, emitted)
      return rrd unless rrd.include?('#@include')
      base = File.dirname(md_file)
      rrd.gsub(INCLUDE_RE) do
        pre, target, post = $1, $2, $3
        resolved = resolve(base, target, emitted)
        "#{pre}#{resolved ? relative(emitted[resolved], File.dirname(emitted[md_file])) : target}#{post}"
      end
    end

    def resolve(base, target, emitted)
      [target, "#{target}.md", "#{target.sub(/\.rd\z/, '')}.md"].uniq.each do |cand|
        rel = base == '.' ? cand : File.join(base, cand)
        rel = File.expand_path(rel, '/').delete_prefix('/')
        return rel if emitted.key?(rel)
      end
      nil
    end

    def relative(path, from_dir)
      return path if from_dir == '.'
      Pathname.new(File.expand_path(path, '/'))
              .relative_path_from(File.expand_path(from_dir, '/')).to_s
    end

    def write(rel, content)
      full = File.join(@out_root, rel)
      FileUtils.mkdir_p(File.dirname(full))
      File.write(full, content)
    end
  end
end
