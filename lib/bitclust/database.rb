#
# bitclust/database.rb
#
# Copyright (c) 2006-2008 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the Ruby License.
#

require 'bitclust/nameutils'
require 'bitclust/exception'

module BitClust

  class Database

    include NameUtils

    def Database.datadir?(dir)
      File.file?("#{dir}/properties")
    end

    def Database.connect(uri)
      case uri.scheme
      when 'file'
        new(uri.path)
      when 'druby'
        DRbObject.new_with_uri(uri.to_s)
      else
        raise InvalidScheme, "unknown database scheme: #{uri.scheme}"
      end
    end

    def Database.dummy(params = {})
      db = new(nil)
      db.properties['version'] = params['version']
      db
    end

    def initialize(prefix)
      @prefix = prefix
      @properties = nil
      @in_transaction = false
      @properties_dirty = false
    end
    
    def dummy?
      not @prefix
    end

    #
    # Transaction
    #

    def transaction
      @in_transaction = true
      yield
      return if dummy?
      if @properties_dirty
        save_properties 'properties', @properties
        @properties_dirty = false
      end
      commit if dirty?
    ensure
      @in_transaction = false
    end

    # abstract dirty?
    # abstract clear_dirty
    # abstract commit

    def check_transaction
      return if dummy?
      unless @in_transaction
        raise NotInTransaction, "database changed without transaction"
      end
    end
    private :check_transaction

    #
    # Properties
    #

    def properties
      @properties ||=
          begin
            h = load_properties('properties')
            h.delete 'source' if h['source'] and h['source'].strip.empty?
            h
          end
    end

    def propkeys
      properties().keys
    end

    def propget(key)
      properties()[key]
    end

    def propset(key, value)
      check_transaction
      properties()[key] = value
      @properties_dirty = true
    end

    def encoding
      propget('encoding')
    end

    #
    # Direct File Access Layer: BitClust internal use only
    #

    def exist?(rel)
      return false unless @prefix
      File.exist?(realpath(rel))
    end

    def entries(rel)
      Dir.entries(realpath(rel))\
          .reject {|ent| /\A[\.=]/ =~ ent }\
          .map {|ent| decodeid(ent) }
    rescue Errno::ENOENT
      return []
    end

    def makepath(rel)
      FileUtils.mkdir_p realpath(rel)
    end

    def load_properties(rel)
      h = {}
      fopen(realpath(rel), 'r:EUC-JP') {|f|
        while line = f.gets
          k, v = line.strip.split('=', 2)
          break unless k
          h[k] = v
        end
        h['source'] = f.read
      }
      h
    rescue Errno::ENOENT
      return {}
    end

    def save_properties(rel, h)
      source = h.delete('source')
      atomic_write_open(rel) {|f|
        h.each do |key, val|
          f.puts "#{key}=#{val}"
        end
        f.puts
        f.puts source
      }
    end

    def read(rel)
      File.read(realpath(rel))
    end

    def foreach_line(rel, &block)
      File.foreach(realpath(rel), &block)
    end

    def atomic_write_open(rel, &block)
      tmppath = realpath(rel) + '.writing'
      fopen(tmppath, 'wb', &block)
      File.rename tmppath, realpath(rel)
    ensure
      File.unlink tmppath  rescue nil
    end

    def realpath(rel)
      "#{@prefix}/#{encodeid(rel)}"
    end
    private :realpath

  end

end
