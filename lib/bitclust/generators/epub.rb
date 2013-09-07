require 'fileutils'
require 'tmpdir'
require 'erb'

require 'bitclust/subcommands/statichtml_command'

module BitClust
  module Generators
    class EPUB
      def initialize(options = {})
        @options = options.dup
        @prefix           = options[:prefix]
        @capi             = options[:capi]
        @outputdir        = options[:outputdir]
        @templatedir      = options[:templatedir]
        @catalog          = options[:catalog]
        @themedir         = options[:themedir]
        @fs_casesensitive = options[:fs_casesensitive]
        @keep             = options[:keep]
        @verbose          = options[:verbose]
      end

      CONTENTS_DIR_NAME = 'OEBPS'

      def generate
        make_epub_directory do |epub_directory|
          contents_directory = epub_directory + CONTENTS_DIR_NAME
          copy_static_files(epub_directory)
          generate_xhtml_files(contents_directory)
          generate_contents_file(epub_directory)
          pack_epub(@options[:outputdir] + @options[:filename], epub_directory)
        end
      end

      def make_epub_directory
        dir = Dir.mktmpdir("epub-", @outputdir)
        yield Pathname.new(dir)
      ensure
        FileUtils.rm_r(dir, :secure => true, :verbose => @verbose) unless @keep
      end

      def copy_static_files(epub_directory)
        FileUtils.cp(@templatedir + "mimetype", epub_directory, :verbose => @verbose)
        FileUtils.cp(@templatedir + "nav.xhtml", epub_directory, :verbose => @verbose)
        meta_inf_directory = epub_directory + "META-INF"
        FileUtils.mkdir_p(meta_inf_directory, :verbose => @verbose)
        FileUtils.cp(@templatedir + "container.xml", meta_inf_directory, :verbose => @verbose)
      end

      def generate_xhtml_files(contents_directory)
        argv = [
          "--outputdir=#{contents_directory}",
          "--templatedir=#{@templatedir}",
          "--catalog=#{@catalog}",
          "--themedir=#{@themedir}",
          "--suffix=.xhtml",
        ]
        argv << "--fs-casesensitive" if @fs_casesensitive
        argv << "--quiet" unless @verbose
        options = {
          :prefix => @prefix,
          :capi   => @capi,
        }
        cmd = BitClust::Subcommands::StatichtmlCommand.new
        cmd.parse(argv)
        cmd.exec(argv, options)
      end

      def generate_contents_file(epub_directory)
        items = []
        glob_relative_path(epub_directory, "#{CONTENTS_DIR_NAME}/class/*.xhtml").each do |path|
          items << {
            :id => decodename_package(path.basename(".*").to_s, @fs_casesensitive),
            :path => path
          }
        end
        items.sort_by!{|item| item[:path] }
        contents = ERB.new(File.read(@templatedir + "contents"), nil, "-").result(binding)
        File.open(epub_directory + "contents.opf", "w") do |f|
          f.write contents
        end
      end

      def pack_epub(output_path, epub_directory)
        Dir.chdir(epub_directory.to_s) do
          system("zip -0 -X #{output_path} mimetype")
          system("zip -r #{output_path} ./* -x mimetype")
        end
      end

      def glob_relative_path(path, pattern)
        relative_paths = []
        absolute_path_to_search = Pathname.new(path).realpath
        Dir.glob(absolute_path_to_search + pattern) do |absolute_path|
          absolute_path = Pathname.new(absolute_path)
          relative_paths << absolute_path.relative_path_from(absolute_path_to_search)
        end
        relative_paths
      end

      def decodename_package(str, fs_casesensitive)
        if fs_casesensitive
          NameUtils.decodename_url(str)
        else
          NameUtils.decodename_fs(str)
        end
      end

      def last_modified
        Time.now.strftime("%Y-%m-%dT%H:%M:%SZ")
      end
    end
  end
end
