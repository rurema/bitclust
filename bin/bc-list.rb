#!/usr/bin/env ruby

require 'pathname'

bindir = Pathname.new(__FILE__).realpath.dirname
$LOAD_PATH.unshift((bindir + '../lib').realpath)

require 'bitclust'
require 'pp'
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

  db = BitClust::Database.new(nil)
  parser = BitClust::RRDParser.new(db)
  ARGV.each do |path|
    libname = File.basename(path, '.rd')
    pp parser.parse_file(path, libname, {"version" => "1.9.0"})
  end
end

main
