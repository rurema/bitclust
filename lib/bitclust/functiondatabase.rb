#
# bitclust/functiondatabase.rb
#
# Copyright (c) 2006-2008 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the Ruby License.
#

require 'bitclust/database'
require 'bitclust/functionentry'
require 'bitclust/completion'
require 'bitclust/functionreferenceparser'
require 'bitclust/exception'

module BitClust

  class FunctionDatabase < Database

    include Completion

    def initialize(prefix)
      super
      @dirty_functions = {}
      @functionmap = {}
      @function_extent_loaded = false
    end

    def commit
      each_dirty_function do |f|
        f.save
      end
      clear_dirty
      #save_completion_index
    end
    private :commit

    def dirty_function(f)
      @dirty_functions[f] = true
    end

    def dirty?
      not @dirty_functions.empty?
    end

    def each_dirty_function(&block)
      @dirty_functions.each_key(&block)
    end

    def clear_dirty
      @dirty_functions.clear
    end

    def update_by_file(path, filename)
      check_transaction
      FunctionReferenceParser.new(self).parse_file(path, filename, properties())
    end

    def search_functions(pattern)
      fs = _search_functions(pattern)
      if fs.empty?
        raise FunctionNotFound, "no such function: #{pattern}"
      end
      fs
    end

    def open_function(id)
      check_transaction
      if exist?("function/#{id}")
        f = load_function(id)
        f.clear
      else
        f = (@functionmap[id] ||= FunctionEntry.new(self, id))
      end
      yield f
      dirty_function f
      f
    end

    def fetch_function(id)
      load_function(id) or
          raise FunctionNotFound, "function not found: #{id.inspect}"
    end

    def load_function(id)
      @functionmap[id] ||=
          begin
            return nil unless exist?("function/#{id}")
            FunctionEntry.new(self, id)
          end
    end
    private :load_function

    def functions
      functionmap().values
    end

    def functionmap
      return @functionmap if @function_extent_loaded
      id_extent(FunctionEntry).each do |id|
        @functionmap[id] ||= FunctionEntry.new(self, id)
      end
      @function_extent_loaded = true
      @functionmap
    end
    private :functionmap

    def id_extent(entry_class)
      entries(entry_class.type_id.to_s)
    end
    private :id_extent

  end

end
