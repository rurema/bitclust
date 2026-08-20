# frozen_string_literal: true
#
# irb からるりま(Ruby リファレンスマニュアル)を引く refe コマンド。
# ~/.irbrc に `require "bitclust/irb"` と書くと irb に `refe` コマンドが
# 登録される。検索対象の DB は refe コマンドと同じ場所
# (bitclust setup が作る ~/.bitclust/config)から探す。

require 'stringio'
require 'bitclust'
require 'bitclust/searcher'

module BitClust
  module Irb
    USAGE = <<~USAGE
      Usage: refe <pattern>

      例:
        refe String#gsub     インスタンスメソッド
        refe Array.new       特異メソッド
        refe Comparable      クラス・モジュール
        refe printf          名前だけでの検索

      DB が無い場合は `bitclust setup` で作成してください。
    USAGE

    # pattern を検索して整形済みテキストを io へ書く。db が nil なら
    # 既定の場所から探す。検索の失敗は例外にせず io へメッセージを書く
    # (irb セッションを止めないため)
    def self.lookup(pattern, io: $stdout, db: nil)
      words = pattern.to_s.split
      if words.empty?
        io.puts USAGE
        return
      end
      view = TerminalView.new(Plain.new,
                              { describe_all: false, line: false, encoding: nil },
                              io: io)
      Searcher.new.run_query(db, words, view)
    rescue BitClust::UserError => err
      io.puts err.message
    end

    begin
      require 'irb/command'
    rescue LoadError
      # irb が無い(または irb < 1.13 で公開コマンド API が無い)環境では
      # コマンド登録だけを諦め、Irb.lookup は使えるままにする
    else
      class RefeCommand < ::IRB::Command::Base
        category 'Documentation'
        description 'るりま(Ruby リファレンスマニュアル)を検索して表示します'
        help_message USAGE

        def execute(arg)
          content = StringIO.new
          BitClust::Irb.lookup(arg, io: content)
          if ::IRB.const_defined?(:Pager)
            ::IRB::Pager.page_content(content.string)
          else
            $stdout.puts content.string
          end
        end
      end

      ::IRB::Command.register(:refe, RefeCommand)
    end
  end
end
