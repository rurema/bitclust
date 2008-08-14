#!/usr/bin/env ruby
#
# gencatalog.rb
#
# Copyright (c) 2008 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the Ruby License.
#

require 'optparse'

def main
  catalog_path = nil
  parser = OptionParser.new
  parser.banner = "Usage: #{File.basename($0)} --merge=PATH [<file>...]"
  parser.on('--merge=PATH', 'Current catalog file.') {|path|
    catalog_path = path
  }
  parser.on('--help', 'Prints this message and quit.') {
    puts parser.help
    exit 0
  }
  begin
    parser.parse!
  rescue OptionParser::ParseError => err
    $stderr.puts err
    $stderr.puts parser.help
    exit 1
  end

  h = collect_messages(ARGF)
  h.update load_catalog(catalog_path) if catalog_path
  print_catalog h
end

def print_catalog(h)
  h.keys.sort.each do |key|
    puts key
    puts h[key]
  end
end

def collect_messages(f)
  h = {}
  f.each do |line|
    line.scan(/_\(
        (?: "( (?:[^"]+|\\.)* )"
          | '( (?:[^']+|\\.)* )'
          )
    /x) do
      text = ($1 || $2).strip
      h[text] = text unless text.empty?
    end
  end
  h
end

def load_catalog(path)
  h = {}
  File.open(path) {|f|
    f.each do |line|
      h[line.chomp] = f.gets.chomp
    end
  }
  h
end

main
