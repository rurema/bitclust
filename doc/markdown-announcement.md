# るりま（Ruby リファレンスマニュアル）Markdown 記法移行のご紹介

> **お知らせ（2026年7月）: 移行は完了し、ドキュメントの編集場所が変わりました**
>
> 今後の編集・新規執筆は doctree の **`manual/` 配下の Markdown ファイル**
> （`manual/{api,doc,capi}/**/*.md`）で行ってください。
> 旧 `refm/` ツリーは凍結されており、編集しても公開サイトには反映されません。
> [docs.ruby-lang.org/ja/](https://docs.ruby-lang.org/ja/) は `manual/` から
> ビルドした HTML を配信しており、各ページの編集リンクも `manual/` の
> `.md` ファイルを指しています。

## るりまとは

[るりま](https://docs.ruby-lang.org/ja/)は、Ruby の日本語リファレンスマニュアルプロジェクトです。
Ruby の組み込みクラスから標準ライブラリまで、すべての API ドキュメントを日本語で提供しています。

ドキュメントは長らく **RD ベースの独自記法（RRD）** で記述されてきましたが、
2026年7月に **GitHub Flavored Markdown（GFM）ベースの記法へ移行しました**。
処理・公開は引き続き専用のドキュメントシステム
[bitclust](https://github.com/rurema/bitclust) が担います。

## なぜ Markdown に移行したのか

### 移行前の課題

るりまへの貢献に興味を持ってくれた方が最初に直面していたのが、**独自記法の壁**です。

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

この記法は Ruby コミュニティ以外では使われておらず、書き方を調べるところから始める必要がありました。
エディタのシンタックスハイライトもプレビューもありません。

### Markdown で何が変わったか

同じ内容を移行後の Markdown 記法で書くとこうなります:

````markdown
---
library: _builtin
include:
  - Enumerable
---
# class Array < Object

## Instance Methods

### def each {|item| ... } -> self

各要素に対してブロックを評価します。

- **param** `item` -- ブロック内で使用する変数です。
- **raise** `TypeError` -- 引数が正しくない場合に発生します。

```ruby title="例"
[1, 2, 3].each {|i| puts i }
```
````

`include Enumerable` のような**関係データは YAML front matter へ**移り、
所属ライブラリ（`library:`）もファイル自身が宣言します。

Markdown にすることで、以下のメリットが得られます:

- **すぐに書き始められる** — 多くの開発者が Markdown を日常的に使っている
- **GitHub 上でプレビューできる** — PR を開くだけで整形された表示が確認できる
- **エディタの支援が受けられる** — シンタックスハイライト、リアルタイムプレビュー、リンターが使える
- **AI ツールとの相性がよい** — GitHub Copilot 等がコンテキストを理解しやすい

---

## 記法の概要

### 基本構造: front matter と見出しでドキュメントを組み立てる

```markdown
---
library: _builtin              ← 所属ライブラリ（front matter）
include:
  - Enumerable                 ← mixin（front matter）
---
# class Array < Object         ← クラス定義（h1）

## Class Methods               ← メソッドカテゴリ（h2）

### def new(size = 0) -> Array ← メソッドシグネチャ（h3 + def）

説明文...

### 補足事項                   ← 本文の小見出し（h3、キーワードなし）
```

`#`（h1）がクラス定義、`##`（h2）がメソッドカテゴリ、`###`（h3）がメソッドや小見出し。
メソッドには `def` キーワードを付けるので、小見出しとの区別は明確です。
構造データ（所属・mixin・バージョンゲート）は front matter に集約され、
ツリーを glob するだけでマニュアル全体の構成が組み上がります
（旧世界の `LIBRARIES` マニフェストは不要になります）。

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

### フェーズ 1: 記法の検証（完了）

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

- RRD ↔ Markdown の**双方向変換器**を実装し、refm の**全3ツリー**
  （api / doc / capi）で検証完了
- ラウンドトリップは **100%**（api 1166 + doc 68 + capi 16 = 1250 ファイル
  全てバイト一致）
- 新旧両経路でフルビルドした**データベースが一致**（9281 メソッドエントリ、
  66 doc ページ、814 C 関数）

### フェーズ 2: bitclust の Markdown ネイティブ化（完了）

```
Markdown ドキュメント ─→ bitclust（ネイティブパース + ネイティブ描画）
                                       │
                                       ↓
                               docs.ruby-lang.org/ja/
```

- bitclust が Markdown を**直接パース・描画**するようになり、
  変換レイヤーはビルド経路から外れました（検証用に残存）
- 描画も Markdown ネイティブになり、**GFM の表現がそのまま HTML に反映**されます
  （インラインコード → `<code>`、GFM テーブル、パラメータ名のコード表示など、
  RRD 時代には表現できなかったマークアップ）
- 旧経路とネイティブ経路で静的 HTML **全 13,535 ページを比較**し、
  差分は GFM による意図した改善と、既知の無害差分1箇所のみ

### フェーズ 3: Markdown での執筆開始（完了 — 2026年7月に本番切替済み）

- doctree に Markdown ツリー `manual/{api,doc,capi}` を追加済み（1250 ファイル）
- ビルドは `bitclust update --markdowntree=manual/api` で md ツリーから直接実行
  （`rake generate` / `rake statichtml` も manual/ から動作）
- [docs.ruby-lang.org/ja/](https://docs.ruby-lang.org/ja/) は manual/ から
  ビルドした HTML を配信中（各ページの編集リンクも manual/ の `.md` を指す）
- **以後の編集・新規執筆は manual/ の Markdown で行います**
- 旧 `refm/` は凍結して共存 → 移行ウィンドウ後に削除予定

### フェーズ 4: 旧バージョンのサルベージ（完了）

旧バージョンの扱いは、性質の違う2つの経路に分かれます。

- **`manual/` に含めるもの（HEAD に残っている範囲）**: `manual/api` を全ビルド
  対象版のスコープ（`--scope 1.8.7,4.2`）で再変換し、HEAD の `refm/` に**なお
  残っている** 3.0 より前のバージョンゲート（`#@since`/`#@until` 等）を
  取りこぼさず含めるようにしました（この再生成で `manual/api` は 1161 → 1166
  ファイル）。これで manual/ から rake の全対象版がビルドできます。ただし
  **HEAD の `refm/` から既に削除済みの、旧バージョン固有の記述までは含みません**
  （るりまは次のバージョンが EOL になった時点で旧版記述の削除を解禁する運用のため）。
- **`manual/` には混ぜないもの（大きく異なる古い版）**: 1.8.7 など、内容が
  現行と大きく分岐していて master への統合が現実的でないバージョンは、当時の
  doctree のスナップショットから復元し、`frozen-<version>` タグ
  （`frozen-1.8.7`〜`frozen-2.7.0`）で固定した**凍結データベース**として扱います。
  これらは manual/ には取り込まず、
  [docs.ruby-lang.org/ja/](https://docs.ruby-lang.org/ja/) の検索に
  1.8.7〜2.7.0 として載せています。復元用の対応表は doctree の
  [`docs/OldVersionArchives.md`](https://github.com/rurema/doctree/blob/master/docs/OldVersionArchives.md)
  にまとめてあります。

### フェーズ 5（将来）: 残タスクと新パイプライン

- bitclust gem のリリース（refe2 などローカルツール向けの Markdown 対応版）
- 旧 `refm/` ツリーの削除（サルベージは完了済みのため、移行ウィンドウ後に実施）
- bitclust に依存しない Markdown ネイティブのパイプラインの構築も
  引き続き視野に入れる（記法とビルドの分離は達成済みのため、
  ツールの置き換えはドキュメントに影響しない）

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

### Q: 既存の RRD ドキュメントはどうなりましたか？

自動変換器（`rrd2md`）による一括変換が完了し、変換結果の doctree
`manual/` ツリーが正式なソースになりました。手作業での書き換えは不要でした。
変換の正しさは、旧ソースと変換結果それぞれからマニュアル全体をビルドして
データベース・HTML を突き合わせる方法で確認済みです。
旧 `refm/` ツリーは移行期間中そのまま残ります（凍結 — 編集しても公開サイトには
反映されません）。移行ウィンドウ後に削除予定です。

### Q: GFM とどのくらい互換性がありますか？

本文の大部分は標準 GFM です。独自拡張は以下の3点のみです:

1. **クロスリファレンス**: `[m:Array#each]` のようなリンク記法
2. **メソッドシグネチャ**: `### def method(args) -> Type` の `def`/`const`/`gvar` キーワード
3. **プリプロセッサ指令**: `#@since`/`#@until` 等（これは既存の仕組みの維持）

front matter は標準的な YAML で、GitHub はメタデータ表として表示します。
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

移行は完了しており、Markdown での編集・執筆をそのまま受け付けています:

- **ドキュメントの編集**: [rurema/doctree](https://github.com/rurema/doctree) の
  `manual/` 配下の `.md` ファイルを編集して PR を送る
  （公開ページ下部の編集リンクから該当ファイルに直接飛べます。
  旧 `refm/` は凍結中なので編集しないでください）
- **記法の確認**: [`MARKUP_SPEC.md`](markdown-samples/MARKUP_SPEC.md) が記法の仕様書です。
  [`doc/markdown-samples/`](markdown-samples/) の実ファイル例も参考になります
- **Issue/PR での議論**: rurema リポジトリの Issue で議論に参加する

---

## 関連リンク

- [rurema/doctree](https://github.com/rurema/doctree) — ドキュメント本体のリポジトリ
- [rurema/bitclust](https://github.com/rurema/bitclust) — ドキュメント処理システム
- [docs.ruby-lang.org/ja/](https://docs.ruby-lang.org/ja/) — 公開サイト
- [`MARKUP_SPEC.md`](markdown-samples/MARKUP_SPEC.md) — 記法の詳細仕様
