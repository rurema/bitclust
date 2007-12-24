#
# bitclust/parseutils.rb
#
# Copyright (c) 2006-2007 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the Ruby License.
#

require 'bitclust/exception'

class String   # reopen
  attr_accessor :location
end

module BitClust

  class LineStream
    def initialize(f)
      @f = f
    end

    def gets
      line = @f.gets
      return nil unless line
      line.location = Location.new(@f.path, @f.lineno)
      line
    end
  end

  class Location
    def initialize(file, line)
      @file = file
      @line = line
    end

    attr_reader :file
    attr_reader :line

    def to_s
      "#{@file}:#{@line}"
    end

    def inspect
      "\#<#{self.class} #{@file}:#{@line}>"
    end
  end

  module ParseUtils
    def parse_error(msg, line)
      raise ParseError, "#{line.location}: #{msg}: #{line.inspect}"
    end
  end

end
