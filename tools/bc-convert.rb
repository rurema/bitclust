#!/usr/bin/env ruby

$KCODE = 'EUC'

require 'stringio'
require 'fileutils'
require 'tmpdir'
require 'optparse'

def main
  mode = :output
  parser = OptionParser.new
  parser.banner = "Usage: #{File.basename($0, '.*')} [--diff] [file...]"
  parser.on('--diff', 'Show the diff between original file and output') {
    mode = :diff
  }
  parser.on('--inplace', 'edit input files in-place (make backup)') {
    mode = :inplace
  }
  parser.on('--help') {
    puts parser.help
    exit
  }
  begin
    parser.parse!
  rescue OptionParser::ParseError => err
    $stderr.puts err.message
    exit 1
  end
  case mode
  when :output
    do_convert ARGF
  when :diff
    ARGV.each do |path|
      diff_output path
    end
  when :inplace
    ARGV.each do |path|
      inplace_edit path
    end
  else
    raise "must not happen: mode=#{mode.inspect}"
  end
end

def inplace_edit(path)
  str = convert_file(path)
  File.rename path, path + '.bak'
  File.open(path, 'w') {|f|
    f.write str
  }
end

def diff_output(path)
  tmppath = "#{Dir.tmpdir}/bc-convert-diff"
  File.open(tmppath, 'w') {|f|
    f.write convert_file(path)
  }
  system 'diff', '-u', path, tmppath
ensure
  FileUtils.rm_f tmppath
end

def convert_file(path)
  File.open(path) {|f| convert(f) }
end

def convert(f)
  buf = StringIO.new
  do_convert f, buf
  buf.string
end

def do_convert(f, out = $stdout)
  f.each do |line|
    case line
    when /\A\#@/
      out.puts line
    when /\A\#/
      out.puts '#@' + line
    when /\A---\s/
      sig = convert_signature(line.sub(/\A---/, '').sub(/\(\(<.*?>\)\)/i, '').strip)
      out.puts "--- #{sig}"
      if meta = line.slice(/\(\(<.*?>\)\)/i)
        out.puts
        out.puts meta
        out.puts
      end
    else
      out.puts convert_link(line.rstrip)
    end
  end
end

def convert_signature(sig)
  case sig
  when /\A([\w:\.\#]+[?!]?)\s*(?:[\(\{]|--|->|\z)/
       # name(arg), name{}, name,
       # name() -- obsolete
       # name() -> return value type
    sig
  when /\A[\w:]+[\.\#]([+\-<>=~*^&|%\/]+)/   # Complex#+
    sig
  when /\Aself\s*(==|===|=~)\s*(\w+)/        # self == other
    "#{$1}(#{$2})"
  when /\A([\w:\.\#]+)\s*\=(\(|\s*\w+)?/   # name=
    "#{remove_class_spec($1)}=(#{remove_paren($2.to_s.strip)})"
  when /\A\w+\[(.*)\]=(.*)/                  # self[key]=
    "[]=(#{$1}, #{$2.strip})"
  when /\A[\w\:]+\[(.*)\]/                   # self[key]
    "[](#{$1})"
  when /\Aself\s*([+\-<>=~*^&|%\/]+)\s*(\w+)/   # self + other
    "#{$1}(#{$2})"
  when /\A([+\-~`])\s*\w+/                   # ~ self
    case op = $1
    when '+', '-' then op + '@'
    else               op
    end
  when /\A(?:[\w:]+[\.\#])?(\[\]=?)/         # Matrix.[](i)
    sig
  when /\A([+\-<>=~*^&|%]+)/                 # +(m)
    sig
  when /\A([A-Z]\w+\*)/                      # HKEY_*
    sig
  when /\Aself([+\-<>=~*^&|%\/\[\]]+)\(\w/   # self+(other)
    sig.sub(/\Aself/, '')
  else
    $stderr.puts "warning: unknown method signature: #{sig.inspect}"
    sig
  end
end

def remove_class_spec(str)
  str.sub(/\A[A-Z]\w*(?:::[A-Z]\w*)*[\.\#]/, '')
end

def remove_paren(str)
  str.sub(/\A\(/, '').sub(/\)\z/, '')
end

def convert_link(line)
  line.gsub(/\(\(\{(.*?)\}\)\)/) { $1 }\
      .gsub(/\(\(\|(.*?)\|\)\)/) { $1 }\
      .gsub(/\(\(<(.*?)>\)\)/) { convert_href($1) }
end

def convert_href(link)
  case link
  when /\Atrap::(.*)/              then "[[trap:#{$1}]]"
  when /\Aruby 1\.\S+ feature/     then "((<#{link}>))"
  when /\Aobsolete/                then "((<obsolete>))"
  when /\A組み込み変数\/(.*)/e     then "[[m:#{$1}]]"
  when /\A組み込み定数\/(.*)/e     then "[[m:Kernel::#{$1}]]"
  when /\A組み込み関数\/(.*)/e     then "[[m:Kernel\##{$1}]]"
  when /\A([\w:]+[\#\.][^|]+)\|/   then "[[m:#{$1}]]"
  when /\A(.*?)\|manual page\z/    then "[[man:#{$1}]]"
  when /\A([\w:]+)\/(.*)\z/n       then "[[m:#{$1}\##{$2}]]"
  when /\A([A-Z][\w:]*)\z/         then "[[c:#{$1}]]"
  else
    "[[unknown:#{link}]]"
  end
end

main
