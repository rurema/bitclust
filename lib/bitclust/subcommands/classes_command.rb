require 'pathname'
require 'optparse'

require 'bitclust/crossrubyutils'

module BitClust
  module Subcommands
    class ClassesCommand < Subcommand
      include CrossRubyUtils

      def initialize
        super
        @rejects = []
        @verbose = false
        @parser.banner = "Usage: #{File.basename($0, '.*')} [-r<lib>] <lib>"
        @parser.on('-r', '--reject=LIB', 'Reject library LIB') {|lib|
          @rejects.concat lib.split(',')
        }
        @parser.on('-v', '--verbose', 'Show all ruby version.') {
          @verbose = true
        }
      end

      def parse(argv)
        super
        option_error('wrong number of arguments') unless argv.size == 1
      end

      def exec(argv, options)
        lib = argv[0]
        print_crossruby_table {|ruby| defined_classes(ruby, lib, @rejects) }
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
