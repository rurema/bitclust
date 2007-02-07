#!/usr/bin/env ruby

require 'pathname'

bindir = Pathname.new(__FILE__).realpath.dirname
$LOAD_PATH.unshift((bindir + '../lib').realpath)

require 'bitclust/crossrubyutils'
require 'optparse'

include BitClust::CrossRubyUtils

def main
  rejects = []
  @verbose = false
  opts = OptionParser.new
  opts.banner = "Usage: #{File.basename($0, '.*')} [-r<lib>] <lib>"
  opts.on('-r', '--reject=LIB', 'Reject library LIB') {|lib|
    rejects.concat lib.split(',')
  }
  opts.on('-v', '--verbose', 'Show all ruby version.') {
    @verbose = true
  }
  opts.on('--help', 'Prints this message and quit.') {
    puts opts.help
    exit 0
  }
  begin
    opts.parse!(ARGV)
  rescue OptionParser::ParseError => err
    $stderr.puts err.message
    exit 1
  end
  unless ARGV.size == 1
    $stderr.puts 'wrong number of arguments'
    $stderr.puts opts.help
    exit 1
  end
  lib = ARGV[0]
  print_crossruby_table {|ruby| defined_classes(ruby, lib, rejects) }
end

def defined_classes(ruby, lib, rejects)
  output = `#{ruby} -e '
    def class_extent
      result = []
      ObjectSpace.each_object(Module) do |c|
        result.push c
      end
      result
    end

    %w(#{rejects.join(" ")}).each do |lib|
      begin
        require lib
      rescue LoadError
      end
    end
    if "#{lib}" == "_builtin"
      class_extent().each do |c|
        puts c
      end
    else
      before = class_extent()
      begin
        require "#{lib}"
      rescue LoadError
        $stderr.puts "\#{RUBY_VERSION} (\#{RUBY_RELEASE_DATE}): library not exist: #{lib}"
        exit
      end
      after = class_extent()
      (after - before).each do |c|
        puts c
      end
    end
  '`
  output.split
end

main
