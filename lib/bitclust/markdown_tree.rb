# frozen_string_literal: true

module BitClust
  # 新パイプラインのファイル発見（MARKUP_SPEC §1.1）。
  #
  # md ツリー（manual/api/**/*.md 相当）を glob し、各ファイルの front matter と
  # エンティティ H1 から次の3種に分類する。旧 LIBRARIES マニフェストと
  # grouping 用 #@include は使わない。
  # - エンティティ: エンティティ H1 を1つ以上持つ（front matter の library が所属）
  # - ライブラリ: type: library を持つ（名前 = パスから .md を除いたもの）
  # - 共有断片: どちらでもなく、いずれかの #@include から参照される
  #
  # 検証（ビルド警告に相当）:
  # - 孤児: どの分類にも入らないファイル（H1 の書き忘れ・参照されない断片の検出）
  # - library の無いエンティティ / 未知の library を指すエンティティ
  # - 関係リント: include/extend/alias の記述場所は front matter のみ。
  #   マルチエンティティファイルの front matter 関係キーと、
  #   本文の H1 直後の関係行（ファイル種を問わず）を警告する
  # - #@include 先の欠損
  class MarkdownTree
    ENTITY_H1_RE = /\A#(?!#)\s*(class|module|object|reopen|redefine)\s+(\S+)/
    RELATION_LINE_RE = /\A(?:include|extend|alias)\s+\S/
    RELATION_KEY_RE = /\A(?:include|extend|alias):\s*\z/
    INCLUDE_RE = /\A\#@include\s*\((.*?)\)/
    FENCE_RE = /\A`{3,}/
    BLANK_RE = /\A\s*\z/

    def self.scan(root)
      new(root).scan
    end

    attr_reader :libraries, :entities, :fragments, :warnings

    def initialize(root)
      @root = root
      @libraries = {}   # name => { path: }
      @entities = {}    # path => { names:, library: }
      @fragments = []
      @warnings = []
    end

    def scan
      files = Dir.glob('**/*.md', base: @root).sort
      warn_case_collisions(files)
      infos = files.to_h { |f| [f, parse_file(f)] }

      referenced = {} #: Hash[String, bool]
      infos.each do |path, info|
        info[:includes].each do |target|
          if (resolved = resolve(path, target, infos))
            referenced[resolved] = true
          else
            @warnings << "include target not found: #{target} (from #{path})"
          end
        end
      end

      infos.each do |path, info|
        if info[:library_file]
          # 名前は原則パス由来。ファイル名衝突回避で改名されたファイル
          # （rdoc/rdoc.lib.md）は front matter の name: が正
          @libraries[info[:name] || path.sub(/\.md\z/, '')] =
            { path: path, since: info[:since], until: info[:until] }
        end
        # include 参照され front matter を持たないファイルは、H1 を含んでいても
        # 断片（transclusion 用。fiddle の版分岐チェーン等）
        info[:fragment] = referenced[path] && !info[:library_file] && info[:library].nil?
        if info[:fragment]
          @fragments << path
        elsif !info[:kinds].empty?
          @entities[path] = { names: info[:kinds].map(&:last), kinds: info[:kinds],
                              library: info[:library],
                              memberships: info[:memberships],
                              since: info[:since], until: info[:until] }
        elsif !info[:library_file]
          @warnings << "orphan file (no entity H1, no type: library, not included): #{path}"
        end
      end
      # 検証は全ライブラリの登録後に行う（辞書順で先に来るエンティティが
      # 未登録ライブラリを誤って「未知」と判定しないように）
      infos.each do |path, info|
        validate(path, info) unless info[:fragment]
      end
      self
    end

    private

    def validate(path, info)
      unless info[:kinds].empty?
        if info[:memberships].empty? && !info[:library_file]
          @warnings << "entity with no library: #{path}"
        else
          info[:memberships].each do |m|
            next if @libraries.key?(m[:library] || raise)
            @warnings << "entity refers to unknown library #{m[:library]}: #{path}"
          end
        end
        if info[:kinds].size > 1 && info[:front_matter_relations]
          @warnings << "relations in front matter of multi-entity file: #{path}"
        end
      end
      if info[:body_relations]
        @warnings << "relations in body (front matter is the only place): #{path}"
      end
    end

    # front matter（raw 走査。#@ を含むため YAML パーサは使わない）と本文
    # （フェンス外の H1・H1 直後の関係行・#@include）を読む
    def parse_file(path)
      # @type var info: file_info
      info = { kinds: [], library: nil, library_file: false, memberships: [],
               front_matter_relations: false, body_relations: false, includes: [] }
      lines = File.readlines(File.join(@root, path))
      i = 0
      if lines[0] =~ /\A---\s*\z/
        i = 1
        in_library_block = false
        gate_stack = [] #: Array[[Symbol, String?]]
        while i < lines.length && lines[i] !~ /\A---\s*\z/
          line = lines[i]
          if in_library_block
            # 多重所属のゲート付きリスト（MARKUP_SPEC §1.2）。
            # 項目は積まれているゲートをすべてまとって membership になる
            case line
            when /\A\s+- (\S+)/
              m = { library: $1 }
              gate_stack.each { |kind, ver| m[kind] = ver }
              info[:memberships] << m
              i += 1; next
            when /\A\#@since\s+(\S+)/ then gate_stack.push([:since, $1]); i += 1; next
            when /\A\#@until\s+(\S+)/ then gate_stack.push([:until, $1]); i += 1; next
            when /\A\#@end\s*\z/ then gate_stack.pop; i += 1; next
            else
              in_library_block = false  # ブロック終端。この行は通常キーとして処理
            end
          end
          case line
          when /\Atype:\s*library\s*\z/ then info[:library_file] = true
          when /\Aname:\s*(\S+)/ then info[:name] = $1
          when /\Alibrary:\s*\z/ then in_library_block = true; gate_stack = [] #: Array[[Symbol, String?]]
          when /\Alibrary:\s*(\S+)/ then info[:memberships] << { library: $1 }
          when /\Asince:\s*"?([^"\s]+)"?/ then info[:since] = $1
          when /\Auntil:\s*"?([^"\s]+)"?/ then info[:until] = $1
          when RELATION_KEY_RE then info[:front_matter_relations] = true
          end
          i += 1
        end
        i += 1
      end
      info[:library] = info[:memberships].dig(0, :library)

      in_fence = false
      in_header = false
      h1_gated = false
      gate_depth = 0
      (lines[i..] || raise).each do |line|
        if line =~ FENCE_RE
          in_fence = !in_fence
          in_header = false
          next
        end
        next if in_fence

        # 版ゲートの深度。#@ ブロック内のヘッダ関係行は body 残置が正しい
        # （H1 自体が版分岐する rbconfig 等）ので lint 対象から外す
        case line
        when /\A\#@(?:since|until|if)\b/ then gate_depth += 1
        when /\A\#@end\b/ then gate_depth -= 1 if gate_depth > 0
        end

        if line =~ ENTITY_H1_RE
          info[:kinds] << [$1 || raise, $2 || raise]
          in_header = true
          h1_gated = gate_depth > 0
        elsif line =~ INCLUDE_RE
          info[:includes] << ($1 || raise)
          in_header = false
        elsif in_header
          case line
          when RELATION_LINE_RE
            # 版分岐 H1（ゲート内の H1）のヘッダ領域は、ゲート直後の
            # 共通関係行も含めて body 残置が正しいので lint しない
            info[:body_relations] = true if gate_depth.zero? && !h1_gated
          when /\A\#@/, BLANK_RE then nil
          else in_header = false
          end
        end
      end
      info
    end

    # 大文字小文字のみが異なる名前は macOS/Windows の case-insensitive FS で
    # チェックアウト不能になるため、衝突を警告する（途中のディレクトリ名も見る）
    def warn_case_collisions(files)
      entries = files.flat_map { |f|
        parts = f.split('/')
        (1..parts.size).map { |n| parts.first(n).join('/') }
      }.uniq
      entries.group_by(&:downcase).each_value do |names|
        next if names.size < 2
        @warnings << "case-insensitive filename collision: #{names.sort.join(', ')}"
      end
    end

    # include 元ディレクトリ相対で target → target.md → （.rd を .md に）の順に解決
    def resolve(from, target, infos)
      base = File.dirname(from)
      [target, "#{target}.md", "#{target.sub(/\.rd\z/, '')}.md"].uniq.each do |cand|
        rel = base == '.' ? cand : File.join(base, cand)
        rel = File.expand_path(rel, '/').delete_prefix('/')
        return rel if infos.key?(rel)
      end
      nil
    end
  end
end
