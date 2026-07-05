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
```

期待値: (1) api 1161/1161・doc 70/70・capi 16/16 byte-exact、
(2) ライブラリ集合一致・要対応警告 0、(3) 全ライブラリ structurally identical、
(4) `DATABASES EQUIVALENT`（末尾空白のみの差分は許容として別掲される）。

## 3. データベース構築（manual/ ツリーから）

`--markdowntree` が md ツリーを一時的に旧形式へブリッジし、既存のビルド機構に渡す。
出てくる DB は従来と同形式なので、以降（statichtml・server・refe）は無変更。

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
