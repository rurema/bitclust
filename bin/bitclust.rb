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
require 'optparse'

def main
  prefix = nil

  parser = OptionParser.new
  parser.banner = "Usage: #{File.basename($0, '.*')} (init|update|list|lookup) [options]"
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
    cmd.parse!(ARGV)
  rescue OptionParser::ParseError => err
    $stderr.puts err.message
    $stderr.puts parser.help
    exit 1
  end
  db = BitClust::Database.new(prefix)
  cmd.exec db
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

  def parse!(argv)
    @parser.parse! argv
  end

  def exec(db)
    db.init
    db.transction {
      ARGV.each do |kv|
        k, v = kv.split('=', 2)
        db.propset k, v
      end
    }
  end
end

class UpdateCommand
  def initialize
    @mode = :file
    @library = nil
    @parser = OptionParser.new {|opt|
      opt.banner = "Usage: #{File.basename($0, '.*')} update <file>..."
      opt.on('--tree', 'Process RD source directory tree.') {
        @mode = :tree
      }
      opt.on('--library=NAME', 'Use NAME for library name.') {|name|
        @library = name
      }
      opt.on('--help', 'Prints this message and quit.') {
        puts opt.help
        exit 0
      }
    }
  end

  def parse!(argv)
    @parser.parse! argv
    if argv.empty?
      error "no file given"
    end
  end

  def exec(db)
    case @mode
    when :file
      db.transaction {
        ARGV.each do |path|
          db.update_by_file path, library_name(path)
        end
      }
    when :tree
raise 'FIXME'
    else
      raise 'must not happen'
    end
  end

  private

  def library_name(path)
    return @library if @library
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

  def parse!(argv)
    @parser.parse! argv
    unless @mode
      error 'one of (--library|--class|--method) is required'
    end
  end

  def exec(db)
    case @mode
    when :library
    when :class
raise 'FIXME'
    when :method
raise 'FIXME'
    else
      raise 'must not happen'
    end
  end
end

class LookupCommand
  def initialize
    @html_p = false
    @parser = OptionParser.new {|opt|
      opt.banner = "Usage: #{File.basename($0, '.*')} lookup (--library|--class|--method) <key>"
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

  def parse!(argv)
raise 'FIXME'
    @parser.parse! argv
  end

  def exec(db)
raise 'FIXME'
  end
end

main
