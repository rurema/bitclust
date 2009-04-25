#
# bitclust/docentry.rb
#
# Copyright (c) 2006-2008 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the Ruby License.
#

require 'bitclust/entry'
require 'bitclust/exception'

module BitClust

  class DocEntry < Entry

    def self.type_id
      :doc
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
      @id.casecmp(other.id)
    end

    def name
      libid2name(@id)
    end

    alias label name

    def labels
      [label()]
    end
    
    def name?(n)
      name() == n
    end

    persistent_properties {
      property :title,    'String'
      property :source,   'String'
    }

    def inspect
      "#<doc #{@id}>"
    end

    def classes
      @db.classes
    end

    def error_classes
      classes.select{|c| c.ancestors.any?{|k| k.name == 'Exception' }}
    end
    
    def methods
      @db.methods
    end

    def libraries
      @db.libraries
    end
  end

end
