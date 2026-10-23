# frozen_string_literal: true
# Copyright (c) 2006-2007 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the Ruby License.
#

require 'bitclust'
require 'bitclust/subcommand'

module BitClust
  module Subcommands
    class HtmlfileCommand < Subcommand
      def initialize
        super
        @target = nil
        @library = nil
        @templatedir = srcdir_root + "data/bitclust/template.offline"
        @baseurl = "file://" + srcdir_root.to_s
        @version = RUBY_VERSION
        @parser.banner = "Usage: #{File.basename($0, '.*')} htmlfile [options] rdfile|mdfile"
        @parser.on('--target=NAME', 'Compile NAME to HTML.') {|name|
          @target = name
        }
        @parser.on('--library=NAME', 'Library of the Markdown entity file (overrides front matter library:).') {|name|
          @library = name
        }
        @parser.on('--[no-]force', '-f', 'Force to use rd_file template.') {|bool|
          @rd_file = bool
        }
        @parser.on('--ruby_version=VER', '--ruby=VER', 'Set Ruby version') {|version|
          @version = version
        }
        @parser.on('--baseurl=URL', 'Base URL of generated HTML') {|url|
          @baseurl = url
        }
        @parser.on('--templatedir=PATH', 'Template directory') {|path|
          @templatedir = path
        }
      end

      # DB は与えられれば使うが必須ではない (--database は任意)
      def needs_database?
        false
      end

      def exec(argv, options)
        db = MethodDatabase.dummy({'version' => @version})
        if options[:prefix]
          db = MethodDatabase.new(options[:prefix])
        end
        @capi = options[:capi]
        target_file = argv[0]
        if target_file&.end_with?('.md')
          exec_markdown(target_file, options[:prefix] ? db : nil)
          return
        end
        if /refm\/doc\// =~ target_file
          @rd_file = true if @rd_file.nil?
        end
        options = { 'version' => @version } #: Database::database_properties
        manager = ScreenManager.new(:templatedir => @templatedir,
                                    :base_url => @baseurl,
                                    :cgi_url => @baseurl,
                                    :default_encoding => 'utf-8')

        unless @rd_file
          begin
            if @capi
              lib = FunctionReferenceParser.parse_file(target_file, options)
              unless @target
                raise NotImplementedError, "generating a C API html without --target=NAME is not implemented yet."
              end
            else
              lib = RRDParser.parse_stdlib_file(target_file, options)
            end
            entry = @target ? lookup(lib, @target) : lib
            puts manager.entry_screen(entry, { :database => db, :target_version => @version }).body
            return
          rescue ParseError => ex
            $stderr.puts ex.message
            $stderr.puts ex.backtrace[0], ex.backtrace[1..-1]&.map{|s| "\tfrom " + s}
          end
        end

        begin
          entry = DocEntry.new(db, target_file)
          source = Preprocessor.read(target_file, options)
          entry.source = source
          puts manager.doc_screen(entry, { :database => db }).body
        rescue WriterError => ex
          $stderr.puts ex.message
          exit 1
        end
      end

      private

      # Markdown ソース(manual/ の .md)を変換する。パースは source_format が
      # markdown の dummy DB で行い、描画には real_db があればそれを使う
      def exec_markdown(path, real_db)
        require 'bitclust/mdparser'
        require 'bitclust/markdown_tree'
        props = { 'version' => @version } #: Database::database_properties
        db = MethodDatabase.dummy(props)
        db.properties['source_format'] = 'markdown'
        screen_db = real_db || db
        manager = ScreenManager.new(:templatedir => @templatedir,
                                    :base_url => @baseurl,
                                    :cgi_url => @baseurl,
                                    :default_encoding => 'utf-8')
        @rd_file = true if @rd_file.nil? && %r<(?:\A|/)manual/doc/> =~ path
        if @rd_file
          puts manager.doc_screen(markdown_doc_entry(db, path, props), { :database => screen_db }).body
        elsif @capi
          fdb = FunctionDatabase.dummy(props)
          fdb.properties['source_format'] = 'markdown'
          funcs = MDFunctionParser.new(fdb).parse_file(path, File.basename(path, '.md'), props)
          unless @target
            raise NotImplementedError, "generating a C API html without --target=NAME is not implemented yet."
          end
          puts manager.entry_screen(lookup(funcs, @target), { :database => screen_db, :target_version => @version }).body
        else
          lib = MDParser.new(db).parse_file(path, markdown_libname(db, path), props)
          entry = @target ? lookup(lib, @target) : lib
          puts manager.entry_screen(entry, { :database => screen_db, :target_version => @version }).body
        end
      rescue ParseError, WriterError => ex
        error "#{path}: #{ex.message}"
      end

      # manual/doc/ の md を doc ページにする(MethodDatabase#copy_doc_md と同じ手順)
      def markdown_doc_entry(db, path, props)
        rel = path[%r<(?:\A|/)manual/doc/(.+)\.md\z>, 1] || File.basename(path, '.md')
        entry = DocEntry.new(db, NameUtils.libname2id(rel))
        title, source = MDParser.split_doc(Preprocessor.read(path, props))
        entry.title = title
        entry.source = source
        entry.source_location = Location.new(path, 1)
        entry
      end

      # 所属ライブラリ名。--library > ライブラリルート(type: library)の
      # name: またはパス(manual/api/ からの相対、無ければファイル名)>
      # エンティティの library:(この版で生きている先頭の所属)
      def markdown_libname(db, path)
        info = MarkdownTree.file_info(path)
        unless db.md_version_covers?(@version, info[:since], info[:until])
          $stderr.puts "warning: #{path}: front matter の since/until により Ruby #{@version} には含まれないファイルです"
        end
        if (name = @library)
          return name
        end
        if info[:library_file]
          return info[:name] || path[%r<(?:\A|/)api/(.+)\.md\z>, 1] || File.basename(path, '.md')
        end
        memberships = info[:memberships]
        m = memberships.find {|x| db.md_gate_covers?(@version, x) } || memberships.first
        return m[:library] if m
        error "#{path}: front matter に library: がありません。--library=NAME で所属ライブラリを指定してください"
      end

      def lookup(lib, key)
        case
        when @capi && NameUtils.functionname?(key)
          # @type var lib: Array[FunctionEntry]
          lib.is_a?(Array) or raise
          lib.find {|func| func.name == key} or raise
        when NameUtils.method_spec?(key)
          # @type var lib: LibraryEntry
          lib.is_a?(LibraryEntry) or raise
          spec = MethodSpec.parse(key)
          if spec.constant?
            begin
              lib.fetch_class(key)
            rescue UserError
              lib.fetch_methods(spec)
            end
          else
            lib.fetch_methods(spec)
          end
        when NameUtils.classname?(key)
          # @type var lib: LibraryEntry
          lib.is_a?(LibraryEntry) or raise
          lib.fetch_class(key)
        else
          raise InvalidKey, "wrong search key: #{key.inspect}"
        end
      end
    end
  end
end
