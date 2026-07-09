# るりま Markdown 記法への移行提案

> **ステータス（2026年7月）: 本提案は採用され、移行は完了しました。**
> doctree の `manual/` ツリーが正式なソースとなり、
> [docs.ruby-lang.org/ja/](https://docs.ruby-lang.org/ja/) は Markdown ソースから
> ビルドした HTML を配信しています。以後の編集は `manual/` の Markdown で
> 行ってください（旧 `refm/` は凍結）。
> 本文書は記法の設計判断の記録として維持します。
> 現在の編集手順の案内は [markdown-announcement.md](markdown-announcement.md) を、
> ビルド・検証の運用は [markdown-operations.md](markdown-operations.md) を参照してください。

## はじめに

るりまのドキュメント記法を、RD ベースの独自記法（RRD）から
**GitHub Flavored Markdown（GFM）ベースの記法**へ移行することを提案します。

本ドキュメントでは、提案する記法の概要、設計判断のポイント、
具体的な Before/After の比較を示します。

## 移行の動機

### 現状の課題

- **学習コスト**: RRD は独自記法であり、新規コントリビュータにとって参入障壁が高い
- **エディタ支援**: RRD 用のシンタックスハイライトやプレビュー環境がほとんどない
- **エコシステム**: Markdown であれば GitHub 上でのプレビュー、エディタの補完・リント、
  既存のドキュメントツールチェインとの統合が可能

### 移行方針

- **ベース仕様**: GFM を基本とし、独自拡張は最小限にとどめる
- **プリプロセッサ**: 既存の `#@` 指令（`#@since`, `#@until`, `#@if`, `#@include` 等）はそのまま維持する
- **段階的移行**: まず Markdown → RRD 変換レイヤーで既存の bitclust パイプライン上の
  等価性を証明し、その後 bitclust 自体が Markdown をネイティブにパース・描画する
  段階へ進む（達成済み。変換レイヤーはビルド経路から外れ、検証用に残存）。
  将来的には bitclust に依存しない新システムも視野に入れる

### 進捗（移行完了）

**実装・検証・本番切替のすべてが完了しています。bitclust は Markdown ツリーを
ネイティブにパース・描画し、doctree の `manual/` ツリーと Rakefile 切替も
マージ済み、公開サイトは Markdown ソースからのビルドを配信中**です。

- RRD ↔ Markdown **双方向変換器**と、クロスファイル情報（ライブラリ所属・
  include 関係・バージョンゲート）を YAML front matter へ集約する
  **オーケストレータ**を実装済み
- 対象は refm の**全3ツリー**（api / doc / capi）。変換結果は doctree の
  `manual/{api,doc,capi}` ツリー（api 1161 + doc 68 + capi 16 = 1245 ファイル）
  として生成済み
- **ネイティブパース**（MDParser）: `bitclust update --markdowntree=manual/api` が
  md ソースを直接パースして DB を構築（変換レイヤー不使用）。DB には md ソースを
  そのまま格納し、編集リンクは `manual/**.md` を指す
- **ネイティブ描画**（MDCompiler）: md ソースを直接 HTML 化。GFM の表現も描画に
  反映される（インラインコード → `<code>`、GFM テーブル、パラメータ名のコード表示等）
- 等価性は5段階で検証済み:
  1. **ラウンドトリップ**（バイト一致）: 1245/1245 = 100%
  2. **ファイル発見**: md ツリーだけで（LIBRARIES 無しで）旧構成を完全復元
  3. **データベース**: 新旧両経路でフルビルドして全比較 — 368 ライブラリ・
     1436 クラス・9281 メソッドエントリ・66 doc・814 C 関数が一致
  4. **描画等価**: 全10,655 エントリで RDCompiler と MDCompiler の HTML が一致
     （GFM 拡張は意図した差分のみ）
  5. **静的 HTML**: 旧経路とネイティブ経路の全 13,535 ページを比較し、
     残差は既知の無害差分1箇所のみ（旧経路のアーティファクト由来、意味等価）
- doctree の Rakefile 切替もマージ済み（`rake generate` / `rake statichtml` が
  manual/ からそのまま動く）
- 公開サイト [docs.ruby-lang.org/ja/](https://docs.ruby-lang.org/ja/) は
  manual/ からビルドした HTML を配信中（各ページの編集リンクも manual/ の
  `.md` を指す）

---

## Before/After: 実例で見る記法の変化

以下、実際の Comparable モジュールのドキュメントを例に比較します。

### クラス/モジュール定義

```diff
- = module Comparable
+ # module Comparable
```

`=` が `#`（h1）に変わるだけです。`class`/`module`/`object` のキーワードはそのまま維持します。

mixin や所属ライブラリなどの**関係データは本文から YAML front matter へ移します**:

```diff
- = class Set < Object
- include Enumerable
+ ---
+ library: _builtin
+ include:
+   - Enumerable
+ since: "3.2"
+ ---
+ # class Set < Object
```

`library`（所属ライブラリ）と `since`/`until`（クラス自体がバージョンで出入りする
構造的ゲート）は、旧世界では `LIBRARIES` マニフェストとライブラリファイル側の
`#@include` の囲みで表現されていた情報です。移行後は各ファイルの front matter が
唯一の出典になり、**`LIBRARIES` と grouping 用 `#@include` は廃止**されます
（ツリーを glob して front matter と H1 から構成を組み立てます）。

### メソッドカテゴリ

```diff
- == Instance Methods
+ ## Instance Methods
```

`==` が `##`（h2）に対応します。

### メソッドシグネチャ

```diff
- --- ==(other)    -> bool
+ ### def ==(other)    -> bool
```

`---` が `### def` に変わります。**`def` キーワードを付ける**のが大きな変更点です。
これにより、本文中の小見出し（`### 見出しテキスト`）とメソッドシグネチャを
キーワードの有無だけで明確に区別できます。

### パラメータ・例外

```diff
- @param other 自身と比較したいオブジェクトを指定します。
- @raise ArgumentError <=> が nil を返したときに発生します。
+ - **param** `other` -- 自身と比較したいオブジェクトを指定します。
+ - **raise** `ArgumentError` -- <=> が nil を返したときに発生します。
```

変更のポイント:
- `@` プレフィクスを外し、`**param**` のようにボールド体にする
  - **理由**: `@` は GitHub の issue/PR でメンション（`@param` → ユーザーへの通知）として
    誤爆するため
- パラメータ名・例外クラス名をコードスパン（`` ` ``）で囲む
- 区切りは `--`（ASCII ハイフン2つ）
- Markdown のリスト項目（`- `）として記述するため、構造が明確になる

### コードブロック

````diff
- #@samplecode 例
- 1 == 1   # => true
- 1 == 2   # => false
- #@end
+ ```ruby title="例"
+ 1 == 1   # => true
+ 1 == 2   # => false
+ ```
````

- `#@samplecode` → `` ```ruby `` に変換
- ラベルは `title="..."` 属性で付与（Docusaurus, MkDocs Material, Hugo 等で採用されているデファクトスタンダード）
- `#@samplecode` はデフォルトで Ruby コード、`//emlist[ラベル][lang]{` は言語指定付きコードブロックに対応

### クロスリファレンス

```diff
- [[m:Array#each]]
+ [m:Array#each]
```

角括弧を1段減らすだけです。リンク種別のプレフィクス（`c:`, `m:`, `lib:`, `d:` 等）はそのまま維持します。

### プリプロセッサ指令（変更なし）

```markdown
#@since 2.4.0
### def clamp(min, max)  -> object
#@since 2.7.0
### def clamp(range)     -> object
#@end
```

`#@` 指令は**一切変更なし**で、そのまま使い続けます。
CommonMark の仕様上、`#@` は ATX heading として解釈されない（`#` の後にスペースが必要）ため、
Markdown パーサーとの衝突もありません。

---

## Before/After: 全体比較

### RRD（旧記法） — Comparable の一部

```
= module Comparable

比較演算を許すクラスのための Mix-in です。

== Instance Methods

--- ==(other)    -> bool

比較演算子 <=> をもとにオブジェクト同士を比較します。
<=> が 0 を返した時に、true を返します。

@param other 自身と比較したいオブジェクトを指定します。

#@samplecode 例
1 == 1   # => true
1 == 2   # => false
#@end

--- between?(min, max)    -> bool

比較演算子 <=> をもとに self が min と max の範囲内にあるかを判断します。

@param min 範囲の下端を表すオブジェクトを指定します。
@param max 範囲の上端を表すオブジェクトを指定します。
@raise ArgumentError self <=> min か、self <=> max が nil を返
                     したときに発生します。
```

### Markdown（新記法） — 同じ部分

````markdown
# module Comparable

比較演算を許すクラスのための Mix-in です。

## Instance Methods

### def ==(other)    -> bool

比較演算子 <=> をもとにオブジェクト同士を比較します。
<=> が 0 を返した時に、true を返します。

- **param** `other` -- 自身と比較したいオブジェクトを指定します。

```ruby title="例"
1 == 1   # => true
1 == 2   # => false
```

### def between?(min, max)    -> bool

比較演算子 <=> をもとに self が min と max の範囲内にあるかを判断します。

- **param** `min` -- 範囲の下端を表すオブジェクトを指定します。
- **param** `max` -- 範囲の上端を表すオブジェクトを指定します。
- **raise** `ArgumentError` -- self <=> min か、self <=> max が nil を返
                     したときに発生します。
````

---

## 主要な設計判断のまとめ

レビューで特に意見をいただきたいポイントを整理します。

### 1. メソッドシグネチャのキーワード

| メソッド種別 | 記法 |
|-------------|------|
| インスタンスメソッド | `### def method(args) -> Type` |
| クラスメソッド | `### def ClassName.method(args) -> Type` |
| モジュール関数 | `### module_function def method(args) -> Type` |
| 定数 | `### const CONST -> Type` |
| グローバル変数 | `### gvar $VAR -> Type` |
| 本文小見出し | `### 見出しテキスト` |

**判断理由**: キーワードの有無だけで種別を判定でき、セクション（`## Constants` 等）の
文脈に依存しないパースが可能になる。

### 2. モジュール関数の参照記法 `.#` → `?`

```diff
- [[m:Kernel.#open]]
+ [m:Kernel?.open]
```

**判断理由**: RRD の `.#` は「クラスメソッドとしてもインスタンスメソッドとしても
呼べる」ことを示す独自の typemark だが、Markdown 内では `.#` が視覚的にわかりにくい。
RBS の `self?` に由来する `?` を採用。

### 3. `@param` → `- **param**` （`@` の除去）

**判断理由**: GitHub の issue/PR 本文に記法サンプルを貼ると `@param` が
ユーザーメンションとして誤検知される。ボールド体にすることで視認性も向上する。

### 4. 定義リストの GFM 互換表現

RRD の定義リスト:
```
: type
  Content-Type ヘッダです。デフォルトは "text/html" です。
: charset
  ボディのキャラクタセットを Content-Type ヘッダに追加します。
```

Markdown での表現:
```markdown
- **`type`**: Content-Type ヘッダです。デフォルトは "text/html" です。
- **`charset`**: ボディのキャラクタセットを Content-Type ヘッダに追加します。
```

**判断理由**: GFM には定義リスト（`<dl>`）がないため、ボールド+コードスパンの
リスト形式で代用する。GitHubのプレビューで自然に表示される。

### 5. `@see` → `- **SEE**`

```diff
- @see [[m:CGI.accept_charset]], [[m:CGI.accept_charset=]]
+ - **SEE** [m:CGI.accept_charset], [m:CGI.accept_charset=]
```

**判断理由**: `@param`/`@raise` と同様に `@` を除去。大文字ボールドで
HTML 出力時の `[SEE_ALSO]` セクションとの対応を明確にする。

### 6. YAML front matter（構造データの一元化）

タイトルに現れない構造・関係データは、すべて YAML front matter に集約する。

エンティティ（クラス/モジュール等）ファイル:

```yaml
---
library: _builtin      # 所属ライブラリ（LIBRARIES マニフェストの後継）
include:
  - Enumerable         # mixin（本文の include 行の後継）
since: "3.2"           # クラス自体の構造的バージョンゲート
---
# class Set < Object
```

ライブラリ概要ファイル:

```yaml
---
type: library
category: Network
require:
  - cgi/core
  - cgi/cookie
sublibrary:
  - cgi/session
---
```

**判断理由と帰結**:

- `include`/`extend`/`alias` の記述場所は front matter **のみ**とする。
  YAML パーサだけで関係データを取得でき、GitHub プレビューでもメタデータ表として
  表示され、リント（スキーマ検証）も可能になる。
- そのため**1ファイル＝1エンティティ**を基本とし、関係を持つエンティティは
  必ず単独ファイルにする。関係を持たない自然な束ね（`Errno::EXXX` 152 個、
  「本体＋エラークラス」対など）は1ファイルに複数エンティティを許す。
- バージョンで値が変わる場合は front matter **内**に `#@since` 等を書く
  （`#` 始まりなので生の YAML ではコメント＝全バージョンの和集合として無害に表示される）。

### 6.5 ファイル配置

新ツリーは doctree トップの `manual/` 配下（`manual/api/**/*.md`、
`manual/doc/`、`manual/capi/`）。旧 `refm/` は移行ウィンドウ中凍結して共存する。
公開 URL はエンティティ名由来のため変わらない。

### 7. アンカー

本文中の小見出しには kramdown/Pandoc 互換の `{#id}` でアンカーを付与する。

```diff
- ===[a:m17n] 多言語化と文字列のエンコーディング
+ ### 多言語化と文字列のエンコーディング {#m17n}
```

### 8. インデントコードブロックの扱い

RRD ではインデントされたテキストが整形済みテキスト（`<pre>`）になります。
Markdown ではバッククォートの個数で元のインデント幅をエンコードします。

````
RRD（8スペースインデント = 相対5スペース）:
        require "cgi"
        params = CGI.parse("query_string")

Markdown（バッククォート 3+5=8 個）:
````````
require "cgi"
params = CGI.parse("query_string")
````````
````

これは RRD との双方向変換を可能にするためのエンコーディングです。
新規にドキュメントを書く場合は通常のフェンスドコードブロック（バッククォート3個）を使います。

---

## 変更しないもの

以下は意図的に変更を加えていません:

| 項目 | 理由 |
|------|------|
| `#@since`/`#@until`/`#@if` 等の指令 | Markdown パーサーと衝突しない。既存の前処理パイプラインをそのまま利用できる |
| `#@include`（共有断片の展開） | pack-template 等の再利用断片の transclusion 手段として維持（エンティティの grouping 用途は front matter 発見に置き換え） |
| `#@#` コメント | そのまま維持 |
| 処理順序（前処理→パース→HTML生成） | 既存の bitclust パイプラインと同じ |
| 公開 URL | エンティティ名由来のため不変 |

---

## 解決済みの論点と残る課題

前版で未解決としていた項目のうち、以下は方針が確定しました:

- **RD/MD 混在**: 混在はさせない。`.md` は `manual/` の別ツリーに置き、旧 `refm/` は
  凍結して共存する（切替時点で更新停止）。旧 bitclust は `refm/` を読み続けるので
  壊れない。
- **旧バージョン（< 3.0）の扱い**: 現行ビルド対象の [3.0, 4.1] にスコープして変換
  する。スコープ外の情報はソース（凍結 `refm/`）に残っており、同じ変換器を別スコープで
  再実行して回収できる（サルベージは別トラック）。

引き続き方針を決めたい項目（移行後の継続課題）:

1. **コードブロック内の `#@` 指令**: RRD 時代と同じくコードブロック内でも処理されるが、
   Markdown パーサーを利用して区別すべきか
2. **RBS 形式シグネチャの実運用**: `### def each: () { (untyped) -> void } -> self`
   のような RBS 形式をどの程度活用するか
3. **エディタ支援**: `#@` 指令用の VS Code TextMate grammar の作成

（当初挙げていた「ネイティブ MD 描画への移行時期」は解決済み — bitclust が
Markdown を直接パース・描画するようになり、GFM 表現は描画に反映されています）

---

## サンプルファイル

実際の変換結果をサンプルとして用意しています（`doc/markdown-samples/`）。
すべて `bin/rrd2md --graph` による実際の RRD → Markdown 変換出力
（doctree の `manual/api` に入るものと同一）です。

| ファイル | 元ファイル | 含まれる記法要素 |
|---------|-----------|-----------------|
| `Comparable.md` | `_builtin/Comparable` | module、front matter（library）、`#@since`/`#@until`、param/raise、`title="..."` |
| `Array.md` | `_builtin/Array` | class、front matter（library/include）、クラス/インスタンスメソッド、複数シグネチャ、定数 |
| `String.md` | `_builtin/String` | 本文小見出し、アンカー `{#id}`、複雑なバージョン分岐、**SEE** |
| `cgi_core.md` | `cgi/core.rd` | ライブラリファイル（`type: library`）、定義リスト、定数テーブル、GFM テーブル |

---

## RRD との記法対応表（早見表）

| RRD | Markdown |
|-----|----------|
| `= class Foo < Bar` | `# class Foo < Bar` |
| `include Enumerable`（ヘッダ直後） | front matter `include:` リスト |
| `LIBRARIES` + grouping `#@include` | front matter `library:` + glob 発見 |
| C API `--- VALUE rb_ary_new()` | `### VALUE rb_ary_new()`（キーワード無し） |
| `== Instance Methods` | `## Instance Methods` |
| `--- method(args) -> Type` | `### def method(args) -> Type` |
| `--- ClassName.method(args)` | `### def ClassName.method(args)` |
| Constants 内 `--- CONST` | `### const CONST -> Type` |
| Module Functions 内 `--- method` | `### module_function def method` |
| `===[a:name] 見出し` | `### 見出し {#name}` |
| `@param name 説明` | `` - **param** `name` -- 説明 `` |
| `@return 説明` | `- **return** -- 説明` |
| `@raise Ex 説明` | `` - **raise** `Ex` -- 説明 `` |
| `@see [[m:...]]` | `- **SEE** [m:...]` |
| `[[c:String]]` | `[c:String]` |
| `[[m:Array#each]]` | `[m:Array#each]` |
| `[[m:Kernel.#open]]` | `[m:Kernel?.open]` |
| `#@samplecode ラベル` | `` ```ruby title="ラベル" `` |
| `//emlist[cap][lang]{` | `` ```lang title="cap" `` |
| `* item` | `- item` |
| `: term` / `  def` | `` - **`term`**: def `` |
| `#@since`/`#@until`/`#@end` 等 | **変更なし** |

---

## フィードバックのお願い

移行は完了していますが、記法や運用への継続的なフィードバックを歓迎します。
以下の観点でご意見をいただけると助かります:

1. **記法の読みやすさ**: 新しい Markdown 記法は、RRD と比べて読みやすいか？書きやすいか？
2. **設計判断**: 上記の主要な設計判断（特にキーワード、`@` 除去、定義リスト、
   front matter への関係集約と1ファイル1エンティティ原則）に違和感はないか？
3. **互換性**: GitHub プレビュー、エディタでの表示、既存ツールとの統合で問題になりそうな点はあるか？
4. **移行後の運用**: `manual/` 別ツリー＋`refm/` 凍結という共存方式、`refm/` の削除時期について懸念はあるか？
5. **継続課題**: 上記の「引き続き方針を決めたい項目」について、方針の提案があるか？
6. **その他**: 見落としている記法パターンや、考慮すべきユースケースがあるか？
