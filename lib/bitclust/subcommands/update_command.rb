require 'pathname'
require 'erb'
require 'find'
require 'pp'
require 'optparse'
require 'yaml'

require 'bitclust'
require 'bitclust/subcommand'

module BitClust
  module Subcommands
    class UpdateCommand < Subcommand

      def initialize
        super
        @root = nil
        @library = nil
        @parser.banner = "Usage: #{File.basename($0, '.*')} update [<file>...]"
        @parser.on('--stdlibtree=ROOT', 'Process stdlib source directory tree.') {|path|
          @root = path
        }
        @parser.on('--library-name=NAME', 'Use NAME for library name in file mode.') {|name|
          @library = name
        }
      end

      def parse(argv)
        super
        if not @root and argv.empty?
          error "no input file given"
        end
      end

      def exec(argv, options)
        super
        @db.transaction {
          if @root
            @db.update_by_stdlibtree @root
          end
          argv.each do |path|
            @db.update_by_file path, @library || guess_library_name(path)
          end
        }
      end

      private

      def guess_library_name(path)
        if %r<(\A|/)src/> =~ path
          path.sub(%r<.*(\A|/)src/>, '').sub(/\.rd\z/, '')
        else
          path
        end
      end

      def get_c_filename(path)
        File.basename(path, '.rd')
      end

    end
  end
end
