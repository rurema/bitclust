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
| in-scope メンバーファイル | **349**（O1実装で確定。初期プロトタイプの 353 は LIBRARIES 内ゲート未適用の過大計上。scanf×2 + sync×2 は LIBRARIES で `#@until 2.7.0` に包まれており正しくは out-of-scope） |
| **多重所属** | **0** → `library` はスカラ確定 |
| in-scope で効く構造 `since`/`until` | **4件**（`_builtin/Data`=3.2, `_builtin/Refinement`=3.1, `_builtin/Set`=3.2, `ractor/Port`=4.0、全て `since`） |
| grouping include（対象=エンティティ） | 384 |
| fragment include（対象=断片） | 61 |
| 単一エンティティ・メンバー | 290 |
| マルチエンティティ・メンバー | 94（`_builtin/SystemCallError`=152 Errno, `net/Net__HTTPResponse`=72 等） |
| grouping ファイル（reachable 総数） | 360（out-of-scope 11: Bignum/Fixnum/Data.old/Base64__Deprecated/minitest×3/scanf×2/sync×2） |
| fragment ファイル | 49 |
| in-scope で `#@if` 条件つき | 20（全て rss、条件は `(version >= "1.8.2")` の1種のみ = スコープ内で常に真 → 制約なし扱いで正しい） |

O1 実装時の発見（初期プロトタイプに無かった要対応点）:
- **LIBRARIES 自体に版ゲートがある**（cmath/scanf/sync = `#@until 2.7.0`）。ライブラリのゲートは
  そのメンバー全員の条件に前置する。
- **`#@samplecode` も `#@end` で閉じる**ため、`#@samplecode` もブロックとして
  スタックに積まないと pop の対応がずれて版条件スタックが壊れる。
- LIBRARIES には `#@#` コメント行（json/add/rails.rd）と重複エントリ（webrick/httputils）がある。

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

（このロジックは `lib/bitclust/include_graph.rb` として実装済み。テストは
`test/test_include_graph.rb`、実データ検証は `tools/md-roundtrip-check.rb --inject`。）

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

- **O1（実装済み 2026-07-03）**: グラフ解析器 + 各メンバーへ `library`(スカラ)・構造 `since`/`until` を注入 →
  メンバー .md 出力。実装:
  - `lib/bitclust/include_graph.rb` — `IncludeGraph`（faithful 解析）+ `Scope`（範囲パラメータ化）+
    `front_matter_map(scope)`（注入値の計算。多重所属は警告スキップ、同一ライブラリ複数サイトは区間 hull）
  - `RRDToMarkdown` に `extra_front_matter:`（type/library/since/until、§1.7 順で emit、
    since/until は常にクォート）。`MarkdownToRRD` は注入キーを無視するので md→rd で元 RRD が復元される
  - `bin/rrd2md --graph [--scope LO,HI]` — バッチ変換に注入を配線
  - `tools/md-roundtrip-check.rb [--inject]` — ラウンドトリップ検証（都度 /tmp に再作成していたものを恒久化）
  - 検証: 全 828 ファイル中 823 byte-exact（残5は既知の空白差のみ・注入の有無で不変）、
    in-scope 349 メンバー注入、フルテストスイート green。
- **O2**: 索引 → ライブラリ概要 .md（grouping include 除去・fragment include 温存・散文/メタ保持）。
  新パイプラインでの二重取り込み回避に必要。
- **O3**: マルチエンティティ分割（必要な範囲のみ。Errno 等はまとめ据え置き）。
- **O4**: Type B ファイル全体ゲート（cmath/set/rss/rubygems/profile(r)/rdoc.rd/irb.slex の8件）→
  ライブラリ `since`/`until`。

## スコープの決定（2026-07-03）

**「旧版サルベージを見据えた設計」で確定**（ユーザー決定）。実装は次の分離で両立する:

- **解析層（`IncludeGraph`）は faithful**: 全版のゲート・全所属を生のまま収集する。
  `Membership#conditions` は LIBRARIES ゲート＋include 経路の条件スタックのスナップショットで、
  スコープを適用しない。旧版専用の所属（thread/rdoc の `#@else` 枝等）もデータとして保持される。
- **出力層（`Scope` + `front_matter_map`）だけがスコープを適用**: 範囲 [lo, hi) はパラメータで、
  現行は [3.0, 4.2)。in-scope はクリーン（0多重・4ゲート）なので出力は (A) 案どおり
  「スカラ `library` + 4件の `since`」になる。
- **サルベージ時は同じ解析結果に別スコープを渡すだけ**（`bin/rrd2md --scope LO,HI`）。
  版分裂所属（~23件）の front matter 表現（§1.6 の `library` 内 `#@`）が必要になったら
  出力層の拡張のみで対応でき、解析層・記法は変わらない。
