#!/usr/bin/env ruby
#
# bc-tohtml.rb
#
# Copyright (c) 2006 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the Ruby License.
#

require 'pathname'

def srcdir_root
  (Pathname.new(__FILE__).realpath.dirname + '..').cleanpath
end

$LOAD_PATH.unshift srcdir_root() + 'lib'

$KCODE = 'EUC'

require 'bitclust'
require 'optparse'

def main
  templatedir = srcdir_root() + 'template'
  target = nil
  parser = OptionParser.new
  parser.banner = "Usage: #{File.basename($0, '.*')} rdfile"
  parser.on('--target=NAME', 'Compile NAME to HTML.') {|name|
    target = name
  }
  parser.on('--templatedir=PATH', 'Template directory') {|path|
    templatedir = path
  }
  parser.on('--help', 'Prints this message and quit.') {
    puts parser.help
    exit 0
  }
  begin
    parser.parse!
  rescue OptionParser::ParseError => err
    $stderr.puts err.message
    $stderr.puts parser.help
    exit 1
  end
  if ARGV.size > 1
    $stderr.puts "too many arguments (expected 1)"
    exit 1
  end

  lib = parse_file(ARGV[0])
  entity = lookup(lib, target)
  manager = BitClust::ScreenManager.new(
    :baseurl => 'http://example.com/',
    :templatedir => templatedir)
  puts manager.entity_screen(entity).body
end

def parse_file(path)
  db = BitClust::Database.new(nil)
  parser = BitClust::RRDParser.new(db)
  libname = File.basename(path, '.rd')
  parser.parse_file(path, libname, {"version" => "1.9.0"})
end

def lookup(lib, key)
  return lib unless key
  raise 'FIXME'
end

main
