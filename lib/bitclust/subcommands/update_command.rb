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
        if @markdowntree
          # ネイティブ md パース（M3）。source には md が入り、描画は
          # MDCompiler（GFM）が選択される。ブリッジは検証用に温存
          # （BITCLUST_MD_BRIDGE=1 で旧経路）
          if ENV['BITCLUST_MD_BRIDGE'] == '1'
            argv = @db.is_a?(FunctionDatabase) ? prepare_capi_markdowntree
                                               : (prepare_markdowntree; argv)
          else
            @db.transaction {
              @db.update_by_markdowntree(@markdowntree || raise)
            }
            return
          end
        end
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
        remap_source_locations if @markdowntree
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
        bridge = MarkdownBridge.build(@markdowntree || raise, root)
        @location_map = { root => [@markdowntree, bridge.source_map] }
        # markdowntree と同じ渡され方（相対/絶対）を保った隣接 doc パス。
        # copy_doc は stdlibtree 相対（../../doc/...）の location を記録する
        doc = File.join(File.dirname(@markdowntree || raise), 'doc')
        if File.directory?(doc)
          if Dir.glob(File.join(doc, '**/*.md')).any?
            doc_map = MarkdownBridge.build_doc(doc, File.join(@bridge_dir, 'doc'))
          else
            FileUtils.ln_s(File.expand_path(doc), File.join(@bridge_dir, 'doc'))
            doc_map = nil
          end
          @location_map[File.join(@bridge_dir, 'doc')] = [doc, doc_map]
          @location_map['../../doc'] = [doc, doc_map]
        end
        @root ||= root
      end

      # C API の Markdown ツリー（manual/capi）を旧形式の .rd 群へ変換し、
      # ファイル引数として返す（--capi update <files> の経路に載せる）
      def prepare_capi_markdowntree
        require 'tmpdir'
        require 'bitclust/markdown_to_rrd'
        @bridge_dir = Dir.mktmpdir('bitclust-capi-bridge')
        # src/ 配下に置く: guess_library_name が src/ 以降を id とするため
        # （関数の filename が旧経路と同じ「eval.c」等になる）
        src = File.join(@bridge_dir, 'src')
        FileUtils.mkdir_p(src)
        capi_map = {} #: Hash[String, String]
        files = Dir.glob(File.join(@markdowntree || raise, '*.md')).sort.map do |f|
          name = "#{File.basename(f, '.md')}.rd"
          rd = File.join(src, name)
          File.write(rd, MarkdownToRRD.convert(File.read(f), capi: true))
          capi_map[name] = "#{File.basename(f, '.md')}.md"
          rd
        end
        @location_map = { src => [@markdowntree, capi_map] }
        files
      end

      # source_location のブリッジ一時パスを manual/ の md パスへ再マップする。
      # 編集リンク（statichtml --edit-base-url）が凍結 refm でなく編集対象の
      # md を指すようにするため。行番号はブリッジ rd 基準の近似で、
      # front matter 等の分だけ md とずれることがある
      def remap_source_locations
        db = @db
        entries =
          if db.is_a?(FunctionDatabase)
            db.functions
          else
            db.is_a?(MethodDatabase) or raise
            db.libraries + db.classes + db.methods + db.docs
          end
        entries.each do |entry|
          loc = entry.source_location or next
          remapped = remap_location(loc) or next
          entry.source_location = remapped
          entry.save
        end
      end

      def remap_location(loc)
        file = loc.file
        file.is_a?(String) or raise
        @location_map.each do |bridge_root, (md_root, map)|
          prefix = "#{bridge_root}/"
          next unless file.start_with?(prefix)
          rel = file.delete_prefix(prefix)
          rel = map[rel] || rel if map
          return Location.new(File.join(md_root, rel), loc.line)
        end
        nil
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
