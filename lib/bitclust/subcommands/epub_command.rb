require 'fileutils'
require 'date'

require 'bitclust'
require 'bitclust/subcommand'
require 'bitclust/generators/epub'

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
        @keep = false
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
                   "Filename of generated EPUB file [#{@filename}]") do |filename|
          @filename = filename
        end
        @parser.on('--[no-]keep', 'Keep all generated files (for debug) [false]') do |keep|
          @keep = keep
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
          @fs_casesensitive = true
        end
        @parser.on('--[no-]quiet', 'Be quiet') do |quiet|
          @verbose = !quiet
        end
      end

      def exec(argv, options)
        generator = BitClust::Generators::EPUB.new(:prefix           => options[:prefix],
                                                   :capi             => options[:capi],
                                                   :outputdir        => @outputdir,
                                                   :catalog          => @catalog,
                                                   :templatedir      => @templatedir,
                                                   :themedir         => @themedir,
                                                   :fs_casesensitive => @fs_casesensitive,
                                                   :verbose          => @verbose,
                                                   :keep             => @keep,
                                                   :filename         => @filename)
        generator.generate
      end
    end
  end

end
