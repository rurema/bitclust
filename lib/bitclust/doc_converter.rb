# frozen_string_literal: true

require 'bitclust/rrd_to_markdown'

module BitClust
  # refm/doc（散文ページ）の Markdown 変換。
  #
  # doc ページにはクロスファイル情報（library 所属等）が無いため、
  # オーケストレータは不要で、reduce（正規化）+ 単一ファイル変換のみ。
  # タイトルは H1 が担い、front matter は使わない。
  #
  # reduce は意味を変えない表記ゆれを md→rd の再生成形に合わせる正規化と、
  # クロスツリー include（api 断片の transclude）の manual レイアウトへの
  # 書き換えを行う。md→rd 変換は reduce の結果を復元する（検証の期待値）。
  module DocConverter
    module_function

    def reduce(rrd)
      RRDToMarkdown.normalize_dlist_colon_spacing(rrd.lines.map { |line|
        case line
        when /\A\#@samplecode[ \t]+\n\z/
          "\#@samplecode\n"                      # ラベル無しの末尾スペース
        when %r{\A//\}[ \t]+\n\z}
          "//}\n"
        when /\A:\s{2,}(.*)/m
          ": #{$1}"                              # 定義リスト term の余分なスペース
        when /\A(={1,4}\[a:[^\]]+\])\s{2,}(.*)/m
          "#{$1} #{$2}"                          # アンカー見出しの余分なスペース
        when /\A\t+/
          line.sub(/\A\t+/) { ' ' * $&.length }  # 行頭タブ（doc の散文1行のみ）
        when /\A\#@include\((?:\.\.\/)+api\/src\//
          # 旧レイアウト ../api/src/X → 新レイアウト ../api/X
          # （manual/ 配下では src 階層が無い。ブリッジが逆変換する）
          line.sub(%r{((?:\.\./)+)api/src/}, '\1api/')
        else
          line
        end
      }.join)
    end

    def convert(rrd)
      RRDToMarkdown.convert(reduce(rrd))
    end

    # 変換対象ファイルの一覧（doc ルート相対）。
    # 旧パイプライン（copy_doc）は **/*.rd だけをページとして読むため、
    # .rd 以外は doc 内 include から参照される断片のみを対象にし、
    # 参照されない死にファイル（news/1.8.0.rd-2 等）は凍結側に残す
    def files(doc_root)
      all = Dir.glob('**/*', base: doc_root)
               .select { |f| File.file?(File.join(doc_root, f)) }.sort
      pages = all.select { |f| f.end_with?('.rd') }
      referenced = pages.flat_map { |f|
        base = File.dirname(f)
        File.read(File.join(doc_root, f))
            .scan(/^\#@include\((?!(?:\.\.\/)+api\/)(.*?)\)/)
            .map { |t| File.expand_path(base == '.' ? t[0] : File.join(base, t[0]), '/')
                           .delete_prefix('/') }
      }
      (pages + (all & referenced)).sort
    end
  end
end
