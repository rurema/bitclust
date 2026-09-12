# frozen_string_literal: true
require 'pathname'
require 'optparse'

require 'bitclust'
require 'bitclust/subcommand'

module BitClust
  module Subcommands
    class ExtractCommand < Subcommand

      def initialize
        super
        @parser.banner = "Usage: #{File.basename($0, '.*')} <file>..."
        @parser.on('-c', '--check-only', 'Check syntax and output status.') {
          @check_only = true
        }
      end

      # ソースファイルを処理するだけで DB を使わない
      def needs_database?
        false
      end

      def exec(argv, options)
        success = true
        argv.each do |path|
          reject_markdown_source(path)
          begin
            lib = RRDParser.parse_stdlib_file(path)
            if @check_only
              $stderr.puts "#{path}: OK"
            else
              show_library lib
            end
          rescue WriterError => err
            raise if $DEBUG
            $stderr.puts "#{File.basename($0, '.*')}: FAIL: #{err.message}"
            success = false
          end
        end
        exit success
      end

      # 旧 RD ソース(refm)専用。Markdown を渡されたときは無関係なパースエラー
      # にせず、未対応であることを案内する
      def reject_markdown_source(path)
        return unless path.end_with?('.md')
        error "#{path}: extract は旧 RD ソース(refm)専用で、Markdown(manual/ の .md)には未対応です。manual/ の内容は doctree の rake generate:X.Y と bitclust server で確認してください"
      end

      def show_library(lib)
        puts "= Library #{lib.name}"
        lib.classes.each do |c|
          puts "#{c.type} #{c.name}"
          c.each do |m|
            puts "\t* #{m.klass.name}#{m.typemark}#{m.names.join(',')}"
          end
        end
        unless lib.methods.empty?
          puts "Additional Methods:"
          lib.methods.each do |m|
            puts "\t* #{m.klass.name}#{m.typemark}#{m.names.join(',')}"
          end
        end
      end
    end
  end
end
