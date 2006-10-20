#!/usr/bin/env ruby

require 'bitclust'

def main
  Signal.trap(:PIPE, "EXIT")
  Signal.trap(:INT, "EXIT")

  refe = BitClust::Searcher.new
  refe.parse ARGV
  refe.exec nil, ARGV
rescue BitClust::UserError => err
  $stderr.puts err.message
  exit 1
end

main
