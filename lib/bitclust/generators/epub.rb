require 'fileutils'
require 'tmpdir'

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
        copy_assets(@options[:themedir], contents_directory)
        FileUtils.remove_entry_secure(epub_directory) unless @options[:keep]
      end

      def copy_static_files(templatedir, epub_directory)
        FileUtils.copy(templatedir + "mimetype", epub_directory)
        FileUtils.mkdir_p(epub_directory + "META-INF")
        FileUtils.copy(templatedir + "container.xml", epub_directory + "META-INF")
      end

      CSS_NAME = 'style.css'
      FAVICON_NAME = 'rurema.png'

      def copy_assets(themedir, contents_directory)
        FileUtils.mkdir_p(contents_directory)
        FileUtils.copy(themedir + CSS_NAME, contents_directory)
        FileUtils.copy(themedir + FAVICON_NAME, contents_directory)
      end
    end
  end
end
