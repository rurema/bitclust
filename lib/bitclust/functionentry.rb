#
# bitclust/functionentry.rb
#
# Copyright (c) 2006-2008 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the Ruby License.
#

require 'bitclust/entry'
require 'bitclust/exception'

module BitClust

  class FunctionEntry < Entry

    def FunctionEntry.type_id
      :function
    end

    def initialize(db, id)
      super db
      @id = id
      init_properties
    end

    def inspect
      "\#<function #{@id}>"
    end

    def name_match?(re)
      re =~ name()
    end

    def <=>(other)
      @id.casecmp(other.id)
    end

    persistent_properties {
      property :filename,   'String'
      property :macro,      'bool'
      property :private,    'bool'
      property :type,       'String'
      property :name,       'String'
      property :params,     'String'
      property :source,     'String'
    }

    attr_reader :id
    remove_method :name
    alias name id
    alias label id

    alias macro? macro
    alias private? private

    def public?
      not private?
    end

    def callable?
      not params().empty?
    end

    def type_label
      macro? ? 'macro' : 'function'
    end
    alias kind type_label

    def header
      if callable?
        base = "#{type()} #{name()}#{params()}"
      else
        base = "#{type()} #{name()}"
      end
      "#{private? ? 'static ' : ''}#{base}"
    end

  end

end
