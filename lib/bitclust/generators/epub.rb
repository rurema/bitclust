require 'fileutils'
require 'tmpdir'

module BitClust
  module Generators
    class EPUB
      def initialize(options = {})
        @options = options.dup
      end

      def generate
        epub_directory = Dir.mktmpdir("epub-temp-", @options[:outputdir])
        copy_static_files(@options[:templatedir], Pathname.new(epub_directory))
        FileUtils.remove_entry_secure(epub_directory) unless @options[:keep]
      end

      def copy_static_files(templatedir, epub_directory)
        FileUtils.copy(templatedir + "mimetype", epub_directory)
        FileUtils.mkdir_p(epub_directory + "META-INF")
        FileUtils.copy(templatedir + "container.xml", epub_directory + "META-INF")
      end
    end
  end
end
