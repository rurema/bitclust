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
        when '[String]'       then "h['#{@name}'].split(/,(?=.)/)"
        when '[LibraryEntry]' then "restore_libraries(h['#{@name}'])"
        when '[ClassEntry]'   then "restore_classes(h['#{@name}'])"
        when '[MethodEntry]'  then "restore_methods(h['#{@name}'])"
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
      LibraryEntry.load(@db, id)
    end

    def restore_class(id)
      id.empty? ? nil : ClassEntry.load(@db, id)
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
      str.split(',').map {|id| klass.load(@db, id) }
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
      (path[i..-1] + [name()]).join(' -> ')
    end
    private :path_string

  end

end
