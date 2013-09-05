require 'fileutils'
require 'date'

require 'bitclust'
require 'bitclust/subcommand'
require 'bitclust/progress_bar'
require 'bitclust/silent_progress_bar'

module BitClust
  module Subcommands
    class EPUBCommand < Subcommand
      def initialize
        super
        @verbose = true
        @catalogdir = nil
        @templatedir = srcdir_root + "data/bitclust/template.epub"
        @themedir = srcdir_root + "theme/default"
        @filename = "rurema-#{Date.today}.epub"
        @parser.banner = "Usage: #{File.basename($0, '.*')} epub [options]"
        @parser.on('-o', '--outputdir=PATH', 'Output directory') do |path|
          begin
            @outputdir = Pathname.new(path).realpath
          rescue Errno::ENOENT
            FileUtils.mkdir_p(path, :verbose => @verbose)
            retry
          end
        end
        @parser.on('-f', '--filename=FILENAME',
                   "Base name of generated EPUB file [#{@filename}]") do |filename|
          @filename = filename
        end
        @parser.on('--catalog=PATH', 'Catalog directory') do |path|
          @catalogdir = Pathname.new(path).realpath
        end
        @parser.on('--templatedir=PATH', 'Template directory') do |path|
          @templatedir = Pathname.new(path).realpath
        end
        @parser.on('--themedir=PATH', 'Theme directory') do |path|
          @themedir = Pathname.new(path).realpath
        end
        @parser.on('--fs-casesensitive', 'Filesystem is case-sensitive') do
          $fs_casesensitive = true
        end
        @parser.on('--[no-]quiet', 'Be quiet') do |quiet|
          @verbose = !quiet
        end
      end

      def exec(argv, options)
        # TODO implement
      end
    end
  end

end
