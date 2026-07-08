# frozen_string_literal: true
#
# bitclust/subcommands/searchpage_command.rb
#
# Generates a standalone, cross-version, client-side search page from
# multiple version databases:
#
#   bitclust searchpage --outputdir=DIR db-3.0 db-3.1 ... db-4.1
#
# The output (index.html + js/search_data.js + assets) is fully static and
# replaces the server-backed rurema-search app at docs.ruby-lang.org/ja/search/.
# Each database's version is read from its own properties, and the merged
# index tags every entry with the versions it appears in.
#

require 'pathname'
require 'fileutils'
require 'json'
require 'optparse'

require 'bitclust'
require 'bitclust/subcommand'
require 'bitclust/search_index_generator'

module BitClust
  module Subcommands
    class SearchpageCommand < Subcommand
      # search_init.js is the in-page dropdown wiring used by statichtml
      # layouts; this page ships its own wiring (search_page.js) instead.
      VENDORED_JS_FILES = %w[
        search_navigation.js search_ranker.js search_controller.js
      ].freeze

      def initialize
        super
        @outputdir = nil
        @themedir = srcdir_root + "theme/default"
        @templatedir = srcdir_root + "data/bitclust/searchpage"
        @suffix = ".html"
        @fs_casesensitive = false
        @verbose = false
        @parser.banner = "Usage: #{File.basename($0, '.*')} searchpage [options] <dbpath>..."
        @parser.on('-o', '--outputdir=PATH', 'Output directory.') {|path|
          @outputdir = Pathname.new(path)
        }
        @parser.on('--themedir=PATH', 'Theme directory.') {|path|
          @themedir = Pathname.new(path)
        }
        @parser.on('--fs-casesensitive', 'Filesystem is case-sensitive.') {
          @fs_casesensitive = true
        }
        @parser.on('--verbose', 'Show progress.') {
          @verbose = true
        }
      end

      # DB paths are taken as positional arguments (one per version), so the
      # global --database option is not required.
      def needs_database?
        false
      end

      def exec(argv, options)
        error("no --outputdir given") unless @outputdir
        error("no database given (pass one path per version)") if argv.empty?

        generator = SearchIndexGenerator.new(suffix: @suffix,
                                             fs_casesensitive: @fs_casesensitive)
        version_indexes = argv.map {|path|
          db = MethodDatabase.new(path)
          fdb = FunctionDatabase.new(path) if File.directory?(File.join(path, 'function'))
          version = db.properties['version'] or
            error("#{path}: no version property (not a bitclust database?)")
          $stderr.puts "indexing #{path} (#{version})" if @verbose
          [version, generator.build_index(db, fdb)]
        }
        versions = version_indexes.map {|version, _| version }
                                  .sort_by {|v| Gem::Version.new(v) }

        jsdir = @outputdir + "js"
        FileUtils.mkdir_p(jsdir)
        File.write(jsdir + "search_data.js",
                   SearchIndexGenerator.merged_js(version_indexes))
        VENDORED_JS_FILES.each do |js|
          FileUtils.cp(@themedir + "js" + js, jsdir.to_s, :preserve => true)
        end
        # Ship the MIT notice for the vendored Aliki files alongside them.
        FileUtils.cp(@themedir + "js" + "NOTICE", jsdir.to_s, :preserve => true)
        FileUtils.cp(@themedir + "js" + "search_page.js", jsdir.to_s, :preserve => true)
        FileUtils.cp(@themedir + "search.css", @outputdir.to_s, :preserve => true)
        File.write(@outputdir + "index.html", render_page(versions))
        $stderr.puts "generated search page for #{versions.join(', ')}" if @verbose
      end

      private

      def render_page(versions)
        template = File.read(@templatedir + "index.html")
        template.sub('%%SEARCH_VERSIONS%%', JSON.generate(versions))
      end
    end
  end
end
