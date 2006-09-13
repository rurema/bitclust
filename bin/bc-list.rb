#!/usr/bin/env ruby

require 'pathname'

bindir = Pathname.new(__FILE__).realpath.dirname
$LOAD_PATH.unshift((bindir + '../lib').realpath)

require 'bitclust'
require 'pp'

def main
  db = BitClust::Database.new(nil)
  parser = BitClust::RRDParser.new(db)
  ARGV.each do |path|
    pp parse_file(parser, path)
  end
end

def parse_file(parser, filename)
  libname = File.basename(filename, '.rd')
  File.open(ARGV[0]) {|f|
    preproc = BitClust::Preprocessor.wrap(f, {"version" => "1.9.0"})
    return parser.parse(preproc, libname, filename)
  }
end

main
