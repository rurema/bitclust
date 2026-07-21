# るりま Markdown 記法仕様（案）

本文書は、Ruby リファレンスマニュアル（るりま）のドキュメント形式を
RD ベースの独自記法（RRD）から Markdown ベースの記法へ移行するための仕様を定める。

## 背景と方針

- **ベース仕様**: GitHub Flavored Markdown (GFM)
- **プリプロセッサ**: 既存の `#@` 指令を維持（Liquid には依存しない）
- **移行戦略**: まず Markdown → RD 変換レイヤーで既存 bitclust 上の等価性を証明し
  （完了）、次に bitclust 自体が Markdown をネイティブにパース・描画する段階へ進む
  （完了。変換レイヤーはビルド経路から外れ検証用に残存）。bitclust に依存しない
  新システムへの移行は当面不要と判断（2026-07。記法とビルドは分離されているため、
  必要になれば記法に影響なくツールを置き換えられる）
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
> いずれも front matter へ集約する（変換器側の実装は §15 の対応項目）。

### 1.1 ファイル構成モデルと種別

移行後は **1ファイル＝1エンティティ** を基本単位とし、`manual/api/**/*.md` を
glob して各ファイルの front matter と H1 を読み取り、構成を組み立てる
（新ツリーは doctree トップの `manual/` 配下。旧 `refm/` は凍結して共存し、
`src`/`md` の階層は新ツリーでは使わない）。
旧 RRD 世界の `LIBRARIES` マニフェストと、ライブラリ→クラスの grouping 用 `#@include` は
**新パイプラインでは使用しない**（旧 `.rd` 世界はそのまま凍結して共存させる。移行手順は別途）。

例外として、**ヘッダ関係（include/extend/alias）を持たないエンティティ**は
1ファイルに複数束ねてもよい（マルチエンティティファイル。`Errno::EXXX` 152件や
「本体クラス＋そのエラークラス」対のような自然な束ねを許す）。発見はファイル内の
**全エンティティ H1** を読み、ファイルの front matter（`library`/`since`/`until`）は
中の全エンティティに適用される。**関係を持つエンティティは必ず単独ファイルにする**
（関係の記述場所を front matter に一元化するため。マルチエンティティファイルに
関係キーや H1 直後の関係行があればビルド警告とし、その時点で分割する）。

ファイルは内容によって次の3種に分類する。**拡張子はすべて `.md`** とし、種別は拡張子ではなく
内容で判定する。

| 種別 | 判定条件 | front matter |
|------|---------|-------------|
| エンティティ | エンティティ H1（`# class`/`# module`/`# object`/`# reopen`/`# redefine`）を持つ | クラス系メタデータ（§1.2） |
| ライブラリ/サブライブラリ | `type: library` を持つ | ライブラリメタデータ（§1.3） |
| 共有断片 | 上記いずれも持たない | なし（`#@include` で本文へ展開。§1.4） |

- 1ファイルが「ライブラリ」と「エンティティ」を兼ねてもよい（`type: library` とエンティティ H1 を併記）。
  単一ファイルで1クラスを提供する小規模ライブラリ（例: `pathname`）がこれに当たる。
- **孤児検出**: `manual/api` 配下に、エンティティ H1 も `type: library` も持たず、
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
  これが**唯一の記述場所**である（関係を持つエンティティは単独ファイルなので曖昧にならない。§1.1）。
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

#### 1.2.1 版で変わる・複数の所属（旧版サルベージ）

対象版スコープを 3.0 未満へ広げると、所属ライブラリが版で切り替わる、
または同時に複数になるエンティティが現れる（thread 系4クラス、旧 rdoc 系
20クラス）。この場合に限り、`library` は §1.6 のゲート付き**リスト**で記述する:

```yaml
---
library:
  - _builtin
#@until 1.9.1
  - thread
#@end
---
# class Mutex < Object
```

- 並び順は「現在まで存在する側（until なし）が先、次に名前順」
- 未前処理の生 YAML では `#@` 行はコメント = 全版の**和集合**リストとして表示される
- このときトップレベルの `since`/`until` はライブラリ横断の hull
  （エンティティ自体の存在ゲート）
- ビルドは版ごとに前処理で解決され、その版でゲートが生きている membership を
  持つライブラリだけがメンバーとして取り込む（同時多重所属の版では
  各ライブラリの下にそれぞれ取り込まれる = 旧 LIBRARIES 世界の
  ゲート付き多重 include と同義）

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
| `name` | String | ライブラリ名の明示（ファイル名衝突回避で改名されたファイルのみ。下記） |
| `category` | String | ライブラリのカテゴリ |
| `require` | String[] | 依存ライブラリのリスト |
| `sublibrary` | String[] | サブライブラリのリスト |
| `since`/`until` | String | ライブラリ自体の版ゲート（任意） |

- `require`/`sublibrary` は常に配列形式で記述する（単一でも配列）。
- ファイル全体が版ゲートで包まれ、かつライブラリの存在自体は旧 LIBRARIES が
  より広く定義しているライブラリ（cmath: LIBRARIES は until 2.7.0 のみ、
  ファイルは `#@since 1.9.1` で全包）では、ゲートは front matter に解除せず
  本文側に残す（そのライブラリは古い版にも「存在して内容が空」であるため）。
  このとき `require`/`sublibrary` は §1.6 のゲート付きリストとして、
  `category` は存在ゲートの `#@` 行で挟んだスカラとして front matter に置く
  （値の版差し替えは従来どおり非対応）:

```yaml
---
type: library
#@since 1.9.1
category: Math
#@end
---
```
- ライブラリ名はファイルパスから決まる（`<lib>.md` → ライブラリ `<lib>`、`<lib>/<sub>.md` → サブライブラリ）。
- **ファイル名の大文字小文字衝突の禁止**: 同一ディレクトリ内で大文字小文字のみが
  異なる名前（`rdoc/RDoc.md` と `rdoc/rdoc.md` 等）は、macOS/Windows の
  case-insensitive ファイルシステムでチェックアウト不能になるため禁止する
  （ビルド警告 + 変換器はエラー）。エンティティ名と衝突するライブラリファイルは
  basename に `.lib` を挟んで回避し（`rdoc/rdoc.lib.md`）、パスから導出できなく
  なった名前を `name:` で明示する。`name:` は md 側専用のキーで、rd への
  逆変換では現れない。

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
### module_function def measure(label) -> Benchmark::Tms
### const CR -> String
### gvar $DEBUG -> bool
```

| メソッド種別 | 記法 | 区別方法 |
|-------------|------|---------|
| インスタンスメソッド | `### def method(args)` | `def` キーワード |
| クラスメソッド / 特異メソッド | `### def ClassName.method(args)` | `def` + `ClassName.` |
| モジュール関数 | `### module_function def method(args)` | `module_function def` |
| 定数 | `### const CONST -> Type` | `const` キーワード |
| グローバル変数 | `### gvar $VAR -> Type` | `gvar` キーワード |
| 本文小見出し | `### 見出しテキスト` | キーワードなし |

RRD との相互変換では `ClassName.method` をそのまま保持する（`self.` への変換はしない）。
クラスメソッドを `self.` プレフィクスで書く形（`### def self.new(...)`）は
RBS 互換形式の一部として将来対応の対象（§3.2。**現状は未実装でビルドエラー**になる
ため、`ClassName.` を使うこと）。

### 3.2 RBS 形式（将来対応予定・現状未実装）

RBS 型シグネチャをそのまま書ける形式。`:` の位置で Ruby 構文形式と区別する。

```markdown
### def self.try_convert: (untyped obj) -> Array[untyped]?
### def each: () { (untyped) -> void } -> self
```

| 判定基準 | 形式 |
|---------|------|
| `def name(` または `def name ->` | Ruby 構文 |
| `def name:` | RBS |

クラスメソッドを `self.` プレフィクスで書く形（`### def self.new(...)`）も
RBS 互換形式の一部として将来対応の対象とする。

**現状、実装（パーサ・描画）はこの形式に対応していない**（2026-07 検証）。
書いた場合はパース時に「unsupported method signature」として明確なビルドエラーに
なる（誤った名前で DB に登録されたり statichtml がクラッシュしたりしないよう、
未対応形式は早期に拒否する）。対応する際は実装とあわせて §15 の項目として
再開すること（`def name:` は Ruby 構文形式と機械的に区別できるため、
後方互換のまま追加できる）。

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
2. **メソッド属性行**（任意）: `{: nomethod}` など（下記）
3. **要約**（必須）: 1段落での概要説明
4. **詳細説明**: 追加の説明文（任意）
5. **param/return/raise**: パラメータ・返り値・例外の説明
6. **注意事項**: 追加の警告など（任意）
7. **使用例**: サンプルコード
8. **SEE**: 関連メソッド参照（リスト形式）

### メソッド属性行（`{: ...}`）

シグネチャ見出しの直後の行に、kramdown の Block IAL に似た属性行を書ける。
`@` プレフィクスのメタデータ行（旧 `@undef`）はメンション誤爆のため廃止し、
この形式に一本化した。

```markdown
### def to_a -> Array
{: nomethod}

オブジェクトを配列に変換した結果を返します。
```

サポートする属性:

- `nomethod` — 説明のためだけに記載されていて実際には定義されていないメソッド
  （例: `Object#to_a`）。`kind = :nomethod` になり、クラスページで
  「説明のための未定義メソッド」として区分表示される。ページ生成・検索対象には残る
- `undef` — そのクラスで意図的に未定義化されているメソッド
  （例: `Complex` における `Comparable` の比較メソッド。旧 `@undef` 相当）。
  `kind = :undefined` になり、ページ生成・検索の対象外になる
- `since="X"` / `until="X"` — このシグネチャの名前が Ruby X から存在する
  （`since`）／ Ruby X で削除される（`until`。半開区間: X 未満のバージョンでは
  存在し、X 以降には存在しない）ことを明示する。X は `"3.2"` のように数字と
  ドットのみをダブルクォートで囲んで書く。シグネチャ見出しの横に
  since/until バッジとして表示される
- `since=""`（空値）— 「初出バージョンは不明（少なくとも記録が残る最古の
  バージョンより前から存在する）」ことを明示し、**バッジを表示しない**。
  メソッド自体は昔からあるのにリファレンスへの記載が後から追加されたために、
  自動算出（`bitclust methodsince`）が記載時期を初出として誤った版を
  表示してしまう場合の抑止に使う（例: `Array#collect` は Ruby 1.8 以前から
  存在するが、記載は 2.4.0 のドキュメント凍結後に追加されたため
  「Ruby 2.5.0 から」と誤って算出される）。
  別名（複数シグネチャ）のエントリで抑止する場合は、抑止したいすべての
  シグネチャ見出しの直後にそれぞれ付けること。`until=""` も同様

規則:

- 属性行は**直前のシグネチャ見出し行のみ**に束縛される（kramdown の Block IAL と
  同じ解釈）。別名（複数シグネチャ）のエントリで使う場合はすべてのシグネチャ見出しの
  直後にそれぞれ付ける。一部にだけ付いているとビルドエラー
  （kind はエントリ単位でしか持てないため）
- ただし `since=`/`until=` は `nomethod`/`undef` と違い**シグネチャ単位**の
  値であり、別名ごとに異なるバージョンを持ってよい（全シグネチャで揃える必要は
  ない）。追加/削除時期が別名ごとに違う場合が本来の用途:

  ```markdown
  ### def -@ -> object
  {: since="2.0.0"}
  ### def dedup -> object
  {: since="3.0"}
  ```

  （本体 `-@` は Ruby 2.0.0 から、別名 `dedup` はそれより後の Ruby 3.0 から、
  という例。それぞれのシグネチャ見出しの横に別々の since バッジが付く）
- シグネチャ見出し行と属性行が連続している範囲がひとつのエントリ（別名グループ）に
  なる。属性行の直後に別エントリを続ける場合は空行で区切る
- パーサーの属性行探索はシグネチャブロックの直後で打ち切る
  （コードブロック中の `{: ...}` 風の行を誤検出しない。空行を挟んだ `{: ...}` は
  ただの本文）
- 未知の属性・不正な形式（`since=X` のような非引用値、`since=""` のような
  空値、数字とドット以外を含む値、未知のキーなど）はビルドエラー（typo 検出）
- 明示された `since`/`until` は、全バージョンの DB を横断して自動算出する
  `bitclust methodsince` サブコマンドの結果より常に優先される（算出側は既に
  値がある名前を上書きしない）。主な用途は自動算出が届かない 1.8.7 以前からの
  存在（フロア救済）や、算出結果の補正

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

モジュール関数の `?.` は RRD の `.#` typemark に対応する（`?` は RBS の `self?` に由来）。

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

前処理はテキストレベル（行単位）で行われるため、Markdown の構文要素
（コードブロック等）の中にある行頭の `#@` 指令も処理される。
RRD と同じ挙動であり、**これを確定仕様とする**（2026-07 決定）。

コードブロック内でも処理する理由:

- **コード例の版分岐が多用されている**: フェンス内の `#@since`/`#@else`/`#@end`
  （出力やエラーメッセージの版差の表現）は manual/ 全体で 400 行超・50 ファイル超で
  現役使用。`#@#` によるコード例内の行の無効化も使われている
- **フェンス構造自体がゲートで変わりうる**: フェンスの区切り行がゲートの片側の
  分岐にだけ現れるソースが実在する（spec/pattern_matching）。この場合
  「Markdown をパースしてからコードブロック内の指令を除外する」方式は、
  パースに必要なフェンス構造が前処理の結果で決まるため原理的に成立しない
  （処理順序が 前処理 → パース である以上、前処理は Markdown 構造を知り得ない）
- 前処理しないツール（GitHub プレビュー等）ではフェンス内の `#@` 行は
  コードの一部としてそのまま表示され、全バージョンの和集合として読める

イディオム:

- コード例の一部（出力など）が版で異なる → フェンス内に `#@since`/`#@else` を書く
- フェンスの区切りや個数自体が版で異なる → フェンスをゲートで包んで分岐ごとに
  完結したフェンスを書く。それも表現できない場合の逃げ道として `#@samplecode`
  （区切り記号を持たず `#@end` のネストを追跡する）が使える
- 制約: コードブロック内に**行頭リテラルの `#@`** は書けない（指令として処理される。
  manual/ は Ruby の文書でありこの記法自体を例示する需要は無い — 必要になった場合は
  行頭に空白を1つ入れる）

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

### 9.3 構文チェックと `invalid` 属性

`ruby`（および `rb` などの Rouge 上の alias）のコードブロックは、ビルド時に
Ripper による構文チェックを兼ねたハイライトが行われ、パースできない場合は
ビルドエラーになる。

SyntaxError の例や文法の一部分など、**構文として完全でないコード**を Ruby と
して色付けしたい場合は、info string に `invalid` 属性を付ける。構文チェックは
行われず、Rouge の Ruby lexer（字句解析ベース）で色付けされる。

````markdown
```ruby invalid
def method_name(  # 引数リストが途中の断片
```
````

- `title=` と併用する場合の順序は `lang invalid title="..."`
- lang は `ruby` のままなので、GitHub など他の処理系でも Ruby として色付けされる
- `invalid` 非対応の旧 bitclust では info string 全体が解釈されず素の `<pre>`
  になる（表示上の劣化のみで情報は失われない）

### 9.4 RRD インデントコードブロック

RRD ではインデントされたテキストが整形済みテキスト（`<pre>`）になる。
Markdown ではバッククォートの個数で元のインデント幅をエンコードする。

``````
N個のバッククォート = 3 + 元のインデント幅

例: 2スペースインデント → 5個のバッククォート
`````
code line 1
code line 2
`````
``````

コードブロック内のベースインデントは除去される。
逆変換時はバッククォートの個数からインデント幅を復元する。

### 9.5 RRD からの変換一覧

| RRD | Markdown |
|-----|----------|
| `#@samplecode ラベル` ... `#@end` | ```` ```ruby title="ラベル" ```` ... ```` ``` ```` |
| `#@samplecode` ... `#@end` | ```` ```ruby ```` ... ```` ``` ```` |
| `//emlist[ラベル][lang]{` ... `//}` | ```` ```lang title="ラベル" ```` ... ```` ``` ```` |
| インデントテキスト（Nスペース） | `(3+N)` 個のバッククォートで囲む |

### 9.6 リスト内のコードブロック（インデントフェンス）

リスト項目や定義リスト（§10.2）の説明の中にコードブロックを置く場合は、
GFM と同じくフェンスを項目のインデントに合わせて書く。
内容と閉じフェンスからはフェンス行のインデント幅までが除去される。
CommonMark と同じく、項目の説明に取り込まれるのはインデントされた
フェンスだけで、カラム0（インデントなし）のフェンスは項目の外の
トップレベルのコードブロックとして扱われる。

````markdown
- **`Dir.glob`**:

  説明文。

  ```ruby
  p Dir.glob(["f*","b*"])  # => ["foo", "bar"]
  ```
````

§9.4 のインデント幅エンコード（行頭の 4 個以上のバッククォート）とは
行頭に空白があるかどうかで区別される。

### 9.7 インラインコード

テキスト行中の `__WORD__` パターン（`__END__`, `__FILE__` 等）は
自動的にコードスパンに変換される。ブラケットリンク内の `__WORD__` は変換しない。

RRD の GNU 風引用 `` `token' ``（rd に code マークアップがなかった時代の
代替記法）はインラインコードスパン `` `token` `` に変換される。
ネイティブ MD 描画（GFM モード）ではこれらが `<code>` として表示される。

上記以外の生のバッククォートは `` \` `` にエスケープされ、
リテラルのバッククォートとして表示される。GNU 風引用でも次の場合は
スパン化せずエスケープで温存する:

- 開き `` ` `` の直前がバックスラッシュ（正規表現特殊変数 `` \` `` 等）
- 中身に空白・バックスラッシュを含む（スパン境界が曖昧になるため）
- TeX 風二重引用 ``` ``text'' ```

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
   - `def ClassName.name` → クラスメソッド / 特異メソッド
   - `def name` → インスタンスメソッド
   - `def name:`（RBS 形式）・`def self.name` は将来対応（§3.2）。
     未実装のため現状はビルドエラーとして拒否される
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
| `[[m:Kernel.#open]]` | `[m:Kernel?.open]` | `.#` → `?.` |
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

## 14. C API リファレンス（refm/capi → manual/capi）

C API リファレンスは api とは別系統（`FunctionReferenceParser`/`FunctionDatabase`）で、
構造は「シグネチャ＋本文」の列のみ。ライブラリ・クラス等のクロスファイル情報が
無いため front matter は使わない。ファイルは `manual/capi/*.md`（1ファイル＝1ソースファイル、
`array.c.md` 等）。

シグネチャは h3 で、**キーワードを付けない**（C のシグネチャは型から始まり自己記述的。
`MACRO`/`static` プレフィクスもそのまま）:

```markdown
### VALUE rb_ary_new()

空の Ruby の配列を作成し返します。

### MACRO type* ALLOC(type)

type 型のメモリを割り当てる。

### static VALUE assign(VALUE self, NODE *lhs)
```

本文の記法（クロスリファレンス・コードブロック・リスト・`#@` 指令）は api と共通。
capi ファイルに本文見出しは存在しないため、`###` の解釈が衝突することはない
（変換は capi モード: `RRDToMarkdown.convert(rrd, capi: true)` /
`MarkdownToRRD.convert(md, capi: true)`）。

ビルドは `bitclust --capi update --markdowntree=manual/capi`。

## 15. 未決事項・今後の検討

### 解決済み

- [x] RD ↔ MD 双方向変換器の実装（826/826 ファイルでロスレスラウンドトリップ達成）
- [x] 定義リストの Markdown 記法（GFM 互換の `` - **`term`**: description `` 形式を採用）
- [x] 複数行にまたがるリスト項目の Markdown 表示品質改善（継続行対応済み）
- [x] `@param`/`@see` 等の継続行が `#@` ディレクティブを挟む場合の対応（ネスト追跡で解決）
- [x] `[c:String]` 等のリンク記法（RRD `[[...]]` ↔ MD `[...]` の双方向変換で解決）
- [x] front matter スキーマの確定（1ファイル1エンティティ、`library` スカラ、共有断片の扱い、front matter 内版分岐。§1）
- [x] `include`/`extend`/`alias` を front matter へ集約する方針の確定（§1.2。変換器実装は未解決へ）
- [x] 本文アンカー `{#id}` の実装（§2.4）— kramdown は不採用となり、bitclust の
  ネイティブ実装で解決。MDCompiler が `### 見出し {#id}` を `<hN id='id'>` に描画し、
  RefsDatabase がアンカーを収集して `[ref:...]` 参照を解決する。本番稼働済み
- [x] 変換器の front matter 対応実装（§1 のとおり実装済み: `include`/`extend`/`alias` の
  front matter 移送（版条件は `#@` 付き）、`#@include` グラフと版ゲートからの
  `library`/`since`/`until` 注入、grouping 用 `#@include` の除去と共有断片の
  拡張子なし正規化、front matter 内 `#@` 出力）
- [x] 新パイプラインのファイル発見（glob + front matter）と孤児検出（§1.1 のとおり
  MarkdownTree として実装済み。孤児・`library` なし・include 欠損はビルド警告）
- [x] `#@include` での RD/MD 混在対応（移行完了により全ツリーが md 化され、
  移行期の混在は解消。共有断片は拡張子なし表記をリゾルバが `.md` に解決する）
- [x] `refe` コマンド等でのプレーンテキスト表示時の可読性確認（2026-07 確認済み。
  `refe`・`bitclust lookup` の表示は RRD 時代から「バージョン解決済みソースを
  そのまま表示」であり、md ソースでも段落・リスト・参照・見出し・`` ```ruby ``
  コード例は RRD ソースと同等以上の可読性。既知の劣化は
  ①インデント幅エンコードの長いフェンス（§9.4）がフェンス行のノイズになる
  （短いブロックが隣接すると顕著）②`- **param**` / `` - **`term`**: `` の装飾記号
  ③`\#` 等のエスケープ残り — いずれも表示側の整形（フェンス→インデント復元等）で
  改善可能なので、refe2 gem の Markdown 対応リリース時に検討する）
- [x] 新システム（bitclust 脱却後）のパーサー実装方針（当面不要と判断 — 2026-07。
  bitclust の Markdown ネイティブ対応で運用できており、記法とビルドは分離済みの
  ため、将来必要になれば記法に影響なくツールを置き換えられる）

- [x] エディタ支援: `#@` 指令用の VS Code TextMate grammar 作成（2026-07 実装済み。
  doctree の `tools/vscode/rurema-markdown/` — Markdown ハイライトへの injection
  grammar として `#@since`/`#@until`/`#@if`/`#@else`/`#@end`/`#@include`/
  `#@samplecode`/`#@todo`/`#@#` を強調。Preprocessor と同じく行頭（カラム0）のみを
  指令とし、既知の指令以外の行頭 `#@` はビルドで parse error になるため
  invalid 表示にしてタイポ検出を兼ねる。manual/ 全ツリーの行頭 `#@` 全行で
  分類を検証済み）

- [x] プリプロセッサがコードブロック内の `#@` を処理する挙動の是非（2026-07 決定:
  **現行どおり処理する**を確定仕様とする。§8.4 に理由とイディオムを明記。
  フェンス内の版分岐が manual/ で 400 行超使用されており、フェンス構造自体が
  ゲートで変わるソースも実在するため、「Markdown パース結果でコードブロック内を
  除外する」方式は処理順序上成立しない）

- [x] RBS 形式シグネチャの実運用テスト（2026-07 検証: 実装（パーサ・描画）が
  未対応であることを確認 — RBS 形式（`def name:`）は誤った名前で DB に入ったのち
  statichtml がクラッシュし、`self.` プレフィクスは `Foo.self` のような誤エントリに
  なる。§3.2 に「将来対応予定・現状未実装」と明記し、未対応形式はパース時に
  明確なビルドエラーで拒否するガードを実装（本番の全 11,902 シグネチャで
  誤検知ゼロを検証済み）。実運用投入は実装対応とあわせて将来判断する）

### 未解決

（なし — 全項目解決済み。RBS 形式の実装対応（§3.2）は需要が生じた時点で再開）
