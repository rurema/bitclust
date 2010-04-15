#!/usr/bin/env ruby
#
# bc-tohtml.rb
#
# Copyright (c) 2006-2007 Minero Aoki
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
  templatedir = srcdir_root() + 'template.offline'
  target = nil
  baseurl = 'file://' + srcdir_root
  parser = OptionParser.new
  ver = '1.9.0'
  parser.banner = "Usage: #{File.basename($0, '.*')} rdfile"
  parser.on('--target=NAME', 'Compile NAME to HTML.') {|name|
    target = name
  }
  parser.on('--force', '-f', 'Force to use rd_file template.') {|name|
    @rd_file = true
  }
  parser.on('--ruby_version=VER', '--ruby=VER', 'Set Ruby version') {|v|
    ver = v
  }
  parser.on('--db=DB', '--database=DB', 'Set database path') {|path|
    db = BitClust::Database.new(path)
  }
  parser.on('--baseurl=URL', 'Base URL of generated HTML') {|url|
    baseurl = url
  }
  parser.on('--templatedir=PATH', 'Template directory') {|path|
    templatedir = path
  }
  parser.on('--help', 'Prints this message and quit.') {
    puts parser.help
    exit 0
  }
  parser.on('--capi', 'C API mode.') {
    @capi = true
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

  db ||= BitClust::Database.dummy({'version' => ver})
  manager = BitClust::ScreenManager.new(
                                        :templatedir => templatedir,
                                        :base_url => baseurl,
                                        :cgi_url => baseurl,
                                        :default_encoding => 'euc-jp')
  unless @rd_file
    begin
      if @capi
        lib = BitClust::FunctionReferenceParser.parse_file(ARGV[0], {'version' => ver})
        unless target
          raise NotImplementedError, "generating a C API html without --target=NAME is not implemented yet."
        end
      else
        lib = BitClust::RRDParser.parse_stdlib_file(ARGV[0], {'version' => ver})
      end
      entry = target ? lookup(lib, target) : lib
      puts manager.entry_screen(entry, {:database => db}).body
      return 
    rescue BitClust::ParseError => ex
      $stderr.puts ex.message
      $stderr.puts ex.backtrace[0], ex.backtrace[1..-1].map{|s| "\tfrom " + s}
    end
  end

  
  ent = BitClust::DocEntry.new(db, ARGV[0])
  ret = BitClust::Preprocessor.read(ARGV[0], {'version' => ver})
  ent.source = ret
  puts manager.doc_screen(ent, {:database => db} ).body
  return 
rescue BitClust::WriterError => err
  $stderr.puts err.message
  exit 1
end

def lookup(lib, key)
  case
  when @capi && BitClust::NameUtils.functionname?(key)
    lib.find {|func| func.name == key}
  when BitClust::NameUtils.method_spec?(key)
    spec = BitClust::MethodSpec.parse(key)
    if spec.constant?
      begin
        lib.fetch_class(key)
      rescue BitClust::UserError
        lib.fetch_methods(spec)
      end
    else
      lib.fetch_methods(spec)
    end
  when BitClust::NameUtils.classname?(key)
    lib.fetch_class(key)
  else
    raise BitClust::InvalidKey, "wrong search key: #{key.inspect}"
  end
end

main
