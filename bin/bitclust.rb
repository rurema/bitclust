#!/usr/bin/env ruby
#
# bitclust.rb
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
require 'find'
require 'optparse'

def main
  prefix = nil

  parser = OptionParser.new
  parser.banner = <<-EndBanner
Usage: #{File.basename($0, '.*')} [global options] <subcommand> [options] [args]

Subcommands:
    init        Initialize database.
    update      Update database.
    list        List libraries/classes/methods in database.
    lookup      Lookup libraries/classes/methods from database.
    property    Handle database properties.

Global Options:
  EndBanner
  parser.on('-d', '--database=PATH', 'Database prefix.') {|path|
    prefix = path
  }
  parser.on('--help', 'Prints this message and quit.') {
    puts parser.help
    exit 0
  }

  subcommands = {}
  subcommands['init'] = InitCommand.new
  subcommands['update'] = UpdateCommand.new
  subcommands['list'] = ListCommand.new
  subcommands['lookup'] = LookupCommand.new
  begin
    parser.order!
    error 'no sub-command given' if ARGV.empty?
    name = ARGV.shift
    cmd = subcommands[name] or error "no such sub-command: #{name}"
    cmd.parse(ARGV)
  rescue OptionParser::ParseError => err
    $stderr.puts err.message
    $stderr.puts parser.help
    exit 1
  end
  unless prefix
    $stderr.puts "no database given. Use --database option"
    exit 1
  end
  db = BitClust::Database.new(prefix)
  cmd.exec db, ARGV
end

def error(msg)
  $stderr.puts "#{File.basename($0, '.*')}: #{msg}"
  exit 1
end

class InitCommand
  def initialize
    @parser = OptionParser.new {|opt|
      opt.banner = "Usage: #{File.basename($0, '.*')} init [KEY=VALUE ...]"
      opt.on('--help', 'Prints this message and quit.') {
        puts opt.help
        exit 0
      }
    }
  end

  def parse(argv)
    @parser.parse! argv
  end

  def exec(db, argv)
    db.init
    db.transaction {
      argv.each do |kv|
        k, v = kv.split('=', 2)
        db.propset k, v
      end
    }
  end
end

class UpdateCommand
  def initialize
    @root = nil
    @library = nil
    @parser = OptionParser.new {|opt|
      opt.banner = "Usage: #{File.basename($0, '.*')} update [<file>...]"
      opt.on('--stdlibtree=ROOT', 'Process stdlib source directory tree.') {|path|
        @root = path
      }
      opt.on('--library-name=NAME', 'Use NAME for library name in file mode.') {|name|
        @library = name
      }
      opt.on('--help', 'Prints this message and quit.') {
        puts opt.help
        exit 0
      }
    }
  end

  def parse(argv)
    @parser.parse! argv
    if not @root and argv.empty?
      error "no file given"
    end
  end

  def exec(db, argv)
    db.transaction {
      if @root
        process_stdlib_tree db, @root
      end
      argv.each do |path|
        db.update_by_file path, @library || guess_library_name(path)
      end
    }
  end

  private

  def process_stdlib_tree(db, root)
    Dir.glob("#{root}/_builtin/*.rd") do |path|
      db.update_by_file path, '_builtin'
    end
    re = %r<\A#{Regexp.quote(root)}/>
    Dir.glob("#{root}/**/*.rd").each do |path|
      libname = path.sub(re, '').sub(/\.rd\z/, '')
      next if %r<\A_builtin/> =~ libname
      db.update_by_file path, libname
    end
  end

  def guess_library_name(path)
    if %r<(\A|/)src/> =~ path
      path.sub(%r<.*(\A|/)src/>, '').sub(/\.rd\z/, '')
    else
      path
    end
  end
end

class ListCommand
  def initialize
    @mode = nil
    @parser = OptionParser.new {|opt|
      opt.banner = "Usage: #{File.basename($0, '.*')} list (--library|--class|--method)"
      opt.on('--library', 'List libraries.') {
        @mode = :library
      }
      opt.on('--class', 'List classes.') {
        @mode = :class
      }
      opt.on('--method', 'List methods.') {
        @mode = :method
      }
      opt.on('--help', 'Prints this message and quit.') {
        puts opt.help
        exit 0
      }
    }
  end

  def parse(argv)
    @parser.parse! argv
    unless @mode
      error 'one of (--library|--class|--method) is required'
    end
  end

  def exec(db, argv)
    case @mode
    when :library
      db.libraries.each do |lib|
        puts lib.name
      end
    when :class
      db.classes.map {|c| c.name }.sort.each do |name|
        puts name
      end
    when :method
      db.classes.sort_by {|c| c.name }.each do |c|
        c.entries.sort_by {|m| m.id }.each do |m|
          puts m.label
        end
      end
    else
      raise "must not happen: @mode=#{@mode.inspect}"
    end
  end
end

class LookupCommand
  def initialize
    @html_p = false
    @parser = OptionParser.new {|opt|
      opt.banner = "Usage: #{File.basename($0, '.*')} lookup (--library|--class|--method) <keys>"
      opt.on('--library', 'Lookup libraries.') {
      }
      opt.on('--class', 'Lookup classes.') {
      }
      opt.on('--method', 'Lookup methods.') {
      }
      opt.on('--html', 'Show result in HTML.') {
        @html_p = true
      }
      opt.on('--help', 'Prints this message and quit.') {
        puts opt.help
        exit 0
      }
    }
  end

  def parse(argv)
    @parser.parse! argv
raise 'FIXME'
  end

  def exec(db, argv)
raise 'FIXME'
  end
end

main
