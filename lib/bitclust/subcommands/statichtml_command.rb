# frozen_string_literal: true
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
require 'bitclust/search_index_generator'

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
          @edit_base_url = h[:edit_base_url]
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
          cname, tmark, mname = split_method_spec(spec)
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

        def custom_js_url(filename)
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

        def edit_url(location)
          "#{@edit_base_url}/#{location.file}".sub(/([^:])\/\/+/, "\\1/")
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
          begin
            verbose, $VERBOSE = $VERBOSE, false
            Encoding.default_external = 'utf-8'
          ensure
            $VERBOSE = verbose
          end
        end
        super
        @verbose = true
        @catalogdir = nil
        @templatedir = srcdir_root + "data/bitclust/template.offline"
        @themedir = srcdir_root + "theme/default"
        @suffix = ".html"
        @gtm_tracking_id = nil
        @meta_robots_content = ["noindex"]
        @stop_on_syntax_error = true
        @eol_warning = false
        @run_ruby_wasm = nil
        @sitemap_baseurl = nil
        @sitemap_paths = []
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
        @parser.on('--edit-base-url=URL', 'Edit base URL') do |url|
          @edit_base_url = url
        end
        @parser.on('--tracking-id=ID', 'Google Tag Manager Tracking ID') do |id|
          @gtm_tracking_id = id
        end
        @parser.on('--meta-robots-content=VALUE1,VALUE2,...', Array, 'HTML <meta> element: <meta name="robots" content="VALUE1,VALUE2..."') do |values|
          @meta_robots_content = values
        end
        @parser.on('--[no-]eol-warning', 'Show a warning banner that this Ruby version is no longer maintained') do |boolean|
          @eol_warning = boolean
        end
        @parser.on('--run-ruby-wasm=WASM_URL', 'Add a RUN button to Ruby sample code, executing it in-browser with the given ruby.wasm') do |url|
          @run_ruby_wasm = url
        end
        @parser.on('--sitemap-baseurl=URL', 'Generate sitemap.xml under the output directory, with <loc> built from this base URL (e.g. https://docs.ruby-lang.org/ja/3.4/). Omit to skip sitemap.xml generation (default)') do |url|
          @sitemap_baseurl = url
        end
        @parser.on('--no-stop-on-syntax-error', 'Do not stop on syntax error') do |boolean|
          @stop_on_syntax_error = boolean
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
          methods = {} #: Hash[String, Array[MethodEntry]]
          db.methods.each_with_index do |entry, i|
            next if entry.undefined?

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
          create_html_entries("capi", fdb.functions, manager, fdb)
        end

        @urlmapper.bitclust_html_base = '..'
        library_index_path = @outputdir + "library/#{html_filename("index", @suffix)}"
        create_file(library_index_path,
                    manager.library_index_screen(db.libraries.sort, {:database => db}).body,
                    :verbose => @verbose)
        record_sitemap_path(library_index_path)
        class_index_path = @outputdir + "class/#{html_filename("index", @suffix)}"
        create_file(class_index_path,
                    manager.class_index_screen(db.classes.sort, {:database => db}).body,
                    :verbose => @verbose)
        record_sitemap_path(class_index_path)
        function_index_path = @outputdir + "function/#{html_filename("index", @suffix)}"
        create_file(function_index_path,
                    manager.function_index_screen(fdb.functions.sort, { :database => fdb }).body,
                    :verbose => @verbose)
        record_sitemap_path(function_index_path)
        create_index_html(@outputdir)
        create_search_index(@outputdir, db, fdb)
        if baseurl = @sitemap_baseurl
          create_sitemap(@outputdir, baseurl)
        end
        FileUtils.cp(@manager_config[:themedir] + @manager_config[:css_url],
                     @outputdir.to_s, :verbose => @verbose, :preserve => true)
        FileUtils.cp(@manager_config[:themedir] + "syntax-highlight.css",
                     @outputdir.to_s, :verbose => @verbose, :preserve => true)
        FileUtils.cp(@manager_config[:themedir] + "script.js",
                     @outputdir.to_s, :verbose => @verbose, :preserve => true)
        copy_run_ruby_wasm_script if @run_ruby_wasm
        FileUtils.cp(@manager_config[:themedir] + @manager_config[:favicon_url],
                     @outputdir.to_s, :verbose => @verbose, :preserve => true)
        Dir.mktmpdir do |tmpdir|
          FileUtils.cp_r(@manager_config[:themedir] + 'images', tmpdir,
                         :verbose => @verbose, :preserve => true)
          Dir.glob(File.join(tmpdir, 'images', '/**/.svn')).each do |d|
            FileUtils.rm_r(d, :verbose => @verbose)
          end
          FileUtils.cp_r(File.join(tmpdir, 'images'), @outputdir.to_s,
                         :verbose => @verbose, :preserve => true)
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
          :edit_base_url => @edit_base_url,
          :gtm_tracking_id => @gtm_tracking_id,
          :meta_robots_content => @meta_robots_content,
          :stop_on_syntax_error => @stop_on_syntax_error,
          :eol_warning => @eol_warning,
          :run_ruby_wasm => @run_ruby_wasm,
        }
        @manager_config[:urlmapper] = URLMapperEx.new(@manager_config)
        @urlmapper = @manager_config[:urlmapper]
      end

      def create_html_entries(title, entries, manager, db)
        title = align_progress_bar_title(title)
        original_title = title.dup
        if @verbose
          progressbar = ProgressBar.create(title: title, total: entries.size)
        else
          progressbar = SilentProgressBar.create(title: title, total: entries.size)
        end
        entries.each do |entry|
          create_html_file(entry, manager, @outputdir, db)
          progressbar.title = align_progress_bar_title([entry].flatten.first.name)
          progressbar.increment
        end
        progressbar.title = original_title
        progressbar.finish
      end

      def create_html_methods(title, methods, manager, db)
        title = align_progress_bar_title(title)
        original_title = title.dup
        if @verbose
          progressbar = ProgressBar.create(title: title, total: methods.size)
        else
          progressbar = SilentProgressBar.create(title: title, total: methods.size)
        end
        methods.each do |method_name, method_entries|
          create_html_method_file(method_name, method_entries, manager, @outputdir, db)
          progressbar.title = align_progress_bar_title(method_name)
          progressbar.increment
        end
        progressbar.title = original_title
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

      SEARCH_JS_FILES = %w[
        search_navigation.js search_ranker.js search_controller.js search_init.js
      ].freeze

      def create_search_index(outputdir, db, fdb)
        generator = SearchIndexGenerator.new(suffix: @suffix,
                                             fs_casesensitive: @fs_casesensitive)
        jsdir = outputdir + "js"
        FileUtils.mkdir_p(jsdir) unless jsdir.directory?
        create_file(jsdir + "search_data.js",
                    generator.to_js(db, fdb),
                    :verbose => @verbose)
        themedir = @manager_config[:themedir]
        SEARCH_JS_FILES.each do |js|
          FileUtils.cp(themedir + "js" + js, jsdir.to_s,
                       :verbose => @verbose, :preserve => true)
        end
        # Ship the MIT notice for the vendored Aliki files alongside them.
        FileUtils.cp(themedir + "js" + "NOTICE", jsdir.to_s,
                     :verbose => @verbose, :preserve => true)
        FileUtils.cp(themedir + "search.css", outputdir.to_s,
                     :verbose => @verbose, :preserve => true)
      end

      # A single sitemap.xml file supports at most 50,000 URLs
      # (https://www.sitemaps.org/protocol.html#index). Splitting into a
      # sitemap index is out of scope for now (small start); if the site
      # grows past this, only the first MAX_SITEMAP_URLS pages are listed
      # and a warning is printed.
      MAX_SITEMAP_URLS = 50_000

      # The 5 characters that need escaping to embed arbitrary text as XML
      # character data (used for the <loc> contents below).
      XML_ESCAPES = {
        '&' => '&amp;',
        '<' => '&lt;',
        '>' => '&gt;',
        '"' => '&quot;',
        "'" => '&apos;',
      }.freeze

      def escape_xml(str)
        str.gsub(/[&<>"']/) {|c| XML_ESCAPES.fetch(c) }
      end

      # Remember +path+ (an HTML page actually written under @outputdir) so
      # that create_sitemap can list it later. A no-op unless
      # --sitemap-baseurl was given, so sitemap generation has no effect on
      # the rest of the run when the option is not used.
      def record_sitemap_path(path)
        return unless @sitemap_baseurl
        @sitemap_paths << path.relative_path_from(@outputdir).to_s
      end

      # Generate outputdir/sitemap.xml: a plain XML sitemap
      # (https://www.sitemaps.org/protocol.html) listing every page
      # recorded via record_sitemap_path, as baseurl + relative path.
      def create_sitemap(outputdir, baseurl)
        paths = @sitemap_paths
        if paths.size > MAX_SITEMAP_URLS
          $stderr.puts "warning: #{paths.size} pages found, but a single sitemap.xml supports at most #{MAX_SITEMAP_URLS} URLs; only the first #{MAX_SITEMAP_URLS} are included. Consider a sitemap index if you need the rest."
          paths = paths.first(MAX_SITEMAP_URLS)
        end
        base = baseurl.end_with?('/') ? baseurl : "#{baseurl}/"
        xml = +%(<?xml version="1.0" encoding="UTF-8"?>\n)
        xml << %(<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n)
        paths.each do |path|
          xml << "<url><loc>#{escape_xml(base + path)}</loc></url>\n"
        end
        xml << "</urlset>\n"
        create_file(outputdir + "sitemap.xml", xml, :verbose => @verbose)
      end

      # Scripts for the RUN-button feature (statichtml --run-ruby-wasm):
      # run.js sets up the button and compiles the wasm module on the main
      # thread; run-worker.js is the module Worker it spawns per execution
      # (see theme/default/js/run.js for why: STOP/timeout both just
      # Worker#terminate() it). Both are required for the feature to work.
      RUN_RUBY_WASM_JS_FILES = %w[run.js run-worker.js].freeze

      # Copy the RUN-button scripts. A themedir missing one of them is
      # tolerated: warn and skip instead of aborting the whole build.
      def copy_run_ruby_wasm_script
        jsdir = @outputdir + "js"
        RUN_RUBY_WASM_JS_FILES.each do |name|
          src = @manager_config[:themedir] + "js" + name
          unless src.file?
            $stderr.puts "warning: #{src} not found; RUN button script not copied"
            next
          end
          FileUtils.mkdir_p(jsdir) unless jsdir.directory?
          FileUtils.cp(src.to_s, jsdir.to_s, :verbose => @verbose, :preserve => true)
        end
      end

      def create_html_file(entry, manager, outputdir, db)
        e = entry.is_a?(Array) ? entry.sort.first : entry
        case e.type_id
        when :library, :class, :doc
          @urlmapper.bitclust_html_base = '..'
          path = outputdir + e.type_id.to_s + html_filename(encodename_package(e.name), @suffix)
          create_html_file_p(entry, manager, path, db)
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
      end

      def create_html_function_file(entry, manager, outputdir, db)
        path = nil
        @urlmapper.bitclust_html_base = '..'
        path = outputdir + entry.type_id.to_s + html_filename(entry.name, @suffix)
        create_html_file_p(entry, manager, path, db)
      end

      def create_html_file_p(entry, manager, path, db)
        FileUtils.mkdir_p(path.dirname) unless path.dirname.directory?
        html = manager.entry_screen(entry, {:database => db}).body
        path.open('w') do |f|
          f.write(html)
        end
        record_sitemap_path(path)
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
