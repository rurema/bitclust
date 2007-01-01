#!/usr/bin/env ruby

class Error < StandardError; end

def main
  entries = parse(find_basedir(ARGV[0]))
  puts '--- Status'
  done = entries.select {|ent| ent.done? }.size
  puts "#{done}/#{entries.size} files done (#{percent_str(done, entries.size)})"
  puts
  puts '--- Ranking by number of files'
  ranking_table(entries) {|ent| 1 }.each_with_index do |(owner, n), idx|
    printf "%2d %4d %-s\n", idx + 1, n, (owner || '(not yet)')
  end
  puts
  puts '--- Ranking by Kbytes'
  ranking_table(entries) {|ent| ent.size }.each_with_index do |(owner,n), idx|
    printf "%2d %4d %-s\n", idx + 1, kb(n), (owner || '(not yet)')
  end
rescue Error => err
  $stderr.puts err.message
  exit 1
end

def find_basedir(dir)
  [ dir, "#{dir}/api", "#{dir}/refm/api", "#{dir}/.." ].each do |basedir|
    if File.file?("#{basedir}/ASSIGN")
      return basedir
    end
  end
  raise Error, "error: wrong directory: #{dir}"
end

def percent_str(n, base)
  sprintf('%0.2f%%', percent(n, base))
end

def percent(n, base)
  n * 100 / base.to_f
end

def kb(bytes)
  if bytes % 1024 == 0
    bytes / 1024
  else
    (bytes / 1024) + 1
  end
end

def ranking_table(entries)
  h = Hash.new(0)
  entries.each do |ent|
    h[ent.done? ? ent.owner : nil] += yield(ent)
  end
  h.to_a.sort_by {|owner, n| -n }
end

def parse(basedir)
  File.open("#{basedir}/ASSIGN") {|f|
    f.map {|line|
      next if line.strip.empty?
      next if /\A\#/ =~ line
      Entry.new(basedir, *line.split)
    }.compact
  }
end

class Entry
  def initialize(basedir, name, owner = nil, status = nil)
    @basedir = basedir
    @name = name
    @owner = owner
    @status = status
    @path = nil
  end

  attr_reader :name
  attr_reader :owner
  attr_reader :status

  def done?
    @status == 'done'
  end

  def size
    File.size(path())
  rescue Error
    0
  end

  def path
    @path ||= ["#{@basedir}/src/#{@name}.rd",
               "#{@basedir}/src/#{@name}"].detect {|path| File.file?(path) } or
        raise Error, "file not found: library #{@name}"
  end
end

main
