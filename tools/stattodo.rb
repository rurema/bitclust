#!/usr/bin/env ruby

require 'pathname'

bindir = Pathname.new(__FILE__).realpath.dirname
$LOAD_PATH.unshift((bindir + '../lib').realpath)

require 'bitclust/preprocessor'
require 'find'

#ALL = 14349

def main
  cmd, hist, prefix = ARGV[0], ARGV[1], ARGV[2]
  case cmd
  when 'count'
    count hist, prefix
  when 'update'
    update hist, prefix
  else
    $stderr.puts "unknown command: #{cmd}"
    exit 1
  end
end

def count(hist, prefix)
  total = 0
  curr = 0
  Table.parse_file(hist).each do |ent|
    n = count_todo_in_file(File.join(prefix, ent.name))
    curr += n
    total += ent.total
    report_count ent.name, n, ent.total
  end
  report_count 'TOTAL', curr, total
end

def report_count(label, curr, all)
  done = all - curr
  printf "%-24s %5d/%5d (%6.2f%%)\n", label, done, all, percent(done, all)
end

def percent(done, all)
  return 0 if all == 0
  done * 100 / all.to_f
end

def update(hist, prefix)
  table = Table.parse_file(hist)
  table.each do |ent|
    ent.push count_todo(File.join(prefix, ent.name))
  end
  File.open("#{hist}.tmp", 'w') {|f|
    f.puts table.header
    table.each do |ent|
      f.puts ent.serialize
    end
  }
  File.rename "#{hist}.tmp", hist
end

def count_todo(path)
  if File.directory?(path)
    count_todo_in_dir(path)
  else
    count_todo_in_file(path)
  end
end

def count_todo_in_dir(dir)
  n = 0
  Dir.entries(dir).each do |ent|
    next if /\A\./ =~ ent
    path = File.join(dir, ent)
    if File.extname(ent) == '.rd' and File.file?(path)
      n += count_todo_in_file(path)
    elsif File.directory?(path)
      n += count_todo_in_dir(path)
    end
  end
  n
end

def count_todo_in_file(path)
  n = 0
  File.open(path) {|f|
    pp = BitClust::LineCollector.wrap(f)
    pp.grep(/\A\#@todo/) { n += 1 }
  }
  n
end

class Table
  def Table.parse_file(path)
    File.open(path) {|f|
      _, *dates = f.gets.split
      ents = f.map {|line|
        name, *ns = line.split
        Entry.new(name, ns.map {|n| n.to_i })
      }
      return new(dates, ents)
    }
  end

  include Enumerable

  def initialize(dates, ents)
    @dates = dates
    @entries = ents
  end

  attr_reader :dates
  attr_reader :entries

  def header
    (["-"] + @dates).join(' ')
  end

  def each(&block)
    @entries.each(&block)
  end
end

class Entry
  def initialize(name, ns)
    @name = name
    @counts = ns
  end

  attr_reader :name
  attr_reader :counts

  def total
    @counts.first
  end

  def count
    @counts.last
  end

  def push(n)
    @counts.push n
  end

  def serialize
    @name + "\t" + @counts.join("\t")
  end
end

main
