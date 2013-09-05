require 'fileutils'
require 'tmpdir'

require 'bitclust/subcommands/statichtml_command'

module BitClust
  module Generators
    class EPUB
      def initialize(options = {})
        @options = options.dup
      end

      CONTENTS_DIR_NAME = 'OEBPS'

      def generate
        epub_directory = Dir.mktmpdir("epub-temp-", @options[:outputdir])
        epub_directory = Pathname.new(epub_directory)
        contents_directory = epub_directory + CONTENTS_DIR_NAME
        copy_static_files(@options[:templatedir], epub_directory)
        html_options = @options.dup
        html_options[:outputdir] = contents_directory
        generate_html(html_options)
        FileUtils.rm_r(epub_directory, {:secure => true}) unless @options[:keep]
      end

      def copy_static_files(template_directory, epub_directory)
        FileUtils.cp(template_directory + "mimetype", epub_directory)
        FileUtils.cp(template_directory + "nav.xhtml", epub_directory)
        FileUtils.mkdir_p(epub_directory + "META-INF")
        FileUtils.cp(template_directory + "container.xml", epub_directory + "META-INF")
      end

      def generate_html(options)
        argv = ["--outputdir=#{options[:outputdir]}",
                "--templatedir=#{options[:templatedir]}",
                "--catalog=#{options[:catalog]}",
                "--themedir=#{options[:themedir]}"]
        argv << "--fs-casesensitive" if options[:fs_casesensitive]
        argv << "--quiet" unless options[:verbose]
        
        cmd = BitClust::Subcommands::StatichtmlCommand.new
        cmd.parse(argv)
        cmd.exec(argv, options)
      end
    end
  end
end
