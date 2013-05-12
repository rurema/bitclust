require 'bitclust'
require 'bitclust/crossrubyutils'

require 'pathname'
require 'optparse'
require 'set'

module BitClust
  module Subcommands
    class AncestorsCommand < Subcommand
      include CrossRubyUtils

      def initialize
        super
        @prefix = nil
        @requires = []
        @version = RUBY_VERSION
        @all = false
        @verbose = false
        @parser.banner = <<-BANNER
Usage: #{File.basename($0, '.*')} ancestors [-r<lib>] [--ruby=<VER>] --db=PATH <classname>
       #{File.basename($0, '.*')} ancestors [-r<lib>] [--ruby=<VER>] --db=PATH --all
NG Sample:
  $ #{File.basename($0, '.*')} ancestors -rfoo --ruby=1.9.1 --db=./db Foo
  NG : Foo
  + FooModule (The Ruby have this class/module in ancestors of the class)
  - BarModule (The Database have this class/module in ancestors of the class)
Options:
        BANNER
        @parser.on('-d', '--database=PATH', 'Database prefix.') {|path|
          @prefix = path
        }
        @parser.on('-r LIB', 'Requires library LIB') {|lib|
          @requires.push lib
        }
        @parser.on('--ruby=[VER]', "The version of Ruby interpreter"){|ver|
          @version = ver
        }
        @parser.on('-v', '--verbose', 'Show differences'){
          @verbose = true
        }
        @parser.on('--all', 'Check anccestors for all classes'){
          @all = true
        }
      end

      def exec(argv, options)
        classname = argv[0]
        db = MethodDatabase.new(@prefix)
        ruby = get_ruby(@version)
        if classname && !@all
          check_ancestors(db, ruby, @requires, classname)
        else
          $stderr.puts 'check all...'
          check_all_ancestors(db, ruby, @requires)
        end
      end

      private

      def ancestors(ruby, requires, classname)
        req = requires.map{|lib|
          unless '_builtin' == lib
            "-r#{lib}"
          else
            ''
          end
        }.join(" ")
        script = <<-SRC
          c = #{classname}
          puts c.ancestors.join("\n")
        SRC
        puts "#{ruby} #{req} -e '#{script}'"
        `#{ruby} #{req} -e '#{script}'`.split
      end

      def check_ancestors(db, ruby, requires, classname)
        a = ancestors(ruby, requires, classname)
        p a
        begin
          b = db.fetch_class(classname).ancestors.map(&:name)
        rescue ClassNotFound => ex
          $stderr.puts ex.backtrace
          $stderr.puts "class not found in database : #{classname}"
          b = []
        end
        unless a.to_set == b.to_set
          puts "NG : #{classname}"
          puts (a-b).map{|c| "+ #{c}" }.join("\n")
          puts (b-a).map{|c| "- #{c}" }.join("\n")
        else
          puts "OK : #{classname}" if @verbose
        end
      end

      def check_all_ancestors(db, ruby, requires)
        classnames = []
        requires.each do |lib|
          classnames.push(*defined_classes(ruby, lib, []))
        end
        classnames.each do |classname|
          check_ancestors(db, ruby, requires, classname)
        end
      end

      def defined_classes(ruby, lib, rejects)
        script = <<-SCRIPT
          def class_extent
            result = []
            ObjectSpace.each_object(Module) do |c|
              result.push c
            end
            result
          end

          %w(#{rejects.join(" ")}).each do |lib|
            begin
              require lib
            rescue LoadError
            end
          end
          if "#{lib}" == "_builtin"
            class_extent().each do |c|
              puts c
            end
          else
            before = class_extent()
            begin
              require "#{lib}"
            rescue LoadError
              $stderr.puts "\#{RUBY_VERSION} (\#{RUBY_RELEASE_DATE}): library not exist: #{lib}"
              exit
            end
            after = class_extent()
            (after - before).each do |c|
              puts c
            end
          end
        SCRIPT
        output = `#{ruby} -e '#{script}'`
        output.split
      end
    end
  end
end
