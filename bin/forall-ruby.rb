#!/usr/bin/env ruby

def main
  rubys(ENV['PATH']).each do |cmd|
    system cmd, '-v', *ARGV
  end
end

def rubys(path)
  parse_PATH(path).map {|bindir|
    Dir.glob("#{bindir}/ruby-*").map {|path| File.basename(path) }
  }\
  .flatten.uniq.sort_by {|name| [-name.size, name] } + ['ruby']
end

def parse_PATH(str)
  str.split(':').map {|path| path.empty? ? '.' : path }
end

main
