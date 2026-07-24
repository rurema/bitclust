# frozen_string_literal: true
#
# bitclust/entry.rb
#
# Copyright (c) 2006-2008 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the Ruby License.
#

require 'bitclust/compat'
require 'bitclust/nameutils'
require 'bitclust/exception'

module BitClust

  # Ancestor of entry classes.
  class Entry

    include NameUtils

    def self.persistent_properties
      @slots = []
      yield
      sep = ";"
      module_eval(src = <<-End, __FILE__, __LINE__ + 1)
        def init_properties
          if saved?
            #{@slots.map {|s| "@#{s.name} = nil" }.join(sep)}
            @loaded = false
          else
            clear
          end
        end

        def clear
          #{@slots.map {|s| "@#{s.name} = #{s.initial_value}" }.join(sep)}
          @loaded = true
        end

        def _set_properties(h)
          #{@slots.map {|s| "@#{s.name} = #{s.deserializer}" }.join(sep)}
        end

        def _get_properties
          h = {}
          #{@slots.map {|s| "h['#{s.name}'] = #{s.serializer}" }.join(sep)}
          h
        end

        def unload
          clear
          @loaded = false
        end
      End
      @slots.each do |slot|
        module_eval(<<-End, __FILE__, __LINE__ + 1)
          def #{slot.name}
            load unless @loaded
            @#{slot.name}
          end

          def #{slot.name}=(value)
            load unless @loaded
            @#{slot.name} = value
          end
        End
      end
    end

    def self.property(name, type)
      @slots.push Property.new(name, type)
    end

    # Used to define specific property of each entry class.
    #
    # Example
    #   persistent_properties {
    #     property :requires, '[LibraryEntry]'
    #     property :classes,  '[ClassEntry]'
    #     ...
    class Property
      def initialize(name, type)
        @name = name
        @type = type
      end

      attr_reader :name

      def initial_value
        case @type
        when 'String'         then "'(uninitialized)'"
        when 'Symbol'         then "nil"
        when 'bool'           then "false"
        when 'LibraryEntry'   then "nil"
        when 'ClassEntry'     then "nil"
        when 'MethodEntry'    then "nil"
        when '[String]'       then "[]"
        when '[LibraryEntry]' then "[]"
        when '[ClassEntry]'   then "[]"
        when '[MethodEntry]'  then "[]"
        when 'Location'       then "nil"
        else
          raise "must not happen: @type=#{@type.inspect}"
        end
      end

      def deserializer
        case @type
        when 'String'         then "h['#{@name}']"
        when 'Symbol'         then "h['#{@name}'].intern"
        when 'bool'           then "h['#{@name}'] == 'true' ? true : false"
        when 'LibraryEntry'   then "restore_library(h['#{@name}'])"
        when 'ClassEntry'     then "restore_class(h['#{@name}'])"
        when 'MethodEntry'    then "restore_method(h['#{@name}'])"
        when '[String]'       then "(h['#{@name}'] || '').split(/,(?=.)/)"
        when '[LibraryEntry]' then "restore_libraries(h['#{@name}'])"
        when '[ClassEntry]'   then "restore_classes(h['#{@name}'])"
        when '[MethodEntry]'  then "restore_methods(h['#{@name}'])"
        when 'Location'       then "h['#{@name}']&.tap { |loc| break if loc.empty?; break Location.new(loc.split(?:).first, nil) }"
        else
          raise "must not happen: @type=#{@type.inspect}"
        end
      end

      def serializer
        case @type
        when 'String'         then "@#{@name}"
        when 'Symbol'         then "@#{@name}.to_s"
        when 'bool'           then "@#{@name}.to_s"
        when 'LibraryEntry'   then "serialize_entry(@#{@name})"
        when 'ClassEntry'     then "serialize_entry(@#{@name})"
        when 'MethodEntry'    then "serialize_entry(@#{@name})"
        when '[String]'       then "@#{@name}.join(',')"
        when '[LibraryEntry]' then "serialize_entries(@#{@name})"
        when '[ClassEntry]'   then "serialize_entries(@#{@name})"
        when '[MethodEntry]'  then "serialize_entries(@#{@name})"
        when 'Location'       then "(@#{@name} && @#{@name}.file).to_s"
        else
          raise "must not happen: @type=#{@type.inspect}"
        end
      end
    end

    class << self
      alias load new
    end

    def initialize(db)
      @db = db
    end

    # description 等、コンパイラを通さない表示テキスト。
    # md ソースの DB では旧経路と同じ表示形（rd インライン形式）へ戻す
    def display_text(text)
      return text unless text
      if @db.properties['source_format'] == 'markdown'
        # LibraryEntry#require（ライブラリ関係の登録）が Kernel#require を
        # 隠蔽するため、ファイルロードは Kernel を明示する
        Kernel.require 'bitclust/markdown_to_rrd'
        ::BitClust::MarkdownToRRD.restore_description(text)
      else
        text
      end
    end
    private :display_text

    # BitClust::RDCompiler::BracketLink と同等の正規表現(/n なし)
    BracketLink = /\[\[[\w-]+?:[!-~]+?(?:\[\] )?\]\]/

    # meta description など、コンパイラを通さずマークアップも解釈されない
    # 場所に使うテキスト。非 ASCII 文字間の改行は削除し(ブラウザでは
    # 空白扱いになり日本語文中に不自然な空白が見えるため)、残りの改行は
    # 空白に変換、ブラケットリンクはリンク先名のみにする
    def description_text(text)
      text = display_text(text)
      return text unless text
      # module function の ".#" は表示専用なので、DB バージョンが 4.0 以降なら
      # "?." で表示する(RDCompiler#display_spec と同じ #250/#282 の規則。
      # ここは可視ページを通さない meta description 用の経路なので、bracket_link
      # と同じ変換を独立に適用する必要がある。spec・URL・アンカーキーは不変)
      version = @db&.propget('version')
      text = text.split("\n").map(&:strip).join("\n")
        .gsub(/(\P{ascii})\n(?=\P{ascii})/) { $1 || raise }
        .tr("\n", ' ')
      text.gsub(BracketLink) {|link|
        label = ((link[2..-3] || raise).split(':', 2).last || raise).rstrip
        label.include?('.#') ? label.sub('.#', NameUtils.display_typemark('.#', version)) : label
      }
    end
    private :description_text

    def type_id
      self.class.type_id
    end

    def loaded?
      @loaded
    end

    def encoding
      @db.encoding
    end

    def synopsis_source
      source().split(/\n\n/, 2).first || ''
    end

    def detail_source
      source().split(/\n\n/, 2)[1] || ''
    end

    def save
      @db.save_properties objpath(), _get_properties()
    rescue Errno::ENOENT
      @db.makepath File.dirname(objpath())
      retry
    end

    private

    def load
      _set_properties @db.load_properties(objpath())
      @loaded = true
    end

    def saved?
      @db.exist?(objpath())
    end

    def restore_library(id)
      LibraryEntry.load(@db, id) # steep:ignore
    end

    def restore_class(id)
      id.empty? ? nil : ClassEntry.load(@db, id) # steep:ignore
    end

    def restore_libraries(str)
      restore_entries(str, LibraryEntry)
    end

    def restore_classes(str)
      restore_entries(str, ClassEntry)
    end

    def restore_methods(str)
      restore_entries(str, MethodEntry)
    end

    def restore_entries(str, klass)
      return [] if str.nil?
      str.split(',').map {|id| klass.load(@db, id) }  # steep:ignore
    end

    def serialize_entry(x)
      x ? x.id : ''
    end

    def serialize_entries(xs)
      xs.map {|x| x.id }.join(',')
    end

    def objpath
      "#{type_id()}/#{id()}"
    end

    def path_string(path)
      i = path.index(name())
      ((path[i..-1] || raise) + [name()]).join(' -> ')
    end
    private :path_string

  end

end
