# frozen_string_literal: true
#
# bitclust/reloadable_request_handler.rb
#

require 'bitclust/methoddatabase'
require 'bitclust/functiondatabase'
require 'bitclust/requesthandler'

module BitClust

  # `bitclust server` を再起動しなくても `rake generate` で再生成された DB を
  # 読み直せるようにするラッパー(bitclust#275)。
  #
  # MethodDatabase/FunctionDatabase はエントリを一度読むとメモリ上にメモ化
  # し続けるため、App#initialize で一度だけ生成した RequestHandler をずっと
  # 使い回す従来の作りでは、DB をディスク上で再生成してもプロセスは古い内容
  # を返し続けてしまう。
  #
  # 新鮮さの判定は DB ディレクトリ直下の "properties" ファイルの mtime で行う。
  # `rake generate` は対象を rm_rf してから MethodDatabase#init(properties を
  # touch) → update という手順を踏むため、再生成のたびに properties は必ず
  # 書き直される。#handle は毎リクエストその mtime を stat するだけなので
  # コストは無視できる。
  #
  # 再生成の途中(rm_rf 直後〜init 前)は properties が一時的に存在しない。
  # その間は新鮮さを判定できないので、古い RequestHandler をそのまま使い
  # 続けてリクエストを失敗させない。次のリクエストで改めて判定する。
  class ReloadableRequestHandler

    def initialize(dbpath, capi, manager, request_handler_class)
      @dbpath = dbpath
      @capi = capi
      @manager = manager
      @request_handler_class = request_handler_class
      @properties_mtime = properties_mtime
      @handler = build_handler
    end

    def handle(req)
      reload_if_stale
      @handler.handle(req)
    end

    private

    def reload_if_stale
      mtime = properties_mtime
      return unless mtime # 再生成中で properties が一時的に無い: 判定を諦めて継続
      return if @properties_mtime == mtime

      @properties_mtime = mtime
      @handler = build_handler
      $bitclust_context_cache = nil # clear cache
    end

    def properties_mtime
      File.mtime("#{@dbpath}/properties")
    rescue Errno::ENOENT
      nil
    end

    def build_handler
      db = BitClust::MethodDatabase.new(@dbpath)
      if @capi
        db = [db, BitClust::FunctionDatabase.new(@dbpath)] #: [MethodDatabase, FunctionDatabase]
      end
      @request_handler_class.new(db, @manager)
    end

  end
end
