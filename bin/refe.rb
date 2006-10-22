#!/usr/bin/env ruby

require 'bitclust'

def main
  Signal.trap(:PIPE) { exit 1 } rescue nil  # Win32 does not have SIGPIPE
  Signal.trap(:INT) { exit 1 }

  refe = BitClust::Searcher.new
  refe.parse ARGV
  refe.exec nil, ARGV
rescue BitClust::UserError => err
  $stderr.puts err.message
  exit 1
end

main
