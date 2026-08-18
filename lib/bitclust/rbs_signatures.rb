# frozen_string_literal: true
#
# bitclust/rbs_signatures.rb
#
# メソッドエントリの RBS 型シグネチャ(rbs_sig property。RbsSigImporter が
# DB 構築後に書き込む)を、シグネチャ見出し(<dt> 群)の直後・説明 <dd> の
# 直前に 1 オーバーロード 1 行の <dt class="rbs-signature"> として描画する。
# dd だと字下げで説明の一部に見え、pre だと theme/script.js が COPY ボタンを
# 付けてしまうため、見出しと同じ dt+code の並びにする。property が無い
# エントリでは何も出さないので、出力は従来とバイト一致のまま。
#
# RDCompiler(md は MDCompiler が継承)に include される。escape_html /
# class_link(いずれも HTMLUtils)と @option[:database] にだけ依存し、
# rbs gem は使わない(型名の位置は property 側で解決済み)。

module BitClust

  module RbsSignatures

    # entry の <dt class="rbs-signature"> 行(1 オーバーロード = 1 <dt>)を
    # 改行で連結して返す。シグネチャが無ければ nil
    def rbs_signature_dts(entry)
      segments = entry.rbs_signature_segments
      return nil unless segments
      segments.map {|line|
        html = line.map {|kind, text| rbs_segment_html(kind, text) }.join
        %Q(<dt class="rbs-signature"><code>#{html}</code></dt>)
      }.join("\n")
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
