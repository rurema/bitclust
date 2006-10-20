#!/usr/bin/env ruby

require 'bitclust'

def main
  Signal.trap(:PIPE) { exit 1 }
  Signal.trap(:INT) { exit 1 }

  refe = BitClust::Searcher.new
  refe.parse ARGV
  refe.exec nil, ARGV
rescue BitClust::UserError => err
  $stderr.puts err.message
  exit 1
end

main
