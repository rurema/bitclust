#
# bitclust/methodentry.rb
#
# Copyright (c) 2006-2008 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the Ruby License.
#

require 'bitclust/entry'
require 'bitclust/exception'

module BitClust

  # Represents a method, a constant, and a special variable.
  class MethodEntry < Entry

    def MethodEntry.type_id
      :method
    end

    def initialize(db, id)
      super db
      @id = id
      init_properties
    end

    attr_reader :id

    def ==(other)
      @id == other.id
    end

    alias eql? ==

    def hash
      @id.hash
    end

    def <=>(other)
      sort_key() <=> other.sort_key
    end

    KIND_NUM = {:defined => 0, :redefined => 1, :added => 2}

    def sort_key
      [label(), KIND_NUM[kind()]]
    end

    def name
      methodid2mname(@id)
    end

    # typename = :singleton_method
    #          | :instance_method
    #          | :module_function
    #          | :constant
    #          | :special_variable
    def typename
      methodid2typename(@id)
    end

    alias type typename

    def typemark
      methodid2typemark(@id)
    end

    def typechar
      methodid2typechar(@id)
    end

    def type_label
      case typemark()
      when '.'  then 'singleton method'
      when '#'  then 'instance method'
      when '.#' then 'module function'
      when '::' then 'constant'
      when '$'  then 'variable'
      end
    end

    def library
      @library ||= @db.fetch_library_id(methodid2libid(@id))
    end

    attr_writer :library

    def klass
      @klass ||= @db.fetch_class_id(methodid2classid(@id))
    end

    attr_writer :klass

    persistent_properties {
      property :names,      '[String]'
      property :visibility, 'Symbol'   # :public | :private | :protected
      property :kind,       'Symbol'   # :defined | :added | :redefined
      property :source,     'String'
    }

    def inspect
      c, t, m, lib = methodid2specparts(@id)
      "\#<method #{c}#{t}#{names().join(',')}>"
    end

    def spec
      MethodSpec.new(*methodid2specparts(@id))
    end

    def spec_string
      methodid2specstring(@id)
    end

    def label
      c, t, m, lib = methodid2specparts(@id)
      "#{t == '$' ? '' : c}#{t}#{m}"
    end

    def short_label
      c, t, m, lib = methodid2specparts(@id)
      "#{t == '#' ? '' : t}#{m}"
    end

    def labels
      c, t, m, lib = methodid2specparts(@id)
      names().map {|name| "#{c}#{t}#{name}" }
    end

    def name?(name)
      names().include?(name)
    end

    def name_match?(re)
      names().any? {|n| re =~ n }
    end

    def really_public?
      visibility() == :public
    end

    def public?
      visibility() != :private
    end

    def protected?
      visibility() == :protected
    end

    def private?
      visibility() == :private
    end

    def public_singleton_method?
      singleton_method? and public?
    end

    def private_singleton_method?
      singleton_method? and private?
    end

    def public_instance_method?
      instance_method? and public?
    end

    def private_instance_method?
      instance_method? and public?
    end

    def singleton_method?
      t = typename()
      t == :singleton_method or t == :module_function
    end

    def instance_method?
      t = typename()
      t == :instance_method or t == :module_function
    end

    def constant?
      typename() == :constant
    end

    def special_variable?
      typename() == :special_variable
    end

    def defined?
      kind() == :defined
    end

    def added?
      kind() == :added
    end

    def redefined?
      kind() == :redefined
    end

  end

end
