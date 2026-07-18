# 等価検証で見つかった既存実装・記述の問題（要フォローアップ）

> **ステータス（2026年7月）**: 本文書は Markdown 移行プロジェクト中の
> 等価検証で見つかった問題点の調査記録です。移行は 2026年7月に完了し、
> 現在の編集ソースは doctree の `manual/`、記法仕様は
> [markdown-samples/MARKUP_SPEC.md](markdown-samples/MARKUP_SPEC.md) です。
> 本文書は歴史的記録として維持します。

MDCompiler の HTML 等価検証（10655件、ae0f248）は「RDCompiler の現在の
出力と一致すること」を正としたため、以下の項目は**バグ互換のまま保存**
されていた。**2026-07-07 に全項目を確認し、対応を実施・記録済み**
（各項目の「確認結果」を参照）。残る作業は #7 の見出し構造レビューと
#9 の切替後コードスパン化（いずれも任意の編集タスク）のみ。

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
- **確認結果（2026-07-07）: 修正済み。** library_file に `\A@see\b` 分岐を
  追加し、MDCompiler は `doc_see` を削除して `see` へ（両コンパイラ同期）。
  doc/lib ページでも `[SEE_ALSO]` として描画される。

### 2. `@undef` が `[UNKNOWN_META_INFO] @undef:` と表示される

- **現象**: entry_info の else 枝に落ち、ユーザー向けページに
  「UNKNOWN_META_INFO」という内部用語が出る。
- **場所**: `refm/api/src/_builtin/Complex`（6箇所: `<` `<=` 等の比較演算子）。
- **M1 での扱い**: MDCompiler も同じ表示を再現（RAW_META_RE）。
- **フォローアップ**: 「このメソッドは Complex では定義されません」の
  ような専用描画にすべき。なお MDCompiler 実装時、未知メタデータの
  受け口がないと dispatch が前進せず無限ループになった — RDCompiler 側の
  else 枝は安全網として機能している。
- **確認結果（2026-07-07）: 修正済み。** 両コンパイラに `@undef` 専用描画
  「このメソッドは定義されていません。」を追加。なお statichtml は
  undefined エントリのページ生成を skip する（statichtml_command.rb）ため
  公開サイトには元々露出しておらず、影響は server 等の動的経路のみ。
  entry_info の else 枝（UNKNOWN_META_INFO）は安全網として温存。

### 3. `/@see/`・`/@todo/` の dispatch が行頭アンカー無し

- **現象**: RDCompiler の entry_chunk は `when /@see/`・`when /@todo/` と
  無アンカーでマッチするため、行の途中に「@see」を含む本文行が
  see() に吸われる潜在バグ。現コーパスでは顕在化していない。
- **フォローアップ**: `\A@see\b` へ。MDCompiler は md 形式
  （`- **SEE**`）でアンカー付きなので影響なし。
- **確認結果（2026-07-07）: 修正済み。** コーパス全体を grep して
  顕在化箇所が無いことを確認した上で `\A@see\b`・`\A@todo\b` に変更
  （MDCompiler の `/@todo/` も同時に修正）。HTML 出力は不変。

### 4. dlist の開始と継続の非対称（`:term` スペース無し）

- **現象**: dlist の開始 dispatch は `/\A:\s/`（スペース必須）だが、
  継続ループは `/\A:/`（不要）。スペース無し `:term` は
  「dlist の途中なら dt、それ以外は段落」という文脈依存になる。
- **場所**: `refm/doc/spec/operator.rd`「:再定義できない演算子(制御構造)」1箇所。
- **M1 での扱い**: `RRDToMarkdown.normalize_dlist_colon_spacing` が
  RDCompiler の文脈判定を再現して `: term` に正規化。
- **フォローアップ**: doctree 側にスペースを入れれば正規化は不要になる
  （refm は凍結方針なので manual/ 側は既に正規形）。
- **確認結果（2026-07-07）: 修正済み。** operator.rd:76 にスペースを追加
  （manual/ は既に正規形のため md 変化なし、roundtrip 1245/1245 維持）。
  `normalize_dlist_colon_spacing` は防御として温存。

## doctree 記述の問題（refm 凍結のため manual/ 正規化で吸収済み）

### 5. `---name`（シグネチャの `---` 直後にスペース無し）

- **場所**: `refm/api/src/openssl/X509__Extension`（7箇所）、
  `X509__StoreContext`（1箇所）。RRDParser/RDCompiler が `/\A---/` で
  受理するため気付かれていなかったタイポ。
- **扱い**: 変換時に `--- name` へ正規化（manual/ は正規形）。
  DB 比較では signature-spacing-only として別掲（md-db-check）。
- **確認結果（2026-07-07）: 修正済み。** doctree 77b3f797b で
  X509__Extension 全9箇所・X509__StoreContext 1箇所を `--- name` に正規化。

### 6. `@raise Ex `（説明なし・末尾スペース）

- **場所**: `rubygems/remote_fetcher.rd:33`、`openssl/Random`（5箇所）。
- **現象**: RDCompiler は dd 内に空白のみのテキスト行を出す
  （実質空の `<dd>` に無意味な1行）。説明を書くか末尾スペースを
  落とすべき記述。
- **M1 での扱い**: MDCompiler は空白を保存して同じ出力を再現。
- **確認結果（2026-07-07）: doctree 修正済み。** openssl/Random の
  egd/egd_bytes に「EGD からのエントロピー取得に失敗した場合に発生します。」
  を追記し、孤立した重複 `@raise` 2行（egd_bytes 直後・load_random_file の
  2つ目）を削除。remote_fetcher.rd の download に「Gem の取得に失敗した
  場合に発生します。」を追記。**文言は要レビュー**。

### 7. `=====`（5個の `=`）見出し

- **場所**: psych.rd(6)・rss/Tutorial(10)・safelevel.rd(10)・IO(1) 等、
  8ファイル36箇所。
- **現象**: MARKUP_SPEC 的には `====` までだが RDCompiler は `=+` 任意個を
  受理し h3 相当（hlevel+2）で描画。`====` と同レベルになる場合があり
  見出し階層として怪しい箇所がある。
- **M1 での扱い**: md では `#####` に対応（双方向・スペース保持）。
- **確認結果（2026-07-07）: 仕様面は解決済み。** MARKUP_SPEC は `#####`
  （h5・最深小見出し）を正式に記載済みで、描画・双方向変換とも対応済み。
  残るのは8ファイル36箇所の**見出し階層が意図通りかの編集レビューのみ**
  （任意。描画上の不具合ではない）。

### 8. 離散した「N. テキスト」がリストにならない

- **場所**: `refm/api/src/logger.rd`（lib:logger 冒頭の 1./2. の選択肢）。
- **現象**: rd の番号リストは `(N)` 形式（要インデント）のみ。
  col-0 の「1. テキスト」は段落テキストとして描画され、リストに見えて
  リストでない。
- **M1 での扱い**: md では `**N.**` 太字で保持し、描画時に素の
  「N.」テキストへ戻す。本来はリスト（`(N)`）に書き直すのが望ましい。
- **確認結果（2026-07-07）: 設計判断により解決済み。** M2 で
  「離散した N. は `**N.**` 太字として保持する」ことが決定済み
  （GFM では太字のステップ番号として自然に表示される）。各ステップの
  直後にコードブロックが続く構成のため、単一項目のリスト化はかえって
  構造を崩す。書き直し不要。

### 9. 旧式引用スタイルの残骸（GNU 風・TeX 風）

- **背景**: rd に code マークアップがなかったため、`` `token' ``（GNU 風）や
  ``` ``text'' ```（TeX 風）の引用が本文に残っている。M2 で GNU 風引用は
  インラインコードスパン `` `token` `` に変換するようにしたが、
  以下は境界が曖昧になるためスパン化せずエスケープ（`\``）で温存している。
  表記として古いので、いずれ手で書き直すのが望ましい:
  - **TeX 風二重引用** ``` ``text'' ```: `refm/api/src/rdoc.rd:612`（コーパスで1箇所のみ）
  - **中身がバックスラッシュの引用** `` `\' ``: `refm/doc/platform/DOSISH-support.rd:14`
  - **バックスラッシュを含む定義リスト term**: `refm/doc/symref.rd:680`（`: xxx \`）
  - **空白を含む `...' 対**（GNU 引用とみなさない）: 該当があれば
    エスケープ温存になる。`\`` が残る md を検索すれば洗い出せる
    （`grep -rn '\\\\\`' manual/`）
- **確認ポイント**: manual/ 移行後、これらを普通のコードスパンか
  かぎ括弧に書き直せば、エスケープも GNU 変換規則も不要にできる。
- **確認結果（2026-07-07）**:
  - rdoc.rd:612 の ``` ``text'' ``` は **RDoc 記法そのものの説明**
    （リテラル）であり内容は正しい。切替後にコードスパン化推奨。
  - DOSISH-support.rd:14 の `` `\' `` は旧式引用の残骸 → **「\」に修正済み**。
  - symref.rd:680 の `: xxx \` は term 内容（継続行のバックスラッシュ）で
    問題なし。切替後にコード term 化推奨。
  - manual/ 全体の `\`` 残存は **60箇所・24ファイル**
    （`grep -rn '\\\\\`' manual/ | grep -v '\`\`\`'` で列挙可能）。
    大半はリテラル記法の説明（String の置換特殊変数 `` \` ``、glob、
    Readline の区切り文字集合等）で内容は正しい。**切替後（md が正）に
    コードスパンへ書き直す編集ワークリスト**として扱う。

### 10. include 末尾空行がエントリ source に漏れる（既知）

- **現象**: includer（json.rd 等）で最後の `#@include` の後の空行が、
  被 include ファイル末尾エントリの source に混入する旧経路の
  アーティファクト。DB 比較の trailing-whitespace-only 25件、
  statichtml 差分1箇所（`JSON::State#generate` の meta description）の根。
- **扱い**: md 経路の方がクリーン。旧経路修正の必要はない
  （移行で自然解消）。
- **確認結果（2026-07-07）: 対応不要を確認。** M3 の statichtml 実機比較で
  この1件のみが残差として現れ、既知の無害差分として受容記録済み
  （markdown-operations.md §4）。ネイティブ経路への切替で自然解消する。
