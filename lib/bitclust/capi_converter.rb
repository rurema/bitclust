# frozen_string_literal: true

require 'bitclust/rrd_to_markdown'

module BitClust
  # refm/capi（C API リファレンス）の Markdown 変換。
  #
  # capi の構造は「--- シグネチャ + 本文」の列のみで、見出し・include・
  # ライブラリ等のクロスファイル情報が無い（FunctionReferenceParser 参照）。
  # front matter は使わず、シグネチャは capi モードの変換
  # 「--- <C sig>」↔「### <C sig>」（def 等のキーワード無し。C の
  # シグネチャは型から始まるため自己記述的）で表す。本文の記法は api と共通。
  module CapiConverter
    module_function

    def convert(rrd)
      RRDToMarkdown.convert(rrd, capi: true)
    end
  end
end
