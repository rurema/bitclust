# るりま Markdown 記法への移行提案

## はじめに

るりまのドキュメント記法を、現行の RD ベースの独自記法（RRD）から
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
- **段階的移行**: まず Markdown → RRD 変換レイヤーを構築し、既存の bitclust パイプライン上で検証。
  最終的には bitclust に依存しない新システムへ移行する

### 現在の進捗

- RRD ↔ Markdown **双方向変換器**を実装済み
- doctree 全 **826 ファイル**でロスレスラウンドトリップを達成（RRD → MD → RRD で差分なし）
- 変換器のテスト: MD→RRD 74テスト/90アサーション、RRD→MD 62テスト/64アサーション

---

## Before/After: 実例で見る記法の変化

以下、実際の Comparable モジュールのドキュメントを例に比較します。

### クラス/モジュール定義

```diff
- = module Comparable
+ # module Comparable
```

`=` が `#`（h1）に変わるだけです。`class`/`module`/`object` のキーワードはそのまま維持します。

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

### RRD（現行） — Comparable の一部

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

### Markdown（提案） — 同じ部分

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

### 6. YAML front matter

`category`/`require`/`sublibrary` の3つのメタデータのみ YAML front matter に移行する。
`include`/`extend`/`alias` は現時点ではそのまま維持する（将来の1ファイル1クラス分割後に front matter 移行を検討）。

```yaml
---
category: Network
require:
  - cgi/core
  - cgi/cookie
sublibrary:
  - rubygems/gem_runner
---
```

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
| `#@include` | 段階的移行において RD/MD 混在を許容するため |
| `#@#` コメント | そのまま維持 |
| `include`/`extend`/`alias` | 将来ファイル分割後に再検討 |
| 処理順序（前処理→パース→HTML生成） | 既存の bitclust パイプラインと同じ |

---

## 未解決の課題

レビューの中で方針を決めたい項目です。

1. **`#@include` での RD/MD 混在**: 段階的移行期に `.rd` と `.md` が混在する場合の扱い
2. **コードブロック内の `#@` 指令**: 現行 RRD と同じくコードブロック内でも処理されるが、
   Markdown パーサーを利用して区別すべきか
3. **RBS 形式シグネチャの実運用**: `### def each: () { (untyped) -> void } -> self`
   のような RBS 形式をどの程度活用するか
4. **エディタ支援**: `#@` 指令用の VS Code TextMate grammar の作成

---

## サンプルファイル

実際の変換結果をサンプルとして用意しています（`doc/markdown-samples/`）。
すべて `bin/rrd2md` による実際の RRD → Markdown 変換出力です。

| ファイル | 元ファイル | 含まれる記法要素 |
|---------|-----------|-----------------|
| `Comparable.md` | `_builtin/Comparable` | module、`#@since`/`#@until`、param/raise、`title="..."` |
| `Array.md` | `_builtin/Array` | class、include、クラス/インスタンスメソッド、複数シグネチャ、定数 |
| `String.md` | `_builtin/String` | 本文小見出し、アンカー `{#id}`、複雑なバージョン分岐、**SEE** |
| `cgi_core.md` | `cgi/core.rd` | ライブラリファイル、定義リスト、定数テーブル、GFM テーブル |

---

## RRD との記法対応表（早見表）

| RRD | Markdown |
|-----|----------|
| `= class Foo < Bar` | `# class Foo < Bar` |
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

以下の観点でご意見をいただけると助かります:

1. **記法の読みやすさ**: 提案する Markdown 記法は、RRD と比べて読みやすいか？書きやすいか？
2. **設計判断**: 上記の主要な設計判断（特にキーワード、`@` 除去、定義リスト）に違和感はないか？
3. **互換性**: GitHub プレビュー、エディタでの表示、既存ツールとの統合で問題になりそうな点はあるか？
4. **未解決課題**: 上記の未解決項目について、方針の提案があるか？
5. **その他**: 見落としている記法パターンや、考慮すべきユースケースがあるか？
