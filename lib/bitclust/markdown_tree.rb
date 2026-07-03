# frozen_string_literal: true

module BitClust
  # 新パイプラインのファイル発見（MARKUP_SPEC §1.1）。
  #
  # md ツリー（refm/api/src/**/*.md 相当）を glob し、各ファイルの front matter と
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
      infos = files.to_h { |f| [f, parse_file(f)] }

      referenced = {}
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
        @libraries[path.sub(/\.md\z/, '')] = { path: path } if info[:library_file]
        # include 参照され front matter を持たないファイルは、H1 を含んでいても
        # 断片（transclusion 用。fiddle の版分岐チェーン等）
        info[:fragment] = referenced[path] && !info[:library_file] && info[:library].nil?
        if info[:fragment]
          @fragments << path
        elsif !info[:kinds].empty?
          @entities[path] = { names: info[:kinds].map(&:last), kinds: info[:kinds],
                              library: info[:library] }
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
        if info[:library].nil? && !info[:library_file]
          @warnings << "entity with no library: #{path}"
        elsif info[:library] && !@libraries.key?(info[:library])
          @warnings << "entity refers to unknown library #{info[:library]}: #{path}"
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
      info = { kinds: [], library: nil, library_file: false,
               front_matter_relations: false, body_relations: false, includes: [] }
      lines = File.readlines(File.join(@root, path))
      i = 0
      if lines[0] =~ /\A---\s*\z/
        i = 1
        while i < lines.length && lines[i] !~ /\A---\s*\z/
          case lines[i]
          when /\Atype:\s*library\s*\z/ then info[:library_file] = true
          when /\Alibrary:\s*(\S+)/ then info[:library] = $1
          when RELATION_KEY_RE then info[:front_matter_relations] = true
          end
          i += 1
        end
        i += 1
      end

      in_fence = false
      in_header = false
      lines[i..].each do |line|
        if line =~ FENCE_RE
          in_fence = !in_fence
          in_header = false
          next
        end
        next if in_fence

        if line =~ ENTITY_H1_RE
          info[:kinds] << [$1, $2]
          in_header = true
        elsif line =~ INCLUDE_RE
          info[:includes] << $1
          in_header = false
        elsif in_header
          case line
          when RELATION_LINE_RE then info[:body_relations] = true
          when /\A\#@/, BLANK_RE then nil
          else in_header = false
          end
        end
      end
      info
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
