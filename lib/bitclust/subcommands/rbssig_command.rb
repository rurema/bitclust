# frozen_string_literal: true
#
# bitclust/subcommands/rbssig_command.rb
#
# RBS 型シグネチャを DB のメソッドエントリに書き込む(rbs_sig property):
#
#   bitclust rbssig --sig-root=RBS_CHECKOUT <dbpath>
#   bitclust rbssig --sig-dir=DIR [--sig-dir=DIR ...] <dbpath>
#
# DB 構築(update)後・statichtml 前に実行する(methodsince と同じ位置)。
# --sig-root には対象 Ruby バージョンに同梱される rbs のチェックアウト
# (core/ と stdlib/ を含む)を渡す。表示は 4.0 以降のドキュメント専用
# なので、DB の version が 4.0 未満ならエラーにする。

require 'bitclust'
require 'bitclust/subcommand'
require 'bitclust/rbs_sig_importer'
require 'tmpdir'
require 'fileutils'

module BitClust
  module Subcommands
    class RbssigCommand < Subcommand
      MINIMUM_VERSION = Gem::Version.new('4.0')

      def initialize
        super
        @sig_root = nil
        @sig_dirs = []
        @dry_run = false
        @parser.banner = "Usage: #{File.basename($0, '.*')} rbssig [options] <dbpath>"
        @parser.on('--sig-root=PATH', 'ruby/rbs checkout containing core/ and stdlib/.') {|path|
          @sig_root = path
        }
        @parser.on('--sig-dir=PATH', 'Directory of extra .rbs files (repeatable).') {|path|
          @sig_dirs.push path
        }
        @parser.on('--dry-run', 'Compute and print stats without saving.') {
          @dry_run = true
        }
      end

      # DB パスは位置引数で受けるのでグローバル --database は不要
      def needs_database?
        false
      end

      def exec(argv, options)
        error('no --sig-root or --sig-dir given') if @sig_root.nil? && @sig_dirs.empty?
        error("wrong number of arguments (#{argv.size} for 1)") unless argv.size == 1
        path = argv.first
        version = check_version(path)

        sig_root = @sig_root
        importer = RbsSigImporter.new(
          core_root: sig_root && File.join(sig_root, 'core'),
          repository_root: sig_root && File.join(sig_root, 'stdlib'),
          sig_dirs: @sig_dirs)
        stats =
          if @dry_run
            apply_dry_run(importer, path)
          else
            importer.apply(MethodDatabase.new(path))
          end
        puts "#{File.basename(path)} (version #{version}): " \
             "entries_updated=#{stats[:entries_updated]} sigs_matched=#{stats[:sigs_matched]} " \
             "methods_missed=#{stats[:methods_missed]}"
      end

      private

      # RBS シグネチャ表示は 4.0 以降のドキュメント専用。比較は
      # display_typemark(nameutils.rb)と同じく Gem::Version で行う
      # (文字列比較だと "10.0" が "4.0" より小さく見える)
      def check_version(path)
        version = MethodDatabase.new(path).propget('version') or
          error("#{path}: no version property (not a bitclust database?)")
        begin
          if Gem::Version.new(version) < MINIMUM_VERSION
            error("#{path}: version #{version} is before 4.0; RBS signatures are only for 4.0+ databases")
          end
        rescue ArgumentError
          error("#{path}: malformed version property: #{version.inspect}")
        end
        version
      end

      # --dry-run: 実 DB には書き込まず、複製に apply した統計だけを見せる
      # (methodsince の apply_dry_run と同じ手口)
      def apply_dry_run(importer, path)
        Dir.mktmpdir do |tmp|
          copy = File.join(tmp, 'db')
          FileUtils.cp_r(path, copy)
          importer.apply(MethodDatabase.new(copy))
        end
      end
    end
  end
end
