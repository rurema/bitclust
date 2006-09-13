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
    pp parser.parse_file(path, {"version" => "1.9.0"})
  end
end

main
