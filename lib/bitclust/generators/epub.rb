require 'fileutils'

module BitClust
  module Generators
    class EPUB
      def initialize(options = {})
        @options = options.dup
      end

      def generate
        copy_static_files(@options[:templatedir], @options[:outputdir])
      end

      def copy_static_files(templatedir, outputdir)
        FileUtils.copy(templatedir + "/mimetype", outputdir)
        FileUtils.mkdir(outputdir + "/META-INF")
        FileUtils.copy(templatedir + "/container.xml", outputdir + "/META-INF")
      end
    end
  end
end
