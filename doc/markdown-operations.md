# Markdown 移行の運用コマンド集

Markdown 移行に関わる変換・検証・ビルドのコマンドをまとめる。
記法は [markdown-samples/MARKUP_SPEC.md](markdown-samples/MARKUP_SPEC.md)、
設計は [orchestrator-design.md](orchestrator-design.md) を参照。

前提: コマンドはすべて `bitclust/` リポジトリのルートで実行する。
`<doctree>` は doctree チェックアウトのパス（例: `../doctree`）。

## 1. 変換（refm/*.rd → manual/*.md）

移行時に一度だけ実行し、生成された `manual/` ツリーを doctree にコミットする。
以後の編集は `.md` に対して直接行う（`refm/` は凍結）。

```console
# API リファレンス（オーケストレータ経由: front matter 注入・分割・include 除去）
$ ruby bin/rrd2md --graph <doctree>/refm/api/src <doctree>/manual/api

# 散文ドキュメント（正規化つき変換。孤児ファイルは変換対象外）
$ ruby bin/rrd2md --doc <doctree>/refm/doc <doctree>/manual/doc

# C API リファレンス
$ ruby bin/rrd2md --capi <doctree>/refm/capi/src <doctree>/manual/capi
```

- `--graph` のスコープ（対象版範囲）は `--scope LO,HI` で変更できる（既定 `3.0,4.2`）。
  旧版サルベージ時は同じコマンドを別スコープで再実行する。
- 単一ファイルの変換を確認したいときは `ruby bin/rrd2md --file <path>`（標準出力へ）。

## 2. 検証

変換器やオーケストレータを変更したら、レベルの浅い順に確認する。

```console
# (1) ラウンドトリップ（バイト一致）: rd → md → rd が元に戻るか
#     api はオーケストレータの reduce 基準（--inject）、doc/capi はオプションで追加
$ ruby tools/md-roundtrip-check.rb --inject <doctree>
$ ruby tools/md-roundtrip-check.rb --with-doc --with-capi <doctree>

# (2) ファイル発見: 生成 md ツリーが LIBRARIES なしで自立して構成できるか
#     （孤児・関係リント・ソース側 include グラフとのパリティ）
$ ruby tools/md-tree-check.rb <doctree>/manual/api --src <doctree>/refm/api/src

# (3) パーサ構造: 全ライブラリを旧ソースとブリッジの両方からパースして比較
$ ruby tools/md-bridge-check.rb <doctree>/refm/api/src <doctree>/manual/api --version 3.4

# (4) DB 全内容: 新旧 DB をエントリ単位で比較（§3 で両方をビルドしてから）
$ ruby tools/md-db-check.rb /tmp/db-old /tmp/db-new

# (5) ネイティブ描画（MDCompiler）: 全エントリで RDCompiler と HTML 比較
#     （md source → MDCompiler と rd source → RDCompiler の出力一致）
$ ruby tools/md-compile-check.rb /tmp/db-old
```

期待値: (1) api 1161/1161・doc 70/70・capi 16/16 byte-exact、
(2) ライブラリ集合一致・要対応警告 0、(3) 全ライブラリ structurally identical、
(4) `DATABASES EQUIVALENT`（末尾空白のみ・シグネチャスペースのみの差分は
許容として別掲される）、(5) `HTML EQUIVALENT`（method/doc/lib/function 全件）。

(5) はメモリの少ないマシンでは 1 プロセスで回さず分割する:

```console
$ ruby tools/md-compile-check.rb /tmp/db-old --only methods --shard 0/4  # 1/4 2/4 3/4 も
$ ruby tools/md-compile-check.rb /tmp/db-old --only docs
$ ruby tools/md-compile-check.rb /tmp/db-old --only libs
$ ruby tools/md-compile-check.rb /tmp/db-old --only functions
```

なお (5) が報告する fragment-roundtrip diffs（〜2250）は情報値。DB 内のエントリ
source はファイルレベルの reduce 正規化を経ていないため、断片単体の再変換では
正規化分の差が出る（HTML 等価が本ゲート）。

`--gfm` を付けると M2 GFM モードの整合も同時に検証する（GFM 出力と M1 出力の
差が `<code>`/`<strong>`/GNU 引用の正規化で消えること）。期待値:
`gfm: consistent: <全件>, diffs: 0`。

## 3. データベース構築（manual/ ツリーから）

`--markdowntree` は md ツリーを**ネイティブにパース**して DB を構築する
（M3。DB には md ソースがそのまま入り、描画は MDCompiler の GFM モードが
自動選択される）。DB の形式・置き場所は従来と同じなので、以降のコマンド
（statichtml・server・refe）は無変更。

旧ブリッジ経路（md→rd 変換して既存機構に渡す）は `BITCLUST_MD_BRIDGE=1` で
利用できる。**ブリッジは検証用に温存中**: markdown-findings.md の
フォローアップと旧バージョン（< 3.0）サルベージが完了してから削除する予定
（2026-07-07 決定）。

```console
# 初期化（従来どおり）
$ bitclust --database=/tmp/db-3.4 init version=3.4 encoding=UTF-8

# Ruby API（manual/api の隣に manual/doc があれば散文ページも自動で取り込む）
$ bitclust --database=/tmp/db-3.4 update --markdowntree=<doctree>/manual/api

# C API
$ bitclust --database=/tmp/db-3.4 --capi update --markdowntree=<doctree>/manual/capi
```

従来の rd ツリーからのビルド（凍結 `refm/` の再現・比較用）:

```console
$ bitclust --database=/tmp/db-old update --stdlibtree=<doctree>/refm/api/src
$ bitclust --database=/tmp/db-old --capi update <doctree>/refm/capi/src/*
```

## 4. 静的 HTML 生成

DB 構築後は従来と同一（doctree の `rake statichtml:3.4` が実行しているものと同じ）:

```console
$ bitclust --database=/tmp/db-3.4 statichtml \
    --outputdir=/tmp/html/3.4 \
    --templatedir=<bitclust>/data/bitclust/template.offline \
    --catalog=<bitclust>/data/bitclust/catalog \
    --fs-casesensitive \
    --canonical-base-url=https://docs.ruby-lang.org/ja/latest/
```

**実機確認済み（2026-07、version 3.4、api+doc+capi）**: 旧経路 DB と md 経路 DB から
生成した HTML 13,540 ファイルを `diff -r` で比較し、差分は 1 ファイル・1 箇所のみ
（`JSON::State#generate` の meta description 属性内の改行1個）。これは旧経路の
アーティファクト由来: includer（json.rd）で最後の `#@include` の後にあった空行が、
include 展開時に被 include ファイル末尾エントリの source へ漏れ込んでいた
（DB 比較の「末尾空白のみ」25件と同根）。md 経路の方がクリーンで、HTML 属性内の
空白は正規化されるため表示・意味とも等価。既知の無害差分として受容する。

**ネイティブ描画（M3、GFM 既定）でも確認済み（2026-07）**: 旧経路（refm → 旧DB →
RDCompiler）とネイティブ経路（manual/ → md DB → MDCompiler GFM）の statichtml
13,535 ファイルを GFM 差分（コードスパン `<code>`・GFM テーブル・太字番号等の意図した
拡張）を正規化した上で比較し、残差は上記 `JSON::State#generate` の1件のみ。

## 5. doctree の Rakefile を切り替える場合の対応表

| 従来（refm） | 移行後（manual） |
|--------------|------------------|
| `bitclust update --stdlibtree=refm/api/src` | `bitclust update --markdowntree=manual/api` |
| `bitclust --capi update refm/capi/src/*` | `bitclust --capi update --markdowntree=manual/capi` |
| （doc は stdlibtree から自動） | （manual/doc から自動。manual/api の隣に置く） |
| `bitclust statichtml ...` | 変更なし |

## 6. トラブルシューティング

- **`#@include'ed file not exist`**: md 側の `#@include` ターゲットが解決できていない。
  `tools/md-tree-check.rb` の `include target not found` 警告で場所を特定する。
- **`relations in body` 警告**: include/extend/alias が front matter ではなく本文に
  書かれている。関係を持つエンティティは単独ファイルに分割する（MARKUP_SPEC §1.1）。
- **孤児警告（orphan file）**: エンティティ H1 も `type: library` も持たず、どこからも
  `#@include` されていないファイル。H1 の書き忘れか、消し忘れの断片。
- 一時ブリッジの中身を見たいとき: `BitClust::MarkdownBridge.build(md_root, out_dir)` を
  irb 等から直接呼ぶと任意のディレクトリに旧形式ツリーを書き出せる。
