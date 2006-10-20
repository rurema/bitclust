#
# bitclust/searcher.rb
#
# Copyright (C) 2006 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the Ruby License.
#

require 'bitclust/nameutils'
require 'bitclust/exception'
require 'rbconfig'
require 'optparse'

module BitClust

  class Searcher

    include NameUtils

    def initialize
      cmd = File.basename($0, '.*')
      @dbpath = nil
      @name = (cmd == 'bitclust' ? 'bitclust search' : 'refe')
      @describe_all = false
      @linep = false
      @parser = OptionParser.new {|opt|
        opt.banner = "Usage: #{@name} <pattern>"
        unless cmd == 'bitclust'
          opt.on('-d', '--database=PATH', "Database location (default: #{dbpath_name()})") {|prefix|
            @dbpath = prefix
          }
        end
        opt.on('-a', '--all', 'Prints descriptions for all matched entries.') {
          @describe_all = true
        }
        opt.on('-l', '--line', 'Prints one entry in one line.') {
          @linep = true
        }
        opt.on('--version', 'Prints version and quit.') {
          if cmd == 'bitclust'
            puts "BitClust -- Next generation reference manual interface"
            exit 1
          else
            puts "ReFe version 2"
            exit 1
          end
        }
        opt.on('--help', 'Prints this message and quit.') {
          puts opt.help
          exit 0
        }
      }
    end

    def parse(argv)
      @parser.parse! argv
      if argv.size > 3
        $stderr.puts "too many arguments (#{argv.size} for 2)"
        exit 1
      end
    end

    def exec(db, argv)
      #compiler = RDCompiler::Text.new
      db ||= Database.new(@dbpath || dbpath())
      compiler = Plain.new   # FIXME
      view = TerminalView.new(compiler,
                              {:describe_all => @describe_all, :line => @linep})
      case argv.size
      when 0
        view.show_class db.classes
      when 1
        _m, _t, _c = argv[0].reverse.split(/(\#[\.,]|[\.,]\#|[\#\.\,]|::)/, 2)
        if _t
          c = _c.reverse
          t = _t.tr(',', '.').sub(/\#\./, '.#')
          m = _m.reverse
        else
          c = nil
          t = nil
          m = argv[0]
        end
        pattern = SearchPattern.for_ctm(c, t, m)
        view.show_method db.search_methods(pattern)
      when 2
        c, m = *argv
        pattern = SearchPattern.for_ctm(c, nil, m)
        view.show_method db.search_methods(pattern)
      when 3
        c, t, m = *argv
        unless typemark?(t)
          raise InvalidSearchPattern, "unknown method type: #{t.inspect}"
        end
        pattern = SearchPattern.for_ctm(c, t, m)
        view.show_method db.search_methods(pattern)
      else
        raise "must not happen: #{argv.size}"
      end
    end

    private

    def dbpath_name
      env_dbpath() or default_dbpath() or '(none)'
    end

    def dbpath
      env_dbpath() or default_dbpath() or
          raise InvalidDatabase, "database not found"
    end

    def env_dbpath
      [ 'REFE2_DATADIR', 'BITCLUST_DATADIR' ].each do |key|
        if ENV.key?(key)
          unless Database.datadir?(ENV[key])
            raise InvalidDatabase, "environment variable #{key} given but #{ENV[key]} is not a valid BitClust database"
          end
          return ENV[key]
        end
      end
      nil
    end

    def default_dbpath
      [ "#{::Config::CONFIG['datadir']}/refe2",
        "#{::Config::CONFIG['datadir']}/bitclust" ].each do |prefix|
        return prefix if Database.datadir?(prefix)
      end
      nil
    end

  end


  class Plain
    def compile(src)
      src
    end
  end


  class TerminalView

    def initialize(compiler, opts)
      @compiler = compiler
      @describe_all = opts[:describe_all]
      @line = opts[:line]
    end

    def show_class(cs)
      if cs.size == 1
        if @line
          print_names [cs.first.label]
        else
          describe_class cs.first
        end
      else
        if @describe_all
          cs.sort_by {|c| c.name }.each do |c|
            describe_class c
          end
        else
          print_names cs.map {|c| c.labels }.flatten.sort
        end
      end
    end

    def show_method(ms)
      if ms.size == 1
        if @line
          print_names [ms.first.label]
        else
          describe_method ms.first
        end
      else
        if @describe_all
          ms.sort_by {|m| m.id }.each do |m|
            describe_method m
          end
        else
          print_names ms.map {|m| m.labels }.flatten.sort
        end
      end
    end

    private

    def print_names(names)
      if @line
        names.each do |n|
          puts n
        end
      else
        print_packed_names names
      end
    end

    def print_packed_names(names)
      max = terminal_column()
      buf = ''
      names.each do |name|
        if buf.size + name.size + 1 > max
          if buf.empty?
            puts name
            next
          end
          puts buf
          buf = ''
        end
        buf << name << ' '
      end
      puts buf unless buf.empty?
    end

    def terminal_column
      (ENV['COLUMNS'] || 70).to_i
    end

    def describe_class(c)
      puts "#{c.type} #{c.name}#{c.superclass ? " < #{c.superclass.name}" : ''}"
      unless c.included.empty?
        puts
        c.included.each do |mod|
          puts "include #{mod.name}"
        end
      end
      unless c.library.name == '_builtin'
        puts
        puts "require '#{c.library.name}'"
      end
      unless c.source.strip.empty?
        puts
        puts @compiler.compile(c.source.strip)
      end
    end

    def describe_method(m)
      unless m.library.name == '_builtin'
        puts "require '#{m.library.name}'"
      end
      puts m.label   # FIXME: replace method signature by method spec
      puts @compiler.compile(m.source.strip)
      puts
    end

  end

end
