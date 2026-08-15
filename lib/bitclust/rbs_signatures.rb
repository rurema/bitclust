# frozen_string_literal: true
#
# bitclust/rbs_signatures.rb
#
# メソッドエントリの RBS 型シグネチャ(rbs_sig property。RbsSigImporter が
# DB 構築後に書き込む)を、シグネチャ見出し(<dt> 群)の直後・説明 <dd> の
# 直前の独立した <dd class="rbs-signatures"> として描画する。property が
# 無いエントリでは何も出さないので、出力は従来とバイト一致のまま。
#
# RDCompiler(md は MDCompiler が継承)に include される。escape_html /
# class_link(いずれも HTMLUtils)と @option[:database] にだけ依存し、
# rbs gem は使わない(型名の位置は property 側で解決済み)。

module BitClust

  module RbsSignatures

    # entry の <dd class="rbs-signatures"> ブロック(1 行 = 1 オーバーロード)。
    # シグネチャが無ければ nil
    def rbs_signatures_dd(entry)
      segments = entry.rbs_signature_segments
      return nil unless segments
      lines = segments.map {|line|
        line.map {|kind, text| rbs_segment_html(kind, text) }.join
      }
      %Q(<dd class="rbs-signatures"><pre><code>#{lines.join("\n")}</code></pre></dd>)
    end

    private

    def rbs_segment_html(kind, text)
      if kind == 'c' and rbs_known_class?(text)
        class_link(text)
      else
        escape_html(text).gsub('-&gt;', '&rarr;')
      end
    end

    # DB に存在するクラス/モジュールだけリンク化する(自動生成リンクで
    # 死リンクを作らないため。interface や型変数もここで自然に落ちる)。
    # 同じページで同じ型名を何度も引くのでメモ化する
    def rbs_known_class?(name)
      @rbs_known_classes ||= {} #: Hash[String, bool]
      @rbs_known_classes.fetch(name) {
        db = @option[:database]
        @rbs_known_classes[name] =
          begin
            db ? (db.fetch_class(name) && true) : false
          rescue ClassNotFound
            false
          end
      }
    end

  end

end
