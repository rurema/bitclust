# るりま（Ruby リファレンスマニュアル）Markdown 記法移行のご紹介

## るりまとは

[るりま](https://docs.ruby-lang.org/ja/)は、Ruby の日本語リファレンスマニュアルプロジェクトです。
Ruby の組み込みクラスから標準ライブラリまで、すべての API ドキュメントを日本語で提供しています。

現在、ドキュメントは **RD ベースの独自記法（RRD）** で記述されており、
専用のドキュメントシステム [bitclust](https://github.com/rurema/bitclust) で処理・公開しています。

## なぜ Markdown に移行するのか

### 現状の課題

るりまへの貢献に興味を持ってくれた方が最初に直面するのが、**独自記法の壁**です。

```
= class Array < Object
include Enumerable

== Instance Methods

--- each {|item| ... } -> self

各要素に対してブロックを評価します。

@param item ブロック内で使用する変数です。
@raise TypeError 引数が正しくない場合に発生します。

#@samplecode 例
[1, 2, 3].each {|i| puts i }
#@end
```

この記法は Ruby コミュニティ以外では使われておらず、書き方を調べるところから始める必要があります。
エディタのシンタックスハイライトもプレビューもありません。

### Markdown にすると何が変わるか

同じ内容を提案する Markdown 記法で書くとこうなります:

````markdown
# class Array < Object
include Enumerable

## Instance Methods

### def each {|item| ... } -> self

各要素に対してブロックを評価します。

- **param** `item` -- ブロック内で使用する変数です。
- **raise** `TypeError` -- 引数が正しくない場合に発生します。

```ruby title="例"
[1, 2, 3].each {|i| puts i }
```
````

Markdown にすることで、以下のメリットが得られます:

- **すぐに書き始められる** — 多くの開発者が Markdown を日常的に使っている
- **GitHub 上でプレビューできる** — PR を開くだけで整形された表示が確認できる
- **エディタの支援が受けられる** — シンタックスハイライト、リアルタイムプレビュー、リンターが使える
- **AI ツールとの相性がよい** — GitHub Copilot 等がコンテキストを理解しやすい

---

## 記法の概要

### 基本構造: 見出しでドキュメントを組み立てる

```markdown
# class Array < Object        ← クラス定義（h1）
include Enumerable

## Class Methods               ← メソッドカテゴリ（h2）

### def new(size = 0) -> Array ← メソッドシグネチャ（h3 + def）

説明文...

### 補足事項                   ← 本文の小見出し（h3、キーワードなし）
```

`#`（h1）がクラス定義、`##`（h2）がメソッドカテゴリ、`###`（h3）がメソッドや小見出し。
メソッドには `def` キーワードを付けるので、小見出しとの区別は明確です。

### メソッドの種別はキーワードで区別

```markdown
### def each {|item| ... } -> self          ← インスタンスメソッド
### def Array.try_convert(obj) -> Array     ← クラスメソッド
### module_function def open(name) -> IO    ← モジュール関数
### const VERSION -> String                 ← 定数
### gvar $DEBUG -> bool                     ← グローバル変数
```

### パラメータ・例外・関連メソッド

```markdown
- **param** `name` -- パラメータの説明
- **return** -- 返り値の説明
- **raise** `TypeError` -- 例外の説明
- **SEE** [m:Array#map]
```

`@param` のような `@` プレフィクスは使いません。
GitHub の issue/PR 内でユーザーメンションとして誤爆するためです。

### コードブロック

````markdown
```ruby title="フィボナッチ数列"
def fib(n)
  n <= 1 ? n : fib(n - 1) + fib(n - 2)
end
```
````

Ruby コードは `` ```ruby `` で囲みます。`title="..."` でラベルを付けられます。

### クロスリファレンス

```markdown
[c:String]          ← クラス参照
[m:Array#each]      ← メソッド参照
[m:Kernel?.open]    ← モジュール関数参照
[lib:json]          ← ライブラリ参照
[d:spec/m17n]       ← ドキュメント参照
```

るりま独自のリンク記法ですが、Markdown のインライン記法と衝突しないよう設計されています。

### バージョン別の記述（変更なし）

```markdown
#@since 3.1
Ruby 3.1 以降の内容
#@end

#@until 3.0
Ruby 3.0 より前の内容
#@end
```

るりまの特徴的な機能である `#@` プリプロセッサ指令は **そのまま維持** します。
Markdown の `#` 見出しと衝突しない（`#` の直後にスペースがないと見出しにならない）ため、
安全に共存できます。

---

## 移行の進め方

### フェーズ 1: 記法の検証（現在ここ）

```
RRD ドキュメント ─→ [rrd2md] ─→ Markdown ドキュメント
                                       │
                                       ↓
                               [md2rrd 変換レイヤー]
                                       │
                                       ↓
                               既存 bitclust パイプライン
                                       │
                                       ↓
                               docs.ruby-lang.org/ja/
```

- Markdown → RRD の変換レイヤーを構築し、**既存の bitclust 上で**記法を検証
- RRD ↔ Markdown の**双方向変換器**を実装済み
- doctree の全 **826 ファイル**でロスレスラウンドトリップ（RRD → MD → RRD）を達成

### フェーズ 2: Markdown での執筆開始

- doctree リポジトリのドキュメントを Markdown 形式に変換
- 新規ドキュメントは Markdown で執筆
- 変換レイヤー経由で既存の bitclust パイプラインを引き続き使用

### フェーズ 3: 新パイプラインへの移行

- bitclust に依存しない Markdown ネイティブのパイプラインを構築
- 変換レイヤーを不要にする

---

## Before/After の比較

実際のドキュメント（`Comparable#clamp`）で比較してみましょう。

### Before（RRD）

```
#@since 2.4.0
--- clamp(min, max)  -> object
#@since 2.7.0
--- clamp(range)     -> object
#@end

self を範囲内に収めます。

@param min 範囲の下端を表すオブジェクトを指定します。
@param max 範囲の上端を表すオブジェクトを指定します。

#@samplecode 例
12.clamp(0, 100)         #=> 12
523.clamp(0, 100)        #=> 100
-3.123.clamp(0, 100)     #=> 0
#@end
#@end
```

### After（Markdown）

````markdown
#@since 2.4.0
### def clamp(min, max)  -> object
#@since 2.7.0
### def clamp(range)     -> object
#@end

self を範囲内に収めます。

- **param** `min` -- 範囲の下端を表すオブジェクトを指定します。
- **param** `max` -- 範囲の上端を表すオブジェクトを指定します。

```ruby title="例"
12.clamp(0, 100)         #=> 12
523.clamp(0, 100)        #=> 100
-3.123.clamp(0, 100)     #=> 0
```
#@end
````

変化の要点:

| 要素 | RRD | Markdown |
|------|-----|----------|
| メソッド定義 | `---` | `### def` |
| パラメータ | `@param name 説明` | `` - **param** `name` -- 説明 `` |
| コードブロック | `#@samplecode` ... `#@end` | `` ```ruby `` ... `` ``` `` |
| バージョン分岐 | `#@since` / `#@end` | **変更なし** |

---

## よくある質問

### Q: 既存の RRD ドキュメントはどうなりますか？

自動変換器（`rrd2md`）で一括変換できます。全 826 ファイルでロスレス変換を確認済みです。
手作業での書き換えは不要です。

### Q: GFM とどのくらい互換性がありますか？

本文の大部分は標準 GFM です。独自拡張は以下の3点のみです:

1. **クロスリファレンス**: `[m:Array#each]` のようなリンク記法
2. **メソッドシグネチャ**: `### def method(args) -> Type` の `def`/`const`/`gvar` キーワード
3. **プリプロセッサ指令**: `#@since`/`#@until` 等（これは既存の仕組みの維持）

GitHub 上で `.md` ファイルを開けば、リンクの解決を除いて概ね正しく表示されます。

### Q: `@param` を使わないのはなぜですか？

GitHub の issue や PR の本文にドキュメントの一部を貼り付けたとき、
`@param` が `param` というユーザーへのメンション通知として誤検知されるためです。
`- **param**` にすることで、この問題を回避しつつ視認性も向上します。

### Q: Liquid（`{% if %}`）ではなく `#@` 指令を維持するのはなぜですか？

2022-2023 年の前回調査では Liquid への移行も検討されましたが、以下の理由で `#@` を維持します:

- `#@` は CommonMark の見出しと衝突しない（安全に共存できる）
- 既存の前処理パイプラインをそのまま活用できる
- `#@since 3.1` のような記法は簡潔で読みやすい
- 段階的移行において、前処理の仕組みを変えないことでリスクを最小化できる

### Q: 貢献するにはどうすればいいですか？

現在は記法のレビューフェーズです。以下の方法で参加できます:

- **記法の仕様書**: [`MARKUP_SPEC.md`](doc/markdown-samples/MARKUP_SPEC.md) を読んでフィードバックを送る
- **サンプルファイルの確認**: [`doc/markdown-samples/`](doc/markdown-samples/) にある
  実変換結果を確認して、読みやすさや違和感をコメントする
- **Issue/PR での議論**: rurema リポジトリの Issue で議論に参加する

---

## 関連リンク

- [rurema/doctree](https://github.com/rurema/doctree) — ドキュメント本体のリポジトリ
- [rurema/bitclust](https://github.com/rurema/bitclust) — ドキュメント処理システム
- [docs.ruby-lang.org/ja/](https://docs.ruby-lang.org/ja/) — 公開サイト
- [`MARKUP_SPEC.md`](doc/markdown-samples/MARKUP_SPEC.md) — 記法の詳細仕様
