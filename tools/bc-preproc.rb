#!/usr/bin/env ruby

require 'pathname'

bindir = Pathname.new(__FILE__).realpath.dirname
$LOAD_PATH.unshift((bindir + '../lib').realpath)

require 'bitclust/rrdparser'
require 'optparse'

def main
  params = {"version" => "1.9.0"}
  parser = OptionParser.new
  parser.banner = "Usage: #{File.basename($0, '.*')} <file>..."
  parser.on('--param=KVPAIR', 'Set parameter by key/value pair.') {|kv|
    k, v = kv.split('=', 2)
    params[k] = v
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

  ARGV.each do |path|
    File.open(path) {|f|
      BitClust::Preprocessor.wrap(f, params).each do |line|
        puts line
      end
    }
  end
rescue BitClust::WriterError => err
  $stderr.puts err.message
  exit 1
end

main
