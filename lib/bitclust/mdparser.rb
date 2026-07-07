# frozen_string_literal: true
#
# bitclust/mdparser.rb
#
# Markdown ソースを直接パースして DB エントリを作るパーサ（フェーズ3 M3）。
#
# RRDParser のサブクラスとして、行レベルのディスパッチだけを Markdown 記法
# （MARKUP_SPEC）に差し替える。構造の組み立て（Context・Signature・Chunk）は
# すべて RRDParser から継承する。エントリの source には md 断片がそのまま入る。
#
# - `= class X < Y` → `# class X < Y`
# - `== Class Methods` 等 → `## Class Methods`（名称は同一）
# - `--- sig` → `### def sig` / `### module_function def` / `### const` / `### gvar`
# - category/require/sublibrary・include/extend/alias → front matter
# - `#@since` 等の指令は md でも同一記法のため Preprocessor は無変更で使う
#   （front matter 内の `#@` 行も先に版解決される）

require 'bitclust/rrdparser'

module BitClust

  class MDParser < RRDParser

    # メソッド系シグネチャ（キーワード付き h3）
    SIG_RE = /\A### (?:module_function def |def |const |gvar )/
    # H1（エンティティ見出し）。エスケープされた行頭リテラル \# は除外
    H1_RE = /\A#[^#]/
    # H2（レベル2セクション見出し）
    H2_RE = /\A##[^#]/
    # klass.source / library.source の終端（H1・H2・シグネチャ）
    BREAK_RE = /\A##?[^#]|\A### (?:module_function def |def |const |gvar )/

    def parse(f, libname, params = {})
      @context = Context.new(@db, libname)
      f = LineInput.new(Preprocessor.wrap(f, params))
      @front_matter = read_front_matter(f)
      do_parse f
      @context.library
    end

    private

    # front matter（--- ... ---）を読む。YAML のサブセット:
    # スカラー（type/library/category/since/until）とリスト
    # （include/extend/alias/require/sublibrary）のみ。#@ 行は
    # Preprocessor で版解決済みの残り（#@# コメント等）なので読み飛ばす
    def read_front_matter(f)
      fm = {}
      return fm unless f.peek && f.peek =~ /\A---\s*$/
      f.gets
      key = nil
      while (line = f.gets)
        break if line =~ /\A---\s*$/
        case line
        when /\A\#@/
          next
        when /\A(\w+):\s*$/
          key = $1
          fm[key] = []
        when /\A(\w+):\s*(.+?)\s*$/
          fm[$1] = ($2 || raise).sub(/\A"(.*)"\z/, '\1')
          key = nil
        when /\A\s+-\s+(\S.*?)\s*$/
          list = fm[key]
          list << $1 if key && list.is_a?(Array)
        end
      end
      fm
    end

    def do_parse(f)
      f.skip_blank_lines
      @context.categorize @front_matter['category'] if @front_matter['category']
      Array(@front_matter['require']).each { |r| @context.require r }
      Array(@front_matter['sublibrary']).each { |s| @context.sublibrary s }
      @context.library.source = f.break(BREAK_RE).join('').rstrip
      read_classes f
      if line = f.gets   # error
        case line
        when H2_RE
          parse_error "met level-2 header in library document; maybe you forgot level-1 header", line
        when SIG_RE
          parse_error "met bare method entry in library document; maybe you forgot reopen/redefine level-1 header", line
        else
          parse_error "unexpected line in library document", line
        end
      end
    end

    RELATION_KEYS = %w[include extend alias].freeze

    def read_classes(f)
      entity_count = 0
      f.while_match(H1_RE) do |line|
        entity_count += 1
        if entity_count > 1 && RELATION_KEYS.any? { |k| @front_matter.key?(k) }
          # 案B: 関係を持つファイルは単一エンティティ（front matter の
          # include/extend/alias の帰属が曖昧になるため）
          parse_error "multiple entities in a file with front matter relations", line
        end
        type, name, superclass = *parse_level1_header(line)
        case type
        when 'class'
          @context.define_class name, (superclass || 'Object'), location: line.location
          read_class_body f
        when 'module'
          parse_error "superclass given for module", line  if superclass
          @context.define_module name, location: line.location
          read_class_body f
        when 'object'
          @context.define_object name, superclass, location: line.location
          read_object_body f
        when 'reopen'
          @context.reopen_class name
          read_reopen_body f
        when 'redefine'
          @context.redefine_class name
          read_reopen_body f
        else
          parse_error "wrong level-1 header", line
        end
      end
    end

    def parse_level1_header(line)
      m = /\A(\S+)\s*([^\s<]+)(?:\s*<\s*(\S+))?\z/.match(line.sub(/\A#/, '').strip)
      unless m
        parse_error "level-1 header syntax error", line
      end
      return m[1], m[2], m[3]
    end

    # 関係（include/extend/alias）は front matter が唯一の置き場（案B）。
    # 本文からは読まない
    def read_aliases(f)
      Array(@front_matter['alias']).each { |name| @context.alias name }
    end

    def read_includes(f, reopen = false)
      Array(@front_matter['include']).each do |name|
        reopen ? @context.dynamic_include(name) : @context.include(name)
      end
    end

    def read_extends(f, reopen = false)
      Array(@front_matter['extend']).each do |name|
        reopen ? @context.dynamic_extend(name) : @context.extend(name)
      end
    end

    def read_class_body(f)
      f.skip_blank_lines
      read_aliases f
      read_extends f
      read_includes f
      f.skip_blank_lines
      @context.klass&.source = f.break(BREAK_RE).join('').rstrip
      read_level2_blocks f
    end

    def read_reopen_body(f)
      f.skip_blank_lines
      read_extends f, true
      read_includes f, true
      f.skip_blank_lines
      read_level2_blocks f
    end

    def read_object_body(f)
      f.skip_blank_lines
      read_aliases f
      read_extends f
      f.skip_blank_lines
      @context.klass&.source = f.break(BREAK_RE).join('').rstrip
      @context.visibility = :public
      @context.type = :singleton_method
      read_level2_blocks f
    end

    def read_level2_blocks(f)
      read_entries f
      f.skip_blank_lines
      f.while_match(H2_RE) do |line|
        case line.sub(/\A##/, '').strip
        when /\A((?:public|private|protected)\s+)?(?:(class|singleton|instance)\s+)?methods?\z/i
          visibility = ($1 || 'public').downcase.strip.intern
          @context.visibility = visibility
          t = ($2 || 'instance').downcase.sub(/class/, 'singleton')
          @context.type = _ = "#{t}_method".intern
        when /\AModule\s+Functions?\z/i
          @context.module_function
        when /\AConstants?\z/i
          @context.constant
        when /\ASpecial\s+Variables?\z/i
          @context.special_variable
        else
          parse_error "unknown level-2 header", line
        end
        read_entries f
      end
    end

    def read_chunks(f)
      f.skip_blank_lines
      result = [] #: Array[Chunk]
      f.while_match(SIG_RE) do |line|
        f.ungets line
        result.push read_chunk(f)
      end
      result
    end

    def read_chunk(f)
      header = f.span(SIG_RE)
      body = f.break(BREAK_RE)
      src = (header + body).join('')
      src.location = header[0].location
      sigs = header.map {|line| method_signature(line) }
      mainsig = check_chunk_signatures(sigs, header[0])
      names = sigs.map {|s| s.name }.compact.uniq.sort
      Chunk.new(mainsig, names, src)
    end

    # md シグネチャ行を rd 形式（--- ...）へ落とし、既存の
    # Signature パースを継承する。エラー時は元の行を報告する
    def method_signature(line)
      rd_line = line.sub(SIG_RE, '--- ')
      case
      when m = SIGNATURE.match(rd_line)
        klass, typemark_, name = m.captures
        typemark = _ = typemark_
        Signature.new(klass, typemark, name)
      when m = GVAR.match(rd_line)
        Signature.new(nil, '$', (m[1] || raise)[1..-1])
      else
        parse_error "wrong method signature", line
      end
    end
  end

end
