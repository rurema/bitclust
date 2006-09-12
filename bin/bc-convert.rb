#!/usr/bin/env ruby

$KCODE = 'EUC'

def main
  ARGF.each do |line|
    case line
    when /\A\#/
      puts '#@' + line
    when /\A---\s/
      puts '--- ' + convert_signature(line.rstrip)
    else
      puts convert_link(line.rstrip)
    end
  end
end

def convert_signature(line)
  sig = line.sub(/\A(:|---)/, '').sub(/\(\(<ruby.*?feature>\)\)/i, '').strip
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
  when /\Aself\s*([+\-<>=~*^&|%\/]+)\s*(\w)/   # self + other
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
  when /\A(.*?)\/manual page\z/    then "[[man:#{$1}]]"
  when /\A([\w:]+)\/(.*)\z/n       then "[[m:#{$1}\##{$2}]]"
  when /\A([A-Z][\w:]*)\z/         then "[[c:#{$1}]]"
  else
    "[[unknown:#{link}]]"
  end
end

main
