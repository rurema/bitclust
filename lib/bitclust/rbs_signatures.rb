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
# Array.new / Array#[] のように引数パターンごとに説明チャンクが分かれる
# メソッドでは、compile_method 冒頭でソースのシグネチャ行を走査して
# チャンク列を作り、RbsOverloadMatcher で各オーバーロードを最も近い
# チャンクへ振り分けておく(entry_chunk は自分の番のぶんだけ描画する)。
#
# RDCompiler(md は MDCompiler が継承)に include される。escape_html /
# class_link(いずれも HTMLUtils)と @option[:database] にだけ依存し、
# rbs gem は使わない(型名の位置は property 側で解決済み)。

require 'bitclust/rbs_overload_matcher'

module BitClust

  module RbsSignatures

    # 振り分け状態はメソッドのコンパイル専用(compile_method が
    # prepare_rbs_signatures で作り直す)なので、他のコンパイルへ
    # 持ち越さないよう setup(全コンパイル共通)からリセットする
    def reset_rbs_signatures
      @rbs_sig_by_chunk = nil
      @rbs_chunk_index = 0
    end

    # compile_method 冒頭で呼ぶ。rbs_sig property があれば、source の
    # シグネチャ行からチャンク列を作りオーバーロードを振り分けておく
    def prepare_rbs_signatures(entry, source)
      reset_rbs_signatures
      overloads = entry.rbs_signature_overloads
      return unless overloads
      chunks = rbs_scan_signature_chunks(source)
      if chunks.empty?
        no_signatures = [] #: Array[String]
        chunks = [no_signatures]
      end
      assignment = RbsOverloadMatcher.assign(overloads, chunks)
      @rbs_sig_by_chunk = assignment.map {|indexes|
        indexes.filter_map {|i| overloads[i]['segments'] }
      }
    end

    # 現在のチャンクに割り当てられたオーバーロードの <dt> 行(改行連結)を
    # 返し、チャンクカウンタを進める。メソッド以外のコンパイル
    # (prepare が呼ばれていない)や割り当てが無いチャンクでは nil
    def rbs_signature_dts_for_chunk
      by_chunk = @rbs_sig_by_chunk
      return nil unless by_chunk
      lines = by_chunk[@rbs_chunk_index]
      @rbs_chunk_index += 1
      return nil unless lines && !lines.empty?
      lines.map {|line|
        html = line.map {|kind, text| rbs_segment_html(kind, text) }.join
        %Q(<dt class="rbs-signature"><code>#{html}</code></dt>)
      }.join("\n")
    end

    private

    # entry_chunk と同じ規則でシグネチャ行の並び(チャンク)を数える。
    # 属性行({: ...})はシグネチャの並びを切らない
    def rbs_scan_signature_chunks(source)
      chunks = [] #: Array[Array[String]]
      current = nil #: Array[String]?
      source.each_line do |line|
        line = line.chomp
        if (sig = rbs_signature_line(line))
          if current
            current << sig
          else
            fresh = [sig] #: Array[String]
            current = fresh
            chunks << fresh
          end
        elsif current && RDCompiler::METHOD_ATTRIBUTE_LINE_RE =~ line
          # シグネチャの並びを継続
        else
          current = nil
        end
      end
      chunks
    end

    # シグネチャ行なら "--- " 始まりの正規形にして返す(rd はそのまま)。
    # md のシグネチャ行(### def ...)は MDCompiler がオーバーライドする
    def rbs_signature_line(line)
      line if line.start_with?('---')
    end

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
