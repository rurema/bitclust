# frozen_string_literal: true
#
# bitclust/subcommands/methodsince_command.rb
#
# Fills per-name since/until into method entries by scanning a version
# ladder of databases:
#
#   bitclust methodsince --update=db-3.4 db-1.8.7 db-1.9.3 ... db-3.3 db-3.4
#
# Every positional argument and every --update path together form the
# version ladder used to compute presence; --update paths are additionally
# written back to (see bitclust/method_since_calculator.rb, bitclust#132 P2).
#

require 'bitclust'
require 'bitclust/subcommand'
require 'bitclust/method_since_calculator'
require 'tmpdir'
require 'fileutils'

module BitClust
  module Subcommands
    class MethodsinceCommand < Subcommand
      def initialize
        super
        @updates = []
        @dry_run = false
        @parser.banner = "Usage: #{File.basename($0, '.*')} methodsince [options] <dbpath>..."
        @parser.on('--update=PATH', 'Writable target database to fill in-place (repeatable).') {|path|
          @updates.push path
        }
        @parser.on('--dry-run', 'Compute and print stats without saving.') {
          @dry_run = true
        }
      end

      # DB パスは自前の引数(位置引数 + --update)で受けるので、
      # グローバル --database は不要
      def needs_database?
        false
      end

      def exec(argv, options)
        error("no --update given (nothing to write to)") if @updates.empty?

        ladder_paths = (argv + @updates).uniq {|path| File.expand_path(path) }
        calculator = MethodSinceCalculator.new(ladder_paths.map {|path| MethodDatabase.new(path) })
        calculator.scan

        @updates.each do |path|
          stats, version = @dry_run ? apply_dry_run(calculator, path) : apply_and_save(calculator, path)
          puts "#{File.basename(path)} (version #{version}): " \
               "entries_updated=#{stats[:entries_updated]} since_filled=#{stats[:since_filled]} " \
               "until_filled=#{stats[:until_filled]} floor_skipped=#{stats[:floor_skipped]}"
        end
      end

      private

      def apply_and_save(calculator, path)
        target = MethodDatabase.new(path)
        version = target.propget('version') or
          error("#{path}: no version property (not a bitclust database?)")
        [calculator.apply(target), version]
      end

      # --dry-run: 実際のデータベースには一切書き込まず、複製に対して
      # apply した結果の統計だけを見せる
      def apply_dry_run(calculator, path)
        version = MethodDatabase.new(path).propget('version') or
          error("#{path}: no version property (not a bitclust database?)")
        Dir.mktmpdir do |tmp|
          copy = File.join(tmp, 'db')
          FileUtils.cp_r(path, copy)
          [calculator.apply(MethodDatabase.new(copy)), version]
        end
      end
    end
  end
end
