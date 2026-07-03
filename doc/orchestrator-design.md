# クロスファイル・オーケストレータ設計（Markdown 移行 項目1）

単一ファイル変換器（`RRDToMarkdown` / `MarkdownToRRD`）では扱えない、
ツリー横断の front matter（`library` 所属・構造的 `since`/`until`）を付与するための
オーケストレータの設計。MARKUP_SPEC §14 の残タスクのうち「クロスファイル」に対応する。

## 前提（完了済み）

単一ファイル変換器の front matter 対応はスライス1〜4で完了（branch `feature/markdown-conversion`）:
- スライス1: `include`/`extend`/`alias` を front matter へ（単一エンティティのみ）
- スライス2: 版条件つきヘッダ関係（`#@`）を front matter 内 `#@` で表現
- スライス4: 版条件つきライブラリメタ（require/sublibrary）を front matter へ

api/src 824/829 byte-exact（残差は空行/末尾空白のみ＝意味的同一）。

## 実データ接地（doctree master, in-scope [3.0, 4.1]）

| 項目 | 値 |
|------|-----|
| in-scope エンティティ | 353 |
| **多重所属** | **0** → `library` はスカラ確定 |
| in-scope で効く構造 `since`/`until` | **4件**（`_builtin/Data`=3.2, `_builtin/Refinement`=3.1, `_builtin/Set`=3.2, `ractor/Port`=4.0、全て `since`） |
| grouping include（対象=エンティティ） | 384 |
| fragment include（対象=断片） | 61 |
| 単一エンティティ・メンバー | 290 |
| マルチエンティティ・メンバー | 94（`_builtin/SystemCallError`=152 Errno, `net/Net__HTTPResponse`=72 等） |

### 決定的な知見

1. **所属はディレクトリでなく include グラフから求める**。26件がディレクトリと不一致
   （例: `ractor/Port`→`_builtin`, `ractor/MovedObject`→`_builtin`, `_builtin/Continuation`→`continuation`）。
2. **`#@else` の反転が必須**。thread（<2.3）/rdoc（<1.9.2）の「旧独立ライブラリ→組込み/サブライブラリ」への
   移行は `#@else` 枝にある。反転しないと `since` を `until` と誤認し、偽の多重所属になる。
   正しく扱うと **in-scope 多重所属は 0**。
3. **マルチエンティティ・ファイルでも `library` 注入は曖昧でない**。1ファイル=1ライブラリ所属で、
   ファイル内の全エンティティが同一 `library`。→ **分割は library 注入に不要**。
   分割は別concern（Errno 152件のように「まとめて1ファイル」が自然なものは無理に割らない）。

## include グラフ解析ロジック（核心・要移植）

`#@include(target)` は **includ元ファイルのディレクトリ相対**で解決（Preprocessor 準拠、
`basedir/target` → 無ければ `basedir/target.rd`）。偽の `#@since` 枝内の include は展開されない。

版ゲート付き走査:
- スタックに `[:since, v]` / `[:until, v]` / `[:if, nil]` を積む（`#@since`/`#@until`/`#@if`）。
- **`#@else` で最内条件を反転**（`:since`↔`:until` を同じ version で入れ替え）。
- `#@end` で pop。
- 各 `#@include` 時点のスタックのスナップショットが、そのメンバーの版ゲート。

in-scope 判定（[3.0, 4.2) と重なるか）:
```
interval(stack) = [lo, hi)   # lo=max(since 群), hi=min(until 群), hi=nil は無限
in_scope?      = lo < 4.2 && (hi.nil? || hi > 3.0)
scoped_gate    = [ (lo>3.0 ? lo : nil), (hi && hi<4.2 ? hi : nil) ]  # front matter に書く since/until
```

分類: include 対象ファイルの最初の非空・非`#@`行が `= (class|module|object|reopen|redefine)`
なら **grouping**（実体）、そうでなければ **fragment**（断片・transclusion 用に温存）。

（プロトタイプ解析スクリプトは作業時 `/tmp/claude/graph3.rb` にあった。環境リセットで消えるため
上記ロジックから再構成すること。）

## アーキテクチャ

```
LIBRARIES → roots（各 <lib>.rd）
   │  include グラフを版ゲート付きで走査（#@else 反転, in-scope フィルタ）
   ▼
[グラフ解析]  ファイル分類（grouping/fragment）、各メンバーの library(スカラ)・構造 since/until を確定
   ▼
[変換 + 注入]  メンバー : rd→md（スライス1-4）に library/since/until を front matter 注入
              索引    : ライブラリ概要 md（category/require + 散文、grouping include 除去）
              断片    : そのまま .md
   ▼
出力ツリー  refm/api/md/**/*.md
```

注入は `RRDToMarkdown` に `extra_front_matter:`(library/since/until) を渡す口を足し、
`emit_front_matter` の既存の順序スロット（library→include/extend/alias→since/until→category…）に
載せるだけ。**単一ファイル変換器の記法ロジックは不変**、オーケストレータが横断情報を計算して渡す。

## 段階実装案

- **O1（最初に作る）**: グラフ解析器 + 各メンバーへ `library`(スカラ)・構造 `since`/`until` を注入 →
  メンバー .md 出力。353メンバーの中核価値。TDD: グラフ解析の単体（#@else 反転・in-scope・パス解決・
  grouping/fragment 分類）、数ファイルの注入結果、全体の library 一意性検証。
- **O2**: 索引 → ライブラリ概要 .md（grouping include 除去・fragment include 温存・散文/メタ保持）。
  新パイプラインでの二重取り込み回避に必要。
- **O3**: マルチエンティティ分割（必要な範囲のみ。Errno 等はまとめ据え置き）。
- **O4**: Type B ファイル全体ゲート（cmath/set/rss/rubygems/profile(r)/rdoc.rd/irb.slex の8件）→
  ライブラリ `since`/`until`。

## 未決の論点（次セッションで最初に決める）

**スコープの faithfulness — (A)/(B) いずれか:**

- **(A) [3.0,4.1] にスコープ（推奨）**: in-scope が完全にクリーン（0多重・4ゲート）で設計が単純。
  out-of-scope 専用エンティティ（`Bignum`=`until 2.4`等、現 master でも 3.0+ ビルドに出ない dead content）と、
  版分裂所属（thread/rdoc の <2.3/<1.9.2 分、~23件）は**別トラック（旧版サルベージ）**へ。
- **(B) 完全 faithful（全版）**: 生ゲートを全保持し、~23件の版分裂所属を `library` 内 `#@`
  （§1.6、スカラ重複キーの粗さあり）で表現。lossless だが ~23 の特殊処理が要る。

**推奨は (A)**: 現 doctree master 自体が 3.0+ しかビルドせず out-of-scope は既に非表示、
in-scope が0多重・4ゲートで極めてクリーン、「旧版はサルベージ込みで別」の既合意方針と一致するため。
(A) なら O1 は「スカラ library + 4件の since 注入」で素直に始められる。
