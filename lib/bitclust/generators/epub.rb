# frozen_string_literal: true
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
        @filename         = options[:filename]
        @templatedir      = options[:templatedir]
        @catalog          = options[:catalog]
        @themedir         = options[:themedir]
        @fs_casesensitive = options[:fs_casesensitive]
        @keep             = options[:keep]
        @verbose          = options[:verbose]
      end

      CONTENTS_DIR_NAME = 'OEBPS'

      # StatichtmlCommand が出力ルートに書く 2 行のリダイレクト用スタブ
      # (<meta http-equiv="refresh"> と <a>)。ルート要素が無く XHTML として
      # 整形式でない。EPUB の入口は nav.xhtml なのでスタブは同梱せず削除する
      INDEX_STUB_NAME = 'index.xhtml'

      def generate
        make_epub_directory do |epub_directory|
          contents_directory = epub_directory + CONTENTS_DIR_NAME
          copy_static_files(epub_directory)
          generate_xhtml_files(contents_directory)
          remove_index_stub(contents_directory)
          generate_contents_opf(epub_directory)
          pack_epub(epub_directory)
        end
      end

      private

      def make_epub_directory
        dir = Dir.mktmpdir("epub-", @outputdir)
        yield Pathname.new(dir)
      ensure
        FileUtils.rm_rf(dir, :secure => true, :verbose => @verbose) unless @keep
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
        # @type var options: Subcommand::options
        options = {
          :prefix => @prefix,
          :capi   => @capi,
        }
        cmd = BitClust::Subcommands::StatichtmlCommand.new
        cmd.parse(argv)
        cmd.exec(argv, options)
      end

      # manifest に id="index" で固定的に載せる doc/index ページの href
      # (epub_directory 相対)。other_items からは除いて二重掲載を避ける
      INDEX_PATH = Pathname.new("#{CONTENTS_DIR_NAME}/doc/index.xhtml")

      MEDIA_TYPES = {
        '.xhtml' => 'application/xhtml+xml',
        '.css'   => 'text/css',
        '.js'    => 'application/javascript',
        '.png'   => 'image/png',
        '.jpg'   => 'image/jpeg',
        '.jpeg'  => 'image/jpeg',
        '.gif'   => 'image/gif',
        '.svg'   => 'image/svg+xml',
      }.freeze

      def generate_contents_opf(epub_directory)
        class_items = [] #: Array[{:id => String, :path => Pathname, :media_type => String}]
        glob_relative_path(epub_directory, "#{CONTENTS_DIR_NAME}/class/*.xhtml").each do |path|
          class_items << {
            :id => "class-#{decodename_package(path.basename(".*").to_s)}",
            :path => path,
            :media_type => media_type_for(path),
          }
        end
        class_items.sort_by!{|item| item[:path] }

        excluded_paths = class_items.map{|item| item[:path] } + [INDEX_PATH]
        other_items = [] #: Array[{:id => String, :path => Pathname, :media_type => String}]
        oebps_file_paths(epub_directory).each do |path|
          next if excluded_paths.include?(path)

          other_items << {
            :id => manifest_id_for(path),
            :path => path,
            :media_type => media_type_for(path),
          }
        end
        other_items.sort_by!{|item| item[:path] }

        template = (@templatedir + "contents").read
        if ::ERB.instance_method(:initialize).parameters.last.first == :key
          erb = ::ERB.new(template, trim_mode: '-')
        else
          erb = ::ERB.new(template, nil, "-") # steep:ignore UnexpectedPositionalArgument
        end
        contents = erb.result(binding)
        File.open(epub_directory + "contents.opf", "w") do |f|
          f.write contents
        end
      end

      # OEBPS 配下の通常ファイル全部(method/library/doc/function ページと、
      # statichtml がコピーした CSS・画像)を epub_directory 相対で返す。
      # class ページも含む(呼び出し側で class_items と重複排除する)
      def oebps_file_paths(epub_directory)
        glob_relative_path(epub_directory, "#{CONTENTS_DIR_NAME}/**/*").select do |relative_path|
          (epub_directory + relative_path).file?
        end
      end

      def media_type_for(path)
        MEDIA_TYPES[path.extname.downcase] || 'application/octet-stream'
      end

      # class ページ以外("OEBPS/method/Array/i/each.xhtml" 等)の manifest
      # item id。XML の NCName として妥当で一意になるよう、使えない文字は "-" に
      # 置き換え、ディレクトリ境界は "--" にして encodename 由来の "-" と
      # 区別する
      def manifest_id_for(path)
        relative = path.to_s.sub(%r{\A#{Regexp.escape(CONTENTS_DIR_NAME)}/}, "")
        segments = relative.split("/").map{|segment| segment.gsub(/[^A-Za-z0-9_.-]/, "-") }
        "item-#{segments.join('--')}"
      end

      def remove_index_stub(contents_directory)
        stub_path = contents_directory + INDEX_STUB_NAME
        FileUtils.rm_f(stub_path.to_s, :verbose => @verbose) if stub_path.file?
      end

      def pack_epub(epub_directory)
        epub_filename = @outputdir + @filename
        Dir.chdir(epub_directory.to_s) do
          system("zip -0 -X #{epub_filename} mimetype")
          system("zip -r #{epub_filename} ./* -x mimetype")
        end
      end

      def glob_relative_path(path, pattern)
        relative_paths = [] #: Array[Pathname]
        absolute_path_to_search = Pathname.new(path).realpath
        Dir.glob(absolute_path_to_search + pattern) do |absolute_path|
          absolute_path = Pathname.new(absolute_path)
          relative_paths << absolute_path.relative_path_from(absolute_path_to_search)
        end
        relative_paths
      end

      def decodename_package(str)
        if @fs_casesensitive
          NameUtils.decodename_url(str)
        else
          NameUtils.decodename_fs(str)
        end
      end

      def last_modified
        Time.now.iso8601
      end
    end
  end
end
