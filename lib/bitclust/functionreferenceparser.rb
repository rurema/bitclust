#
# bitclust/functionreferenceparser.rb
#
# Copyright (c) 2006-2007 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the Ruby License.
#

require 'bitclust/exception'

module BitClust

  class FunctionReferenceParser

    def FunctionReferenceParser.parse_file(path, params = {"version" => "1.9.0"})
      parser = new(FunctionDatabase.dummy(params))
      parser.parse_file(path, File.basename(path, ".rd"), params)
    end

    def initialize(db)
      @db = db
    end

    def parse_file(path, filename, properties)
      fopen(path, 'r:EUC-JP') {|f|
        return parse(f, filename)
      }
    end

    def parse(f, filename)
      @filename = filename
      file_entries LineInput.new(f)
      @db.functions
    end

    private

    def file_entries(f)
      f.skip_blank_lines
      f.while_match(/\A---/) do |header|
        entry header.sub(/\A---/, '').strip, f.break(/\A---/)
        f.skip_blank_lines
      end
    end

    def entry(header, body)
      h = parse_header(header)
      @db.open_function(h.name) {|f|
        f.filename = @filename
        f.macro = h.macro
        f.private = h.private
        f.type = h.type
        f.name = h.name
        f.params = h.params
        f.source = body.join('')
      }
    end

    def parse_header(header)
      h = FunctionHeader.new
      m = header.match(/\A\s*(MACRO\s+)?(static\s+)?(.+?\W)(\w+)(\(.*\))?\s*\z/)
      raise ParseError, "syntax error: #{header.inspect}" unless m
      h.macro = m[1] ? true : false
      h.private = m[2] ? true : false
      h.type = m[3].strip
      h.name = m[4]
      h.params = m[5].strip if m[5]
      h
    end

  end

  FunctionHeader = Struct.new(:macro, :private, :type, :name, :params)

end
