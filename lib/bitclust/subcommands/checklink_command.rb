# frozen_string_literal: true
#
# bitclust/subcommands/checklink_command.rb
#
# DB 中の全ソースをコンパイル経路で走査し、[[c:]]/[[m:]]/[[lib:]]/[[d:]]/
# [[f:]] 参照のリンク切れを報告する:
#
#   bitclust -d db-3.4 checklink
#   bitclust -d db-3.4 checklink --capi-database=db-3.4-capi
#
# リンク切れが1件でもあれば exit 1(CI 組み込み用)。
# [[f:]](C API 関数)は --capi-database 指定時のみ検証し、
# 未指定ならスキップ数だけ報告する。

require 'bitclust'
require 'bitclust/subcommand'
require 'bitclust/link_checker'

module BitClust
  module Subcommands
    class ChecklinkCommand < Subcommand
      def initialize
        super
        @capi_prefix = nil
        @parser.banner = "Usage: #{File.basename($0, '.*')} --database=PATH checklink [options]"
        @parser.on('--capi-database=PATH', 'C API (function) database for [[f:]] refs.') {|path|
          @capi_prefix = path
        }
      end

      def exec(argv, options)
        super
        db = @db
        unless db.is_a?(MethodDatabase)
          error 'checklink is for method databases (do not use --capi; pass --capi-database instead)'
        end
        capi_prefix = @capi_prefix
        fdb = capi_prefix ? BitClust::FunctionDatabase.new(capi_prefix) : nil
        checker = LinkChecker.new(db, function_database: fdb)
        checker.check_all
        # 同一エントリ内の同一参照の繰り返しは1行にまとめる
        checker.findings.map {|f| "#{f.location}: [[#{f.ref}]] #{f.message}" }.uniq.each do |line|
          puts line
        end
        if fdb.nil? && checker.skipped_function_refs > 0
          puts "note: #{checker.skipped_function_refs} [[f:]] refs skipped (no --capi-database)"
        end
        version = @db.properties['version']
        puts "#{checker.broken_count} broken link(s) in #{version ? "db (version #{version})" : 'db'}"
        exit 1 unless checker.broken_count.zero?
      end
    end
  end
end
