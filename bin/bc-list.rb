#!/usr/bin/env ruby

require 'pathname'

bindir = Pathname.new(__FILE__).realpath.dirname
$LOAD_PATH.unshift((bindir + '../lib').realpath)

require 'bitclust'
require 'optparse'

def main
  parser = OptionParser.new
  parser.banner = "Usage: #{File.basename($0, '.*')} <file>..."
  parser.on('--help', 'Prints this message and quit.') {
    puts parser.help
    exit
  }
  begin
    parser.parse!
  rescue OptionParser::ParseError => err
    $stderr.puts err.message
    exit 1
  end

  ARGV.each do |path|
    show_library BitClust::RRDParser.parse_stdlib_file(path)
  end
end

def show_library(lib)
  puts "= Library #{lib.name}"
  lib.classes.each do |c|
    puts c.inspect
    c.each do |m|
      puts "\t#{m.inspect}"
    end
  end
  unless lib.methods.empty?
    puts "Additional Methods:"
    lib.methods.each do |m|
      puts "\t#{m.inspect}"
    end
  end
end

main
