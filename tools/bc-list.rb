#!/usr/bin/env ruby

require 'pathname'

bindir = Pathname.new(__FILE__).realpath.dirname
$LOAD_PATH.unshift((bindir + '../lib').realpath)

require 'bitclust'
require 'optparse'

def main
  check_only = false
  parser = OptionParser.new
  parser.banner = "Usage: #{File.basename($0, '.*')} <file>..."
  parser.on('-c', '--check-only', 'Check syntax and output status.') {
    check_only = true
  }
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

  success = true
  ARGV.each do |path|
    begin
      lib = BitClust::RRDParser.parse_stdlib_file(path)
      if check_only
        $stderr.puts "#{path}: OK"
      else
        show_library lib
      end
    rescue BitClust::WriterError => err
      raise if $DEBUG
      $stderr.puts "#{File.basename($0, '.*')}: FAIL: #{err.message}"
      success = false
    end
  end
  exit success
end

def show_library(lib)
  puts "= Library #{lib.name}"
  lib.classes.each do |c|
    puts "#{c.type} #{c.name}"
    c.each do |m|
      puts "\t* #{m.klass.name}#{m.typemark}#{m.names.join(',')}"
    end
  end
  unless lib.methods.empty?
    puts "Additional Methods:"
    lib.methods.each do |m|
      puts "\t* #{m.klass.name}#{m.typemark}#{m.names.join(',')}"
    end
  end
end

main
