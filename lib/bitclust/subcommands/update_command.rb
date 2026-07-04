# frozen_string_literal: true
require 'pathname'
require 'erb'
require 'find'
require 'pp'
require 'optparse'
require 'yaml'

require 'bitclust'
require 'bitclust/subcommand'

module BitClust
  module Subcommands
    class UpdateCommand < Subcommand

      def initialize
        super
        @root = nil
        @markdowntree = nil
        @library = nil
        @parser.banner = "Usage: #{File.basename($0, '.*')} update [<file>...]"
        @parser.on('--stdlibtree=ROOT', 'Process stdlib source directory tree.') {|path|
          @root = path
        }
        @parser.on('--markdowntree=ROOT', 'Process Markdown source directory tree.') {|path|
          @markdowntree = path
        }
        @parser.on('--library-name=NAME', 'Use NAME for library name in file mode.') {|name|
          @library = name
        }
      end

      def parse(argv)
        super
        if not @root and not @markdowntree and argv.empty?
          error "no input file given"
        end
      end

      def exec(argv, options)
        super
        prepare_markdowntree if @markdowntree
        @db.transaction {
          if @root
            db = @db
            db.is_a?(MethodDatabase) or raise
            db.update_by_stdlibtree(@root || raise)
          end
          argv.each do |path|
            @db.update_by_file path, @library || guess_library_name(path)
          end
        }
      ensure
        FileUtils.remove_entry(@bridge_dir) if @bridge_dir
      end

      private

      # Markdown ツリーを旧形式の rd ツリーへブリッジし、既存の
      # stdlibtree 更新機構にそのまま渡す。
      # doc（散文ページ）は stdlibtree/../../doc から読まれるため、
      # md ツリー側に doc/ が同居していればレイアウトを合わせる
      # （manual/api を渡すと manual/doc を拾う。md ならブリッジ変換、
      # .rd のまま（移行中）なら symlink）。
      def prepare_markdowntree
        require 'tmpdir'
        require 'bitclust/markdown_bridge'
        @bridge_dir = Dir.mktmpdir('bitclust-md-bridge')
        root = File.join(@bridge_dir, 'api/src')
        MarkdownBridge.build(@markdowntree, root)
        doc = File.expand_path('../doc', @markdowntree)
        if File.directory?(doc)
          if Dir.glob(File.join(doc, '**/*.md')).any?
            MarkdownBridge.build_doc(doc, File.join(@bridge_dir, 'doc'))
          else
            FileUtils.ln_s(doc, File.join(@bridge_dir, 'doc'))
          end
        end
        @root ||= root
      end

      def guess_library_name(path)
        if %r<(\A|/)src/> =~ path
          path.sub(%r<.*(\A|/)src/>, '').sub(/\.rd\z/, '')
        else
          path
        end
      end

      def get_c_filename(path)
        File.basename(path, '.rd')
      end

    end
  end
end
