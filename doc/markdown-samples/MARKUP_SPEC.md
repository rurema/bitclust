# るりま Markdown 記法仕様（案）

本文書は、Ruby リファレンスマニュアル（るりま）のドキュメント形式を
RD ベースの独自記法（RRD）から Markdown ベースの記法へ移行するための仕様を定める。

## 背景と方針

- **ベース仕様**: GitHub Flavored Markdown (GFM)
- **プリプロセッサ**: 既存の `#@` 指令を維持（Liquid には依存しない）
- **移行戦略**: まず Markdown → RD 変換レイヤーを構築して既存 bitclust 上で記法を検証し、
  段階的に Markdown 記法への移行を進め、最終的に bitclust に依存しない新システムへ移行する
- **設計原則**:
  - 処理系に依存しない記法を選択する
  - 構造データは YAML front matter に集約する
  - 本文は極力標準 GFM に従い、独自拡張を最小限にする
  - 既存の Markdown エコシステム（エディタ、プレビュー）との互換性を重視する

## 前回調査（2022-2023）からの変更点

| 項目 | 前回（bitclust markdown 記法） | 本仕様 |
|------|-------------------------------|--------|
| プリプロセッサ | Liquid (`{% if %}`) | `#@since`/`#@until`/`#@if` を維持 |
| コメント | `{% comment %}` | `#@#` を維持 |
| include | Liquid `{% include %}` 予定 | `#@include` を維持 |
| `include`/`extend`/`alias` | 未定 | front matter に集約（`library`/`since`/`until` と統合） |
| メソッドシグネチャ | `def` のみ | `def`/`const`/`gvar`/`module_function def` |
| モジュール関数参照 | 未定 | `[m:Kernel?.open]`（RBS `self?` 由来） |
| `@param` 記法 | `* *param* name -- 説明` | `` - **param** `name` -- 説明 `` |
| `@see` 記法 | 未定 | `- **SEE** [リンク]`（リスト形式） |
| アンカー | 未定 | `{#id}`（kramdown/Pandoc 互換） |
| コードブロックラベル | 未対応 | `title="ラベル"` |

---

## 1. YAML Front Matter

ファイル冒頭に `---` で囲まれた YAML ブロックを置き、構造データ・関係データを記述する。
エンティティの宣言（種別・名前・継承）は H1 が担い（§2.2）、front matter には
タイトルに現れない関係的・構造的メタデータを集約する。

> **本節は確定仕様である。** 旧変換器は `include`/`extend`/`alias` を本文へパススルーし、
> メタ行に `#@` が混在する場合は front matter 生成をスキップしていた。本節の確定により
> いずれも front matter へ集約する（変換器側の実装は §14 の対応項目）。

### 1.1 ファイル構成モデルと種別

移行後は **1ファイル＝1エンティティ** を基本単位とし、`refm/api/src/**/*.md` を
glob して各ファイルの front matter と H1 を読み取り、構成を組み立てる。
旧 RRD 世界の `LIBRARIES` マニフェストと、ライブラリ→クラスの grouping 用 `#@include` は
**新パイプラインでは使用しない**（旧 `.rd` 世界はそのまま凍結して共存させる。移行手順は別途）。

ファイルは内容によって次の3種に分類する。**拡張子はすべて `.md`** とし、種別は拡張子ではなく
内容で判定する。

| 種別 | 判定条件 | front matter |
|------|---------|-------------|
| エンティティ | エンティティ H1（`# class`/`# module`/`# object`/`# reopen`/`# redefine`）を持つ | クラス系メタデータ（§1.2） |
| ライブラリ/サブライブラリ | `type: library` を持つ | ライブラリメタデータ（§1.3） |
| 共有断片 | 上記いずれも持たない | なし（`#@include` で本文へ展開。§1.4） |

- 1ファイルが「ライブラリ」と「エンティティ」を兼ねてもよい（`type: library` とエンティティ H1 を併記）。
  単一ファイルで1クラスを提供する小規模ライブラリ（例: `pathname`）がこれに当たる。
- **孤児検出**: `refm/api/src` 配下に、エンティティ H1 も `type: library` も持たず、
  かつどの `#@include` からも参照されない `.md` があればビルドで警告する
  （H1 の書き忘れによるエンティティの取りこぼしと、参照されない断片の双方を検出する）。

### 1.2 クラス/モジュール/オブジェクトのメタデータ

```yaml
---
library: _builtin
include:
  - Enumerable
extend:
  - Foo
alias:
  - OldName
since: "3.2"
until: "4.0"
---
# class Array < Object

配列クラスです。
```

| キー | 型 | 説明 |
|------|-----|------|
| `library` | String | 所属ライブラリ（スカラ）。`require` 不要で使えるか等の所属を表す |
| `include` | String[] | mixin する module |
| `extend` | String[] | extend する module |
| `alias` | String[] | このエンティティ自体の別名 |
| `since` | String | このエンティティが存在する最小バージョン（構造的版ゲート、任意） |
| `until` | String | このエンティティが存在しなくなるバージョン（構造的版ゲート、任意） |

- 種別（class/module/object/reopen/redefine）・名前・継承は **H1** が担い、front matter には重複させない。
- `include`/`extend`/`alias` は本文ではなく front matter に置く（リスト形式。単一でも配列）。
- `reopen`/`redefine` の `include`/`extend` は dynamic include/extend に対応する。`reopen` に `alias` は無い。
- `library` はスカラ。**所属はファイルの置き場所（ディレクトリ）ではなく front matter が決める**
  （例: `thread/ConditionVariable.md` は物理的に `thread/` 配下だが `library: _builtin`）。
  ディレクトリは所属に無関係なので、置き場所の差は問題を起こさない。
- 対応版スコープ（3.0 以降）では、所属が版で変わる／複数になるケースは発生しない
  （thread → `_builtin` の移動も、`thread` への重複 include も `< 2.3` に閉じている）。
  仮に所属を版で切り替える必要が生じた場合は §1.6 の `#@` を front matter 内で使えるが、
  `library` はスカラのため未前処理の生 YAML では重複キーになる（§1.6 の制限に該当）。
  その場合は、ライブラリごとの寄与（基底の `class`/`module` 定義と、各ライブラリによる
  `reopen`/`redefine`）を別ファイルに分け、各ファイルの `library` を単一に保つ方が明快。
  この「1ライブラリ × 1エンティティへの寄与」が分割の単位である。
- `since`/`until` は「エンティティ自体が版で出入りする」構造的ゲートを表す
  （旧 RRD で `#@include` を `#@since`/`#@until` で囲っていたものに相当）。
  メソッド内など本文中の版分岐は従来どおり本文に `#@since` 等を書く（§8.1）。

### 1.3 ライブラリ/サブライブラリのメタデータ

H1 にエンティティ宣言を持たないライブラリ概要ファイルでは `type: library` を明示する。

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
# CGI

ライブラリ概要の散文……
```

| キー | 型 | 説明 |
|------|-----|------|
| `type` | String | `library`（ライブラリ概要ファイルであることの明示） |
| `category` | String | ライブラリのカテゴリ |
| `require` | String[] | 依存ライブラリのリスト |
| `sublibrary` | String[] | サブライブラリのリスト |
| `since`/`until` | String | ライブラリ自体の版ゲート（任意） |

- `require`/`sublibrary` は常に配列形式で記述する（単一でも配列）。
- ライブラリ名はファイルパスから決まる（`<lib>.md` → ライブラリ `<lib>`、`<lib>/<sub>.md` → サブライブラリ）。

### 1.4 共有断片ファイル

複数箇所で再利用される内容の断片（例: `pack-template`, `printf-format`, `Module.define_method`）。

- front matter もエンティティ H1 も持たない。
- glob（`api/src/**/*.md`）には**マッチするが、エンティティとして登録されない**
  （断片と判定してスキップする）。内容は、それを `#@include` するファイルの前処理時に本文へ展開される（§8.2）。
- 拡張子は他と同じ `.md`。単体ではページとして成立しないが、それは許容する。
- GFM に include 相当が無いため、共有手段として `#@include` を維持する。

### 1.5 doc ファイルのメタデータ

`refm/doc/` 配下の散文ドキュメントは最小限のメタデータを持つ（すべて任意）。

```yaml
---
title: 多言語化と文字列のエンコーディング
---
```

`title` 省略時は本文先頭の H1 をタイトルとする。版ゲートが必要なら `since`/`until` を付ける。

### 1.6 front matter 内のバージョン分岐

版によって値が異なる場合は、front matter の**中**に `#@since`/`#@until`/`#@if` を書く。

```yaml
---
library: _builtin
include:
  - Enumerable
#@since 3.1
  - Comparable
#@end
require:
  - foo
#@since 3.0
  - bar
#@end
---
```

**処理順序**: 前処理（`#@` 指令の解決）→ YAML パース → Markdown パース（§8.4）。

- `#@…` 行は `#` 始まりのため **YAML コメント**として解釈される。
  前処理を行わないツール（GitHub のプレビュー等）でも YAML は壊れず、
  全バージョンの**和集合**として表示される。
- リスト値フィールド（`include`/`extend`/`alias`/`require`/`sublibrary`）では、
  版による要素の増減をこの方法で過不足なく表現できる。
- **制限**: スカラ値を版で丸ごと差し替える場合（例: `category` が版で変わる）は、
  前処理しない生の YAML では重複キーになる。稀なケースであり、
  必要なら当該フィールドのみ front matter 外で表現する。

### 1.7 H1 と front matter の責務分担

| 情報 | 置き場所 |
|------|---------|
| 種別・名前・継承 | **H1**（`# class Array < Object`） |
| 所属ライブラリ | front matter `library`（スカラ） |
| mixin・別名 | front matter `include`/`extend`/`alias`（リスト） |
| エンティティの構造的版ゲート | front matter `since`/`until` |
| ライブラリのメタデータ | front matter `type: library` + `category`/`require`/`sublibrary` |
| メソッド内など本文中の版分岐 | 本文の `#@since`/`#@until`/`#@if`（不変） |

---

## 2. 見出し構造

ATX 形式（`# heading`）のみを使用する。Setext 形式は使用しない。

### 2.1 見出しレベルの対応

| レベル | 用途 | 例 |
|--------|------|-----|
| `#` (h1) | クラス/モジュール/オブジェクト定義 | `# class Array < Object` |
| `##` (h2) | メソッドカテゴリ | `## Instance Methods` |
| `###` (h3) | メソッドシグネチャ / 本文小見出し | `### def each` / `### 破壊的な変更 {#mutable}` |
| `####` (h4) | 本文のさらに深い小見出し | `#### 文字列同士の比較・結合` |
| `#####` (h5) | 本文の最深小見出し（稀） | `##### まとめ` |

### 2.2 クラス/モジュール定義（h1）

```markdown
# class Array < Object
# module Comparable
# module Kernel
# object ENV
# reopen Kernel
```

`class`、`module`、`object`、`reopen` のキーワードで種別を示す。
継承関係は `< SuperClass` で記述する。

### 2.3 メソッドカテゴリ（h2）

```markdown
## Class Methods
## Instance Methods
## Module Functions
## Constants
## Special Variables
## Private Instance Methods
## Protected Instance Methods
```

### 2.4 本文小見出しとアンカー

本文中の小見出しには kramdown/Pandoc 互換の `{#id}` でアンカーを付与できる。

```markdown
### 多言語化と文字列のエンコーディング {#m17n}
#### 文字列同士の比較・結合
```

アンカーへの参照は標準 Markdown リンクで行う: `[テキスト](#m17n)`

---

## 3. メソッドシグネチャ

h3 レベル（`###`）で記述する。キーワード（`def`/`const`/`gvar`/`module_function def`）の
有無と種類で本文小見出しおよびエントリの種別を区別する。

### 3.1 Ruby 構文形式

```markdown
### def each {|item| ... } -> self
### def Array.try_convert(obj) -> Array | nil
### def self.new(size = 0, val = nil) -> Array
### module_function def measure(label) -> Benchmark::Tms
### const CR -> String
### gvar $DEBUG -> bool
```

| メソッド種別 | 記法 | 区別方法 |
|-------------|------|---------|
| インスタンスメソッド | `### def method(args)` | `def` キーワード |
| クラスメソッド / 特異メソッド | `### def ClassName.method(args)` | `def` + `ClassName.` |
| クラスメソッド（RBS 互換） | `### def self.method(args)` | `def` + `self.` |
| モジュール関数 | `### module_function def method(args)` | `module_function def` |
| 定数 | `### const CONST -> Type` | `const` キーワード |
| グローバル変数 | `### gvar $VAR -> Type` | `gvar` キーワード |
| 本文小見出し | `### 見出しテキスト` | キーワードなし |

RRD との相互変換では `ClassName.method` をそのまま保持する（`self.` への変換はしない）。

### 3.2 RBS 形式

`:` の位置で Ruby 構文形式と区別する。

```markdown
### def self.try_convert: (untyped obj) -> Array[untyped]?
### def each: () { (untyped) -> void } -> self
```

| 判定基準 | 形式 |
|---------|------|
| `def name(` または `def name ->` | Ruby 構文 |
| `def name:` | RBS |

### 3.3 定数

`const` キーワードを付ける。

```markdown
### const CR -> String
### const NEEDS_BINMODE -> bool
```

### 3.4 グローバル変数

`gvar` キーワードを付ける。

```markdown
### gvar $DEBUG -> bool
### gvar $ERROR_INFO -> Exception | nil
```

### 3.5 モジュール関数

`module_function def` キーワードを付ける。

```markdown
### module_function def measure(label) -> Benchmark::Tms
### module_function def realtime { ... } -> Float
```

### 3.6 エイリアスメソッド

同一メソッドの別名は `###` 行を連続して記述する。

```markdown
### def [](nth) -> object | nil
### def at(nth) -> object | nil

nth 番目の要素を返します。
```

### 3.7 バージョン分岐を含むシグネチャ

```markdown
### def self.new(string = "") -> String
#@since 2.4.0
### def self.new(string = "", encoding: string.encoding, capacity: 127) -> String
#@end
```

---

## 4. メソッドエントリの構造

各メソッドエントリは以下の順序で構成する。
（[ReferenceManualFormatDigest](https://github.com/rurema/doctree/wiki/ReferenceManualFormatDigest) に準拠）

1. **シグネチャ**（必須）: `### def method(args) -> Type`
2. **要約**（必須）: 1段落での概要説明
3. **詳細説明**: 追加の説明文（任意）
4. **param/return/raise**: パラメータ・返り値・例外の説明
5. **注意事項**: 追加の警告など（任意）
6. **使用例**: サンプルコード
7. **SEE**: 関連メソッド参照（リスト形式）

---

## 5. パラメータ・返り値・例外

`@param`/`@return`/`@raise` に代わるリスト形式で記述する。
`@` プレフィクスは使用しない（GitHub issue/PR でのメンション誤爆を回避）。

### 5.1 基本形式

```markdown
- **param** `name` -- 説明文
- **return** -- 説明文
- **return** `Type` -- 説明文
- **raise** `ExceptionClass` -- 説明文
```

- 種別ラベルはボールド体: `**param**`, `**return**`, `**raise**`
- パラメータ名・例外クラス名はコードスパン: `` `name` ``, `` `TypeError` ``
- 区切りは `--`（ASCII ハイフン2つ）
- 複数行の説明はインデントで継続

### 5.2 例

```markdown
- **param** `nth` -- インデックスを整数で指定します。
           先頭の要素が 0 番目になります。nth の値が負の時には末尾から
           のインデックスと見倣します。
- **param** `val` -- 設定したい要素の値を指定します。
- **return** `String` -- 変換後の文字列
- **return** `nil` -- 変換できなかった場合
- **raise** `TypeError` -- 引数に整数以外のオブジェクトを指定した場合に発生します。
- **raise** `IndexError` -- 指定された nth が自身の始点よりも前を指している場合に発生します。
```

---

## 6. SEE（関連メソッド参照）

param/raise と同様にリスト形式で記述する。
HTMLでの `[SEE_ALSO]` 表示に対応し、大文字のボールド体とする。

```markdown
- **SEE** [m:String#-@]
```

カンマ区切りの複数参照は1つの SEE 項目内にそのまま保持する:

```markdown
- **SEE** [m:String#encode], [m:String#encode!]
```

RRDの `@see` が複数行に分かれている場合は個別の項目になる:

```markdown
- **SEE** [m:CGI.accept_charset]
- **SEE** [m:CGI.accept_charset=]
```

---

## 7. クロスリファレンス（ハイパーリンク）

RRD の `[[type:target]]` から角括弧を1段減らし `[type:target]` とする。
前回調査（2022-2023）の設計を踏襲。

### 7.1 記法一覧

| 種別 | 記法 | 例 |
|------|------|-----|
| クラス | `[c:ClassName]` | `[c:String]` |
| メソッド | `[m:Class#method]` | `[m:Array#each]` |
| クラスメソッド | `[m:Class.method]` | `[m:CGI.accept_charset]` |
| モジュール関数 | `[m:Class?.method]` | `[m:Kernel?.open]` |
| ライブラリ | `[lib:name]` | `[lib:json]` |
| C 関数 | `[f:name]` | `[f:rb_str_new]` |
| ドキュメント | `[d:path]` | `[d:spec/m17n]` |
| ドキュメント+アンカー | `[d:path#anchor]` | `[d:spec/m17n#m17n]` |
| RFC | `[RFC:number]` | `[RFC:822]` |
| man ページ | `[man:command(section)]` | `[man:grep(1)]` |
| ML | `[ruby-list:number]` | `[ruby-list:35911]` |
| bugs.ruby-lang.org | `[feature:number]` | `[feature:12345]` |

モジュール関数の `?` は RBS の `self?` に由来し、RRD の `.#` typemark に対応する。

### 7.2 メソッド名のエスケープ

メソッド名に `[` `]` `\` を含む場合はバックスラッシュでエスケープする。

```markdown
[m:Hash#\[\]]          ← Hash#[]
[m:String#\[\]=]       ← String#[]=
[m:$\\]                ← $\
```

### 7.3 表示テキスト付きリンク（将来対応予定）

Markdown のリンク記法を活用して表示テキストを指定できる:

```markdown
[Array#dup][m:Array#dup]
[spec/m17n][d:spec/m17n]
```

現在の変換器は bare ref (`[type:target]`) のみ生成・変換する。
表示テキスト付きリンクの対応は Markdown 移行後に行う。

### 7.4 外部 URL

通常の Markdown リンク記法を使用する:

```markdown
<https://example.com>
[例示ドメイン](https://example.com)
```

### 7.5 ファイル内アンカー参照

標準 Markdown のフラグメントリンクを使用する:

```markdown
[破壊的な変更](#mutable)
```

---

## 8. プリプロセッサ指令

既存の `#@` 指令をそのまま維持する。
`#@` は CommonMark で見出し（ATX heading）として解釈されないため安全である
（ATX heading は `#` の後にスペースが必要）。

### 8.1 バージョン条件

```markdown
#@since 3.0
（Ruby 3.0 以降の内容）
#@end

#@until 3.2
（Ruby 3.2 より前の内容）
#@end

#@if (version >= "3.1")
（条件を満たす場合の内容）
#@else
（条件を満たさない場合の内容）
#@end
```

### 8.2 ファイルインクルード

共有断片（§1.4）の取り込みに使用する。ライブラリ→クラスの grouping には**使用しない**
（front matter `library` + glob に置き換え。§1.1 参照）。

```markdown
#@include(_builtin/pack-template)
```

参照は拡張子なしで記述し、リゾルバが `.md` を補完する。

### 8.3 コメント

```markdown
#@# これはコメント（出力されない）
```

### 8.4 処理順序

**前処理 → YAML front matter パース → Markdown パース → HTML 生成**

前処理はテキストレベルで行われるため、Markdown の構文要素（コードブロック等）の
中にある `#@` 指令も処理される。これは RRD と同じ挙動である。

---

## 9. コードブロック

GFM 標準のフェンスドコードブロックを使用する。

### 9.1 基本形式

````markdown
```ruby
puts "hello"
```
````

### 9.2 ラベル（タイトル）

info string の `title=` 属性でラベルを付与する。
これは Docusaurus、MkDocs Material、Hugo、Expressive Code 等で
採用されているデファクトスタンダードである。

````markdown
```ruby title="nil を渡す例"
5.clamp(0, nil)          #=> 5
5.clamp(nil, 0)          #=> 0
```
````

`title=` 非対応の処理系では無視される（表示上の劣化のみで情報は失われない）。

### 9.3 RRD インデントコードブロック

RRD ではインデントされたテキストが整形済みテキスト（`<pre>`）になる。
Markdown ではバッククォートの個数で元のインデント幅をエンコードする。

````
N個のバッククォート = 3 + 元のインデント幅

例: 2スペースインデント → 5個のバッククォート
`````
code line 1
code line 2
`````
````

コードブロック内のベースインデントは除去される。
逆変換時はバッククォートの個数からインデント幅を復元する。

### 9.4 RRD からの変換一覧

| RRD | Markdown |
|-----|----------|
| `#@samplecode ラベル` ... `#@end` | ```` ```ruby title="ラベル" ```` ... ```` ``` ```` |
| `#@samplecode` ... `#@end` | ```` ```ruby ```` ... ```` ``` ```` |
| `//emlist[ラベル][lang]{` ... `//}` | ```` ```lang title="ラベル" ```` ... ```` ``` ```` |
| インデントテキスト（Nスペース） | `(3+N)` 個のバッククォートで囲む |

### 9.5 インラインコード

テキスト行中の `__WORD__` パターン（`__END__`, `__FILE__` 等）は
自動的にコードスパンに変換される。ブラケットリンク内の `__WORD__` は変換しない。

---

## 10. 通常のテキスト

GFM の記法に従う。

### 10.1 リスト

```markdown
- 項目1
- 項目2
  - ネストした項目
```

番号付きリストは GFM 標準の形式を使用する。
RRD の ` (1)` 形式に対応する。

```markdown
1. 最初の項目
2. 次の項目
3. 最後の項目
```

段落で分断された番号付きテキスト（RRD で `N.` 形式）は、
Markdown で番号付きリストに誤解釈されないよう太字番号で記述する。

```markdown
**1.** クラス定義の中で、Exception2MessageMapper を extend すれば、
def_e2message メソッドや def_exception メソッドが使えます。

例:
...

**2.** 何度も使いたい例外クラスは、クラスの代わりにモジュールで定義して、
それを include して使います。
```

### 10.2 定義リスト的な記述

RRD の定義リスト（`: term` / `  definition`）に相当する記法として、
ボールドリストを使用する。GFM は定義リストに未対応のため、
GFM 互換のリスト形式で記述する。

```markdown
- **`type`**: Content-Type ヘッダです。デフォルトは "text/html" です。
- **`charset`**: ボディのキャラクタセットを Content-Type ヘッダに追加します。
```

短い英数字/記号の term（40文字未満、日本語を含まない）は自動的にコードスパン化される: `` **`term`** ``。
日本語を含む term や長い term はプレーンテキスト: `**term**`。

`` - **param** `name` -- 説明 `` との区別:
- 定義リスト: `` - **`term`**: description ``（コロン区切り）
- メタデータ: `` - **param** `name` -- description ``（ダブルハイフン区切り）

### 10.3 テーブル

GFM テーブルを使用できる。

```markdown
| 文字列 | ステータス |
|--------|-----------|
| `"OK"` | `"200 OK"` |
```

---

## 11. パーサーの見出し判定ロジック

h3 行の種別判定（キーワードベース）:

```
1. `### module_function def ` → モジュール関数
2. `### def ` → メソッドシグネチャ
   - `def name:` → RBS 形式
   - `def ClassName.name` or `def self.name` → クラスメソッド / 特異メソッド
   - `def name` → インスタンスメソッド
3. `### const ` → 定数
4. `### gvar ` → グローバル変数
5. それ以外の `### ` → 本文小見出し
```

キーワードの有無で明確に区別できるため、セクションコンテキスト（`## Constants` 等）
による文脈依存の判定は不要。

---

## 12. RRD との記法対応表

| RRD | Markdown | 備考 |
|-----|----------|------|
| `= class Foo < Bar` | `# class Foo < Bar` | h1 |
| `== Instance Methods` | `## Instance Methods` | h2 |
| `--- method(args) -> Type` | `### def method(args) -> Type` | `def` キーワード |
| `--- ClassName.method(args)` | `### def ClassName.method(args)` | クラスメソッド |
| Module Functions 内 `--- method` | `### module_function def method` | モジュール関数 |
| `--- CONST -> Type` | `### const CONST -> Type` | `const` キーワード |
| `--- $VAR -> Type` | `### gvar $VAR -> Type` | `gvar` キーワード |
| `===[a:name] 見出し` | `### 見出し {#name}` | kramdown/Pandoc 互換 |
| `==== 小見出し` | `#### 小見出し` | h4 |
| `include Mod` | front matter `include: [Mod]` | YAML |
| `extend Mod` | front matter `extend: [Mod]` | YAML |
| `alias Name` | front matter `alias: [Name]` | YAML |
| `category Cat` | front matter `category: Cat` | YAML |
| `require lib` | front matter `require: [lib]` | YAML |
| `sublibrary lib` | front matter `sublibrary: [lib]` | YAML |
| `[[c:String]]` | `[c:String]` | 角括弧1段減 |
| `[[m:Array#each]]` | `[m:Array#each]` | 角括弧1段減 |
| `[[m:Kernel.#open]]` | `[m:Kernel?.open]` | `.#` → `?` |
| `[[m:Hash#[] ]]` | `[m:Hash#\[\]]` | `\` エスケープ |
| `[[ref:name]]` | `[テキスト](#name)` | 標準 Markdown リンク |
| `@param name 説明` | `` - **param** `name` -- 説明 `` | リスト形式 |
| `@return 説明` | `- **return** -- 説明` | リスト形式 |
| `@raise Ex 説明` | `` - **raise** `Ex` -- 説明 `` | リスト形式 |
| `@see [[m:...]]` | `- **SEE** [m:...]` | リスト形式 |
| `#@since VER` | `#@since VER` | **そのまま維持** |
| `#@until VER` | `#@until VER` | **そのまま維持** |
| `#@if (cond)` | `#@if (cond)` | **そのまま維持** |
| `#@else` | `#@else` | **そのまま維持** |
| `#@end` | `#@end` | **そのまま維持** |
| `#@include(file)` | `#@include(file)` | **そのまま維持** |
| `#@#` | `#@#` | **そのまま維持** |
| `#@samplecode ラベル` | ```` ```ruby title="ラベル" ```` | Ruby コード |
| `//emlist[cap][lang]{` | ```` ```lang title="cap" ```` | 非 Ruby コード |
| `* item` | `- item` | GFM リスト |
| `(1) item` | `1. item` | GFM 番号付きリスト |
| `N. text`（離散） | `**N.** text` | 太字番号テキスト |
| `: term` / `  def` | `` - **`term`**: def `` | ボールドリスト |

---

## 13. サンプルファイル

本仕様に基づくサンプルファイルは `doc/markdown-samples/` ディレクトリに格納されている。
各ファイルは `bin/rrd2md` による実際の RRD→MD 変換出力から生成されたものである。

| ファイル | 元ファイル | 検証内容 |
|---------|-----------|---------|
| `Comparable.md` | `_builtin/Comparable` | module、since/until、param/raise、title=、module_function |
| `Array.md` | `_builtin/Array` | class、include、class/instance methods、複数シグネチャ、const |
| `String.md` | `_builtin/String` | 本文小見出し(`###`/`####`)、アンカー `{#id}`、複雑なバージョン分岐、**SEE** |
| `cgi_core.md` | `cgi/core.rd` | ライブラリサブファイル、定義リスト、定数、GFM テーブル、**SEE** |

---

## 14. 未決事項・今後の検討

### 解決済み

- [x] RD ↔ MD 双方向変換器の実装（826/826 ファイルでロスレスラウンドトリップ達成）
- [x] 定義リストの Markdown 記法（GFM 互換の `` - **`term`**: description `` 形式を採用）
- [x] 複数行にまたがるリスト項目の Markdown 表示品質改善（継続行対応済み）
- [x] `@param`/`@see` 等の継続行が `#@` ディレクティブを挟む場合の対応（ネスト追跡で解決）
- [x] `[c:String]` 等のリンク記法（RRD `[[...]]` ↔ MD `[...]` の双方向変換で解決）
- [x] front matter スキーマの確定（1ファイル1エンティティ、`library` スカラ、共有断片の扱い、front matter 内版分岐。§1）
- [x] `include`/`extend`/`alias` を front matter へ集約する方針の確定（§1.2。変換器実装は未解決へ）

### 未解決

- [ ] `#@include` での RD/MD 混在対応（段階的移行期の課題）
- [ ] エディタ支援: `#@` 指令用の VS Code TextMate grammar 作成
- [ ] プリプロセッサがコードブロック内の `#@` を処理する挙動の是非
  - 現行 RRD と同じ挙動だが、Markdown パーサーの結果を利用して
    コードブロック内の指令を区別すべきか要検討
- [ ] kramdown での `{#id}` 対応状況の詳細検証
- [ ] `refe` コマンド等でのプレーンテキスト表示時の可読性確認
- [ ] RBS 形式シグネチャの実運用テスト
- [ ] 新システム（bitclust 脱却後）のパーサー実装方針
- [ ] 変換器の front matter 対応実装（§1）
  - `include`/`extend`/`alias` を本文から front matter へ移送（版条件は `#@` 付きで）
  - `#@include` グラフと版ゲートを辿り、エンティティに `library`（スカラ）と構造的 `since`/`until` を付与
  - grouping 用 `#@include` の除去と、共有断片 `#@include` の温存・拡張子なし正規化
  - front matter 内 `#@` 出力対応（旧「メタ行に `#@` があると front matter 生成をスキップ」制限の解除）
- [ ] 新パイプラインのファイル発見（glob + front matter）と孤児検出（§1.1）
