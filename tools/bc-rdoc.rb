#!/usr/bin/env ruby
#
# bc-rdoc.rb -- handle rdoc (ri) database.
#
# "bc-rdoc history" code is derived from bc-history.rb, posted in
# [ruby-reference-manual:150] by moriq.
#

require 'pathname'

srcdir_root = Pathname.new(__FILE__).realpath.dirname.parent.cleanpath
$LOAD_PATH.unshift srcdir_root + 'lib'

require 'bitclust'
require 'bitclust/ridatabase'
require 'rdoc/ri/ri_reader'
require 'rdoc/ri/ri_cache'
require 'rdoc/ri/ri_paths'
require 'rdoc/markup/simple_markup/fragments'
require 'stringio'
require 'pp'
require 'optparse'

class ApplicationError < StandardError; end
class RiClassNotFound < ApplicationError; end

def main
  Signal.trap(:PIPE) { exit 1 } rescue nil   # Win32 does not have SIGPIPE
  Signal.trap(:INT) { exit 1 }

  parser = OptionParser.new
  parser.banner = <<-EndUsage
Usage: #{File.basename($0)} (list|diff|history) [options]

Subcommands:
    list        List methods stored in ri database.
    diff        Compare between BitClust and ri database.
    history     Show class/method history stored in ri database.

Global Options:
EndUsage
  parser.on('--help', 'Prints this message and quit.') {
    puts parser.help
    exit 0
  }
  begin
    parser.order!
  rescue OptionParser::ParseError => err
    $stderr.puts err.message
    $stderr.puts parser.help
    exit 1
  end

  subcommands = {
    'list'    => ListCommand.new,
    'diff'    => DiffCommand.new,
    'history' => HistoryCommand.new
  }
  subcommands['hist'] = subcommands['history']
  unless ARGV[0]
    $stderr.puts 'no subcommand given'
    $stderr.puts parser.help
    exit 1
  end
  unless subcommands.key?(ARGV[0])
    $stderr.puts "unknown subcommand: #{ARGV[0].inspect}"
    $stderr.puts parser.help
    exit 1
  end
  sub = subcommands[ARGV.shift]
  begin
    sub.parse ARGV
  rescue OptionParser::ParseError => err
    $stderr.puts err.message
    $stderr.puts sub.parser.help
    exit 1
  end
  sub.exec
rescue Errno::EPIPE
  exit 1
rescue ApplicationError, BitClust::UserError => err
  $stderr.puts err.message
  exit 1
end


class Subcommand

  def open_ri_database(prefix)
    if prefix
      RiDatabase.open(prefix, nil)
    else
      RiDatabase.open_system_db
    end
  end

end


class ListCommand < Subcommand

  def initialize
    @prefix = nil
    @type = :name
    @parser = OptionParser.new
    @parser.banner = "Usage: #{File.basename($0, '.*')} list"
    @parser.on('--ri-database=PREFIX', 'Ri database prefix') {|path|
      @prefix = path
    }
    @parser.on('-c', '--content', 'Prints method description') {
      @type = :content
    }
    @parser.on('--help', 'Prints this message and quit.') {
      puts @parser.help
      exit 0
    }
  end

  attr_reader :parser

  def parse(argv)
    @parser.parse! argv
    unless argv.size == 1
      $stderr.puts "class name not given"
      exit 1
    end
    @classname = argv[0]
    @ri = open_ri_database(@prefix)
  end

  def exec
    c = @ri.lookup_class(@classname)
    case @type
    when :name
      c.method_entries.each do |m|
        puts m.fullname
      end
    when :content
      fmt = Formatter.new
      c.method_entries.each do |m|
        puts fmt.method_info(@ri.get_method(m))
      end
    end
  end

end


class DiffCommand < Subcommand

  def initialize
    @bcprefix = nil
    @riprefix = nil
    @type = :name
    @parser = OptionParser.new
    @parser.banner = "Usage: #{File.basename($0, '.*')} diff --bc=PATH --ri=PATH <classname>"
    @parser.on('--bc-database=PREFIX', 'BitClust database prefix') {|path|
      @bcprefix = path
    }
    @parser.on('--ri-database=PREFIX', 'Ri database prefix') {|path|
      @riprefix = path
    }
    @parser.on('-c', '--content', 'Prints method description') {
      @type = :content
    }
    @parser.on('--help', 'Prints this message and quit.') {
      puts @parser.help
      exit 0
    }
  end

  attr_reader :parser

  def parse(argv)
    @parser.parse! argv
    unless @bcprefix
      $stderr.puts 'missing BitClust database prefix.  Use --bc option'
      exit 1
    end
    @bc = BitClust::MethodDatabase.new(@bcprefix)
    @ri = open_ri_database(@riprefix)
    unless argv.size == 1
      $stderr.puts "wrong number of arguments (#{argv.size} for 1)"
      $stderr.puts @parser.help
      exit 1
    end
    @classname = argv[0]
  end

  def exec
    @ri.current_class = @classname
    win, lose = *diff_class(bc_lookup_class(@classname), @ri)
    case @type
    when :name
      win.each do |m|
        puts "+ #{m.id}"
      end
      lose.each do |m|
        puts "- #{m.fullname}"
      end
    when :content
      fmt = Formatter.new
      lose.each do |m|
#        puts "\#@\# bc-rdoc: detected missing name: #{m.name}"
        puts fmt.method_info(m.entry)
      end
    end
  end

  def bc_lookup_class(classname)
    @bc.fetch_class(classname)
  rescue BitClust::ClassNotFound
    $stderr.puts "warning: class #{classname} not exist in BitClust database"
    @bc.get_class(classname)
  end

  def diff_class(bc, ri)
    unzip(diff_entries(bc, bc_wrap(bc.singleton_methods), ri.singleton_methods),
          diff_entries(bc, bc_wrap(bc.instance_methods),  ri.instance_methods))\
        .map {|list| list.flatten }
  end

  def bc_wrap(ents)
    ents.map {|m|
      m.names.map {|name| BCMethodEntry.new(name, m) }
    }.flatten.uniq
  end

  def unzip(*tuples)
    [tuples.map {|s, i| s }, tuples.map {|s, i| i }]
  end

  def diff_entries(bc_class, bc, ri)
    bc = bc.sort
    ri = ri.sort
    [bc - ri, (ri - bc).reject {|m| true_exist?(bc_class, m) }]
  end

  def true_exist?(c, m)
    if m.singleton_method?
      c.singleton_method?(m.name, true)
    else
      c.instance_method?(m.name, true)
    end
  end

end


class HistoryCommand < Subcommand

  def initialize
    @riprefix = nil
    @parser = OptionParser.new
    @parser.banner = "Usage: #{File.basename($0, '.*')} history --ri=PATH <classname>"
    @parser.on('--ri-database=PREFIX', 'Ri database prefix') {|path|
      @riprefix = path
    }
    @parser.on('--help', 'Prints this message and quit.') {
      puts @parser.help
      exit 0
    }
  end

  attr_reader :parser

  def parse(argv)
    @parser.parse! argv
    unless @riprefix
      $stderr.puts 'ri database not given; use --ri option'
      exit 1
    end
    @ris = Dir.glob("#{@riprefix}/1.*").map {|dir|
      RiDatabase.open(dir, File.basename(dir))
    }
    if @ris.empty?
      $stderr.puts 'wrong ri database directory; directories like <path>/1.8.3/, <path>/1.8.4/, ... must exist'
      exit 1
    end
    unless argv.size == 1
      $stderr.puts "wrong number of arguments (#{argv.size} for 1)"
      $stderr.puts @parser.help
      exit 1
    end
    @classname = argv[0]
  end

  def exec
    @ris.each do |ri|
      ri.current_class = @classname
    end
    s = {}
    i = {}
    @ris.each do |ri|
      ri.singleton_methods.each do |m|
        (s[m] ||= []).push ri.version
      end
      ri.instance_methods.each do |m|
        (i[m] ||= []).push ri.version
      end
    end
    namecols = calculate_n_namecols(s.keys + i.keys)
    versions = @ris.map {|ri| ri.version }
    print_header namecols, versions
    print_records namecols, versions, (s.to_a + i.to_a)
  end

  def calculate_n_namecols(ms)
    tabstop = 8
    maxnamelen = ms.map {|m| m.fullname.size }.max
    (maxnamelen / tabstop + 1) * tabstop
  end

  def print_header(namecols, versions)
    print ' ' * namecols
    versions.each do |ver|
      printf '%4s', ver.tr('.', '')
    end
    puts
  end

  def print_records(namecols, versions, records)
    veridx = {}
    versions.each_with_index do |ver, idx|
      veridx[ver] = idx
    end
    records.sort_by {|m, vers| m.fullname }.each do |m, vers|
      printf "%-#{namecols}s", m.fullname

      fmt = '%4s' * versions.size
      cols = ['-'] * versions.size
      vers.each do |ver|
        cols[veridx[ver]] = 'o'
      end
      printf fmt, *cols
      puts
    end
  end

end


main
