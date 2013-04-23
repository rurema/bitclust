require 'pathname'
require 'erb'
require 'find'
require 'pp'
require 'optparse'
require 'yaml'

require 'bitclust'
require 'bitclust/subcommand'

module BitClust::Subcommands
  class UpdateCommand < BitClust::Subcommand

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
