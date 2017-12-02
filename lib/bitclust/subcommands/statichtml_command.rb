# Copyright (c) 2006-2007 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the Ruby License.
#

require 'fileutils'

require 'bitclust'
require 'bitclust/nameutils'
require 'bitclust/subcommand'
require 'bitclust/progress_bar'
require 'bitclust/silent_progress_bar'

module BitClust
  module Subcommands
    class StatichtmlCommand < Subcommand
      include NameUtils

      class URLMapperEx < URLMapper
        include NameUtils

        attr_accessor :bitclust_html_base

        def initialize(h)
          super
          @bitclust_html_base = ""
          @suffix = h[:suffix]
          @fs_casesensitive = h[:fs_casesensitive]
          @canonical_base_url = h[:canonical_base_url]
        end

        def library_url(name)
          if name == '/'
            @bitclust_html_base + "/library/#{html_filename("index", @suffix)}"
          else
            @bitclust_html_base + "/library/#{html_filename(encodename_package(name), @suffix)}"
          end
        end

        def class_url(name)
          @bitclust_html_base + "/class/#{html_filename(encodename_package(name), @suffix)}"
        end

        def method_url(spec)
          cname, tmark, mname = *split_method_spec(spec)
          filename = html_filename(encodename_package(mname), @suffix)
          @bitclust_html_base +
            "/method/#{encodename_package(cname)}/#{typemark2char(tmark)}/#{filename}"
        end

        def function_url(name)
          filename = html_filename(name.empty? ? 'index' : name, @suffix)
          @bitclust_html_base + "/function/#{filename}"
        end

        def document_url(name)
          filename = html_filename(encodename_package(name), @suffix)
          @bitclust_html_base + "/doc/#{filename}"
        end

        def css_url
          @bitclust_html_base + "/" + @css_url
        end

        def custom_css_url(filename)
          @bitclust_html_base + "/" + filename
        end

        def favicon_url
          @bitclust_html_base + "/" + @favicon_url
        end

        def library_index_url
          @bitclust_html_base + "/library/#{html_filename("index", @suffix)}"
        end

        def function_index_url
          @bitclust_html_base + "/function/#{html_filename("index", @suffix)}"
        end

        def canonical_url(current_url)
          (@canonical_base_url + "/#{current_url}").sub(@bitclust_html_base, "").sub(/([^:])\/\/+/, "\\1/")
        end

        def encodename_package(str)
          if @fs_casesensitive
            encodename_url(str)
          else
            encodename_fs(str)
          end
        end
      end

      def initialize
        if Object.const_defined?(:Encoding)
          Encoding.default_external = 'utf-8'
        end
        super
        @verbose = true
        @catalogdir = nil
        @templatedir = srcdir_root + "data/bitclust/template.offline"
        @themedir = srcdir_root + "theme/default"
        @suffix = ".html"
        @gtm_tracking_id = nil
        @meta_robots_content = ["noindex"]
        @parser.banner = "Usage: #{File.basename($0, '.*')} statichtml [options]"
        @parser.on('-o', '--outputdir=PATH', 'Output directory') do |path|
          begin
            @outputdir = Pathname.new(path).realpath
          rescue Errno::ENOENT
            FileUtils.mkdir_p(path, :verbose => @verbose)
            retry
          end
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
        @parser.on('--suffix=SUFFIX', 'Suffix for each (X)HTML file [.html]') do |suffix|
          @suffix = suffix
        end
        @parser.on('--fs-casesensitive', 'Filesystem is case-sensitive') do
          @fs_casesensitive = true
        end
        @parser.on('--canonical-base-url=URL', 'Canonical base URL') do |url|
          @canonical_base_url = url
        end
        @parser.on('--tracking-id=ID', 'Google Tag Manager Tracking ID') do |id|
          @gtm_tracking_id = id
        end
        @parser.on('--meta-robots-content=VALUE1,VALUE2,...', Array, 'HTML <meta> element: <meta name="robots" content="VALUE1,VALUE2..."') do |values|
          @meta_robots_content = values
        end
        @parser.on('--[no-]quiet', 'Be quiet') do |quiet|
          @verbose = !quiet
        end
      end

      def exec(argv, options)
        create_manager_config

        prefix = options[:prefix]
        db = MethodDatabase.new(prefix.to_s)
        fdb = FunctionDatabase.new(prefix.to_s)
        manager = ScreenManager.new(@manager_config)

        db.transaction do
          methods = {}
          db.methods.each_with_index do |entry, i|
            entry.names.each do |name|
              method_name = entry.klass.name + entry.typemark + name
              (methods[method_name] ||= []) << entry
            end
          end

          entries = db.docs + db.libraries.sort + db.classes.sort
          create_html_entries("entries", entries, manager, db)
          create_html_methods("methods", methods, manager, db)
        end

        fdb.transaction do
          functions = {}
          create_html_entries("capi", fdb.functions, manager, fdb)
        end

        @urlmapper.bitclust_html_base = '..'
        create_file(@outputdir + "library/#{html_filename("index", @suffix)}",
                    manager.library_index_screen(db.libraries.sort, {:database => db}).body,
                    :verbose => @verbose)
        create_file(@outputdir + "class/#{html_filename("index", @suffix)}",
                    manager.class_index_screen(db.classes.sort, {:database => db}).body,
                    :verbose => @verbose)
        create_file(@outputdir + "function/#{html_filename("index", @suffix)}",
                    manager.function_index_screen(fdb.functions.sort, { :database => fdb }).body,
                    :verbose => @verbose)
        create_index_html(@outputdir)
        FileUtils.cp(@manager_config[:themedir] + @manager_config[:css_url],
                     @outputdir.to_s, {:verbose => @verbose, :preserve => true})
        FileUtils.cp(@manager_config[:themedir] + "syntax-highlight.css",
                     @outputdir.to_s, {:verbose => @verbose, :preserve => true})
        FileUtils.cp(@manager_config[:themedir] + @manager_config[:favicon_url],
                     @outputdir.to_s, {:verbose => @verbose, :preserve => true})
        Dir.mktmpdir do |tmpdir|
          FileUtils.cp_r(@manager_config[:themedir] + 'images', tmpdir,
                         {:verbose => @verbose, :preserve => true})
          Dir.glob(File.join(tmpdir, 'images', '/**/.svn')).each do |d|
            FileUtils.rm_r(d, {:verbose => @verbose})
          end
          FileUtils.cp_r(File.join(tmpdir, 'images'), @outputdir.to_s,
                         {:verbose => @verbose, :preserve => true})
        end
      end

      private

      def create_manager_config
        @manager_config = {
          :catalogdir  => @catalogdir,
          :suffix      => @suffix,
          :templatedir => @templatedir,
          :themedir    => @themedir,
          :css_url     => 'style.css',
          :favicon_url => 'rurema.png',
          :cgi_url     => '',
          :tochm_mode  => true,
          :fs_casesensitive => @fs_casesensitive,
          :canonical_base_url => @canonical_base_url,
          :gtm_tracking_id => @gtm_tracking_id,
          :meta_robots_content => @meta_robots_content,
        }
        @manager_config[:urlmapper] = URLMapperEx.new(@manager_config)
        @urlmapper = @manager_config[:urlmapper]
      end

      def create_html_entries(title, entries, manager, db)
        original_title = title.dup
        if @verbose
          progressbar = ProgressBar.new(title, entries.size)
        else
          progressbar = SilentProgressBar.new(title, entries.size)
        end
        entries.each do |entry|
          create_html_file(entry, manager, @outputdir, db)
          progressbar.title.replace([entry].flatten.first.name)
          progressbar.inc
        end
        progressbar.title.replace(original_title)
        progressbar.finish
      end

      def create_html_methods(title, methods, manager, db)
        original_title = title.dup
        if @verbose
          progressbar = ProgressBar.new(title, methods.size)
        else
          progressbar = SilentProgressBar.new(title, methods.size)
        end
        methods.each do |method_name, method_entries|
          create_html_method_file(method_name, method_entries, manager, @outputdir, db)
          progressbar.title.replace(method_name)
          progressbar.inc
        end
        progressbar.title.replace(original_title)
        progressbar.finish
      end

      def create_index_html(outputdir)
        index_filename = html_filename("index", @suffix)
        path = outputdir + index_filename
        File.open(path, 'w'){|io|
          io.write <<HERE
<meta http-equiv="refresh" content="0; URL=doc/#{index_filename}">
<a href="doc/#{index_filename}">Go</a>
HERE
        }
      end

      def create_html_file(entry, manager, outputdir, db)
        e = entry.is_a?(Array) ? entry.sort.first : entry
        case e.type_id
        when :library, :class, :doc
          @urlmapper.bitclust_html_base = '..'
          path = outputdir + e.type_id.to_s + html_filename(encodename_package(e.name), @suffix)
          create_html_file_p(entry, manager, path, db)
          path.relative_path_from(outputdir).to_s
        when :function
          create_html_function_file(entry, manager, outputdir, db)
        else
          raise
        end
        e.unload
      end

      def create_html_method_file(method_name, entries, manager, outputdir, db)
        path = nil
        @urlmapper.bitclust_html_base = '../../..'
        e = entries.sort.first
        name = method_name.sub(e.klass.name + e.typemark, "")
        path = outputdir + e.type_id.to_s + encodename_package(e.klass.name) +
          e.typechar + html_filename(encodename_package(name), @suffix)
        create_html_file_p(entries, manager, path, db)
        path.relative_path_from(outputdir).to_s
      end

      def create_html_function_file(entry, manager, outputdir, db)
        path = nil
        @urlmapper.bitclust_html_base = '..'
        path = outputdir + entry.type_id.to_s + html_filename(entry.name, @suffix)
        create_html_file_p(entry, manager, path, db)
        path.relative_path_from(outputdir).to_s
      end

      def create_html_file_p(entry, manager, path, db)
        FileUtils.mkdir_p(path.dirname) unless path.dirname.directory?
        html = manager.entry_screen(entry, {:database => db}).body
        path.open('w') do |f|
          f.write(html)
        end
      end

      def create_file(path, str, options = {})
        verbose = options[:verbose]
        $stderr.print("creating #{path} ...") if verbose
        path.open('w') do |f|
          f.write(str)
        end
        $stderr.puts(" done.") if verbose
      end

      def encodename_package(str)
        if @fs_casesensitive
          encodename_url(str)
        else
          encodename_fs(str)
        end
      end
    end
  end
end
