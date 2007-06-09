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

    def initialize(db)
      @db = db
    end

    def parse_file(path, filename, properties)
      File.open(path) {|f|
        return parse(f, filename)
      }
    end

    def parse(f, filename)
      file_entries LineInput.new(f)
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
      id = parse_header(header)
      @db.open_function(id) {|f|
        f.header = header
        f.source = body.join('')
      }
    end

    def parse_header(header)
      header.slice(/(\w+)(?:\(|\s*\z)/, 1) or
          raise "function header parse error: #{header.inspect}"
    end

  end

end
