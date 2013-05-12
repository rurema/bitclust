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
        @templatedir = srcdir_root + "data/bitclust/template.offline"
        @baseurl = "file://" + srcdir_root.to_s
        @version = "2.0.0"
        @parser.banner = "Usage: #{File.basename($0, '.*')} htmlfile [options] rdfile"
        @parser.on('--target=NAME', 'Compile NAME to HTML.') {|name|
          @target = name
        }
        @parser.on('--force', '-f', 'Force to use rd_file template.') {|name|
          @rd_file = true
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

      def exec(argv, options)
        db = MethodDatabase.dummy({'version' => @version})
        if options[:prefix]
          db = MethodDatabase.new(options[:prefix])
        end
        @capi = options[:capi]
        target_file = argv[0]
        options = { 'version' => @version }
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
            puts manager.entry_screen(entry, { :database => db }).body
            return
          rescue ParseError => ex
            $stderr.puts ex.message
            $stderr.puts ex.backtrace[0], ex.backtrace[1..-1].map{|s| "\tfrom " + s}
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

      def lookup(lib, key)
        case
        when @capi && NameUtils.functionname?(key)
          lib.find {|func| func.name == key}
        when NameUtils.method_spec?(key)
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
          lib.fetch_class(key)
        else
          raise InvalidKey, "wrong search key: #{key.inspect}"
        end
      end
    end
  end
end
