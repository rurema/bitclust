# 等価検証で見つかった既存実装・記述の問題（要フォローアップ）

MDCompiler の HTML 等価検証（10655件、ae0f248）は「RDCompiler の現在の
出力と一致すること」を正としたため、以下の項目は**バグ互換のまま保存**
されている。移行完了後に個別に確認・修正したい。

修正する場合の注意: いずれも直すと HTML が変わるため、
`tools/md-compile-check.rb` の期待値と（doctree 記述を直す場合は）
`manual/` の再生成が必要になる。

## RDCompiler の実装漏れ・癖

### 1. doc/lib ページの `@see` が解釈されない

- **現象**: `library_file`（doc・lib ページの描画）には `@see` の分岐がなく、
  段落テキスト「@see <リンク>」としてそのまま表示される。
  メソッドエントリでは `[SEE_ALSO]` になるのと非対称。
- **場所**: `refm/doc/spec/def.rd:467`、`refm/doc/spec/literal.rd:607`、
  `refm/doc/spec/safelevel.rd:307`、`_builtin/pack-template`（doc:pack_template）。
- **M1 での扱い**: MDCompiler `doc_see` が同じ生テキスト描画を再現
  （mdcompiler.rb）。
- **フォローアップ**: RDCompiler の library_file にも SEE_ALSO 描画を
  追加するのが素直。その際 MDCompiler の `doc_see` を `see` に戻す。

### 2. `@undef` が `[UNKNOWN_META_INFO] @undef:` と表示される

- **現象**: entry_info の else 枝に落ち、ユーザー向けページに
  「UNKNOWN_META_INFO」という内部用語が出る。
- **場所**: `refm/api/src/_builtin/Complex`（6箇所: `<` `<=` 等の比較演算子）。
- **M1 での扱い**: MDCompiler も同じ表示を再現（RAW_META_RE）。
- **フォローアップ**: 「このメソッドは Complex では定義されません」の
  ような専用描画にすべき。なお MDCompiler 実装時、未知メタデータの
  受け口がないと dispatch が前進せず無限ループになった — RDCompiler 側の
  else 枝は安全網として機能している。

### 3. `/@see/`・`/@todo/` の dispatch が行頭アンカー無し

- **現象**: RDCompiler の entry_chunk は `when /@see/`・`when /@todo/` と
  無アンカーでマッチするため、行の途中に「@see」を含む本文行が
  see() に吸われる潜在バグ。現コーパスでは顕在化していない。
- **フォローアップ**: `\A@see\b` へ。MDCompiler は md 形式
  （`- **SEE**`）でアンカー付きなので影響なし。

### 4. dlist の開始と継続の非対称（`:term` スペース無し）

- **現象**: dlist の開始 dispatch は `/\A:\s/`（スペース必須）だが、
  継続ループは `/\A:/`（不要）。スペース無し `:term` は
  「dlist の途中なら dt、それ以外は段落」という文脈依存になる。
- **場所**: `refm/doc/spec/operator.rd`「:再定義できない演算子(制御構造)」1箇所。
- **M1 での扱い**: `RRDToMarkdown.normalize_dlist_colon_spacing` が
  RDCompiler の文脈判定を再現して `: term` に正規化。
- **フォローアップ**: doctree 側にスペースを入れれば正規化は不要になる
  （refm は凍結方針なので manual/ 側は既に正規形）。

## doctree 記述の問題（refm 凍結のため manual/ 正規化で吸収済み）

### 5. `---name`（シグネチャの `---` 直後にスペース無し）

- **場所**: `refm/api/src/openssl/X509__Extension`（7箇所）、
  `X509__StoreContext`（1箇所）。RRDParser/RDCompiler が `/\A---/` で
  受理するため気付かれていなかったタイポ。
- **扱い**: 変換時に `--- name` へ正規化（manual/ は正規形）。
  DB 比較では signature-spacing-only として別掲（md-db-check）。

### 6. `@raise Ex `（説明なし・末尾スペース）

- **場所**: `rubygems/remote_fetcher.rd:33`、`openssl/Random`（5箇所）。
- **現象**: RDCompiler は dd 内に空白のみのテキスト行を出す
  （実質空の `<dd>` に無意味な1行）。説明を書くか末尾スペースを
  落とすべき記述。
- **M1 での扱い**: MDCompiler は空白を保存して同じ出力を再現。

### 7. `=====`（5個の `=`）見出し

- **場所**: psych.rd(6)・rss/Tutorial(10)・safelevel.rd(10)・IO(1) 等、
  8ファイル36箇所。
- **現象**: MARKUP_SPEC 的には `====` までだが RDCompiler は `=+` 任意個を
  受理し h3 相当（hlevel+2）で描画。`====` と同レベルになる場合があり
  見出し階層として怪しい箇所がある。
- **M1 での扱い**: md では `#####` に対応（双方向・スペース保持）。

### 8. 離散した「N. テキスト」がリストにならない

- **場所**: `refm/api/src/logger.rd`（lib:logger 冒頭の 1./2. の選択肢）。
- **現象**: rd の番号リストは `(N)` 形式（要インデント）のみ。
  col-0 の「1. テキスト」は段落テキストとして描画され、リストに見えて
  リストでない。
- **M1 での扱い**: md では `**N.**` 太字で保持し、描画時に素の
  「N.」テキストへ戻す。本来はリスト（`(N)`）に書き直すのが望ましい。

### 9. include 末尾空行がエントリ source に漏れる（既知）

- **現象**: includer（json.rd 等）で最後の `#@include` の後の空行が、
  被 include ファイル末尾エントリの source に混入する旧経路の
  アーティファクト。DB 比較の trailing-whitespace-only 25件、
  statichtml 差分1箇所（`JSON::State#generate` の meta description）の根。
- **扱い**: md 経路の方がクリーン。旧経路修正の必要はない
  （移行で自然解消）。
