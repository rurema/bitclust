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
  Pathname.new(__FILE__).realpath.dirname.parent.cleanpath
end

$LOAD_PATH.unshift srcdir_root() + 'lib'

$KCODE = 'EUC'

require 'bitclust'
require 'erb'
require 'find'
require 'optparse'

def main
  Signal.trap(:PIPE) { exit 1 }
  Signal.trap(:INT) { exit 1 }

  prefix = nil
  parser = OptionParser.new
  parser.banner = <<-EndBanner
Usage: #{File.basename($0, '.*')} [global options] <subcommand> [options] [args]

Subcommands:
    init        Initialize database.
    list        List libraries/classes/methods in database.
    lookup      Lookup a library/class/method from database.
    search      Search classes/methods from database.
    property    Handle database properties.
    update      Update database.

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
  subcommands['search'] = BitClust::Searcher.new
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
rescue BitClust::UserError => err
  $stderr.puts err.message
  exit 1
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
    @format = :text
    @type = nil
    @key = nil
    @parser = OptionParser.new {|opt|
      opt.banner = "Usage: #{File.basename($0, '.*')} lookup (--library|--class|--method) [--html] <key>"
      opt.on('--library=NAME', 'Lookup library.') {|name|
        @type = :library
        @key = name
      }
      opt.on('--class=NAME', 'Lookup class.') {|name|
        @type = :class
        @key = name
      }
      opt.on('--method=NAME', 'Lookup method.') {|name|
        @type = :method
        @key = name
      }
      opt.on('--html', 'Show result in HTML.') {
        @format = :html
      }
      opt.on('--help', 'Prints this message and quit.') {
        puts opt.help
        exit 0
      }
    }
  end

  def parse(argv)
    @parser.parse! argv
    unless @type
      error "one of --library/--class/--method is required"
    end
    unless argv.empty?
      error "too many arguments"
    end
  end

  def exec(db, argv)
    entry = fetch_entry(db, @type, @key)
    puts fill_template(get_template(@type, @format), entry)
  end

  def fetch_entry(db, type, key)
    case type
    when :library
      db.fetch_library(key)
    when :class
      db.fetch_class(key)
    when :method
      db.fetch_method(BitClust::MethodSpec.parse(key))
    else
      raise "must not happen: #{type.inspect}"
    end
  end

  def fill_template(template, entry)
    ERB.new(template).result(binding())
  end

  def get_template(type, format)
    template = TEMPLATE[type][format]
    BitClust::TextUtils.unindent_block(template).join('')
  end

  TEMPLATE = {
    :library => {
       :text => <<-End,
           type: library
           name: <%= entry.name %>
           classes: <%= entry.classes.map {|c| c.name }.sort.join(', ') %>
           methods: <%= entry.methods.map {|m| m.name }.sort.join(', ') %>

           <%= entry.source %>
           End
       :html => <<-End
           <dl>
           <dt>type</dt><dd>library</dd>
           <dt>name</dt><dd><%= entry.name %></dd>
           <dt>classes</dt><dd><%= entry.classes.map {|c| c.name }.sort.join(', ') %></dd>
           <dt>methods</dt><dd><%= entry.methods.map {|m| m.name }.sort.join(', ') %></dd>
           </dl>
           <%= compile_rd(entry.source) %>
           End
    },
    :class   => {
       :text => <<-End,
           type: class
           name: <%= entry.name %>
           library: <%= entry.library.name %>
           singleton_methods: <%= entry.singleton_methods.map {|m| m.name }.sort.join(', ') %>
           instance_methods: <%= entry.instance_methods.map {|m| m.name }.sort.join(', ') %>
           constants: <%= entry.constants.map {|m| m.name }.sort.join(', ') %>
           special_variables: <%= entry.special_variables.map {|m| '$' + m.name }.sort.join(', ') %>

           <%= entry.source %>
           End
       :html => <<-End
           <dl>
           <dt>type</dt><dd>class</dd>
           <dt>name</dt><dd><%= entry.name %></dd>
           <dt>library</dt><dd><%= entry.library.name %></dd>
           <dt>singleton_methods</dt><dd><%= entry.singleton_methods.map {|m| m.name }.sort.join(', ') %></dd>
           <dt>instance_methods</dt><dd><%= entry.instance_methods.map {|m| m.name }.sort.join(', ') %></dd>
           </dl>
           <%= compile_rd(entry.source) %>
           End
    },
    :method  => {
       :text => <<-End,
           type: <%= entry.type %>
           name: <%= entry.name %>
           names: <%= entry.names.sort.join(', ') %>
           visibility: <%= entry.visibility %>
           kind: <%= entry.kind %>
           library: <%= entry.library.name %>

           <%= entry.source %>
           End
       :html => <<-End
           <dl>
           <dt>type</dt><dd><%= entry.type %></dd>
           <dt>name</dt><dd><%= entry.name %></dd>
           <dt>names</dt><dd><%= entry.names.sort.join(', ') %></dd>
           <dt>visibility</dt><dd><%= entry.visibility %></dd>
           <dt>kind</dt><dd><%= entry.kind %></dd>
           <dt>library</dt><dd><%= entry.library.name %></dd>
           </dl>
           <%= compile_rd(entry.source) %>
           End
    }
  }

  def compile_rd(src)
    umap = BitClust::URLMapper.new(:base_url => 'http://example.com',
                                   :cgi_url  => 'http://example.com/view')
    compiler = BitClust::RDCompiler.new(umap, 2)
    compiler.compile(src)
  end

end

main
