#!/usr/bin/env ruby

require 'find'

ALL = 14349

def main
  n = count_todo(ARGV[0])
  puts "#{n} / #{ALL} (#{n * 100 / ALL.to_f}%)"
end

def count_todo(dir)
  n = 0
  Find.find(dir) {|path|
    Find.prune if File.basename(path) == '.svn'
    if File.file?(path)
      File.open(path) {|f|
        f.grep(/\A\#@todo/) { n += 1 }
      }
    end
  }
  n
end

main
