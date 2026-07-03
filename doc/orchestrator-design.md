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
- **O2（実装済み 2026-07-03）**: ライブラリ概要 .md（grouping include 除去・fragment include 温存・
  散文/メタ保持・`type: library` 付与）。新パイプラインでの二重取り込み回避。実装:
  - `lib/bitclust/include_pruner.rb` — rd→rd の純変換。target の `#@include` 行を除去し、
    空になった版ゲートブロック（`#@else` 両枝空を含む）をブロックごと除去、除去痕の空行を整理。
    末尾の空行は保持（md→rd のメタデータ再生成の空行仕様との整合。除去すると webrick/server.rd 型
    「require 群+空行+include 群」でバイト一致が崩れる）。対応の取れないファイルは無変更。
  - `IncludeGraph#grouping_include_sites` — prune 対象 {ファイル => 記載どおりの target}（64ファイル。
    root 60 + member/fragment 経由 4。fragment include は含まない）
  - `IncludeGraph#library_front_matter_map(scope)` — ライブラリ概要へ {type: library ＋
    LIBRARIES 由来の since/until}。in-scope で効くのは **fiber=until 3.1, set=until 3.2** の2件。
    スコープ外ライブラリ（cmath/scanf/sync/shell 等）は type を付けない（サルベージは別スコープで再実行）
  - `bin/rrd2md --graph` は prune → 変換（member 注入 + library 注入）を行い、`LIBRARIES` 自体は
    変換対象外（役目は front matter 発見に置き換わる）
  - 検証: prune+注入後も **823/828 byte-exact（pruned 基準、既知5件のみ）**、残存 grouping include ゼロ、
    828/828 変換成功、フルスイート green。_builtin.md は「type+category+散文」だけの理想形。
  - 残置（O4 スコープ）: 全体ゲート型ファイル（rss/fiber/set/thread 等）は `#@if`/`#@since`/`#@until` の
    ファイル全体ラップと body 内 category が残る。
- **O3（実装済み 2026-07-03、方針=案B）**: **関係を持つエンティティのみ**分割し、
  「include/extend/alias の記述場所は front matter だけ」という不変条件を全ツリーで成立させる。
  関係を持たない束ね（Errno 152件・エラークラス対等）は分割しない（ユーザー決定。
  全件分割は Errno 爆発と版分岐 H1 の分割不能問題があり、無分割は front matter 一元化の
  利点—汎用MD描画・YAML だけで関係取得・リント可能性—を恒久に薄めるため）。実装:
  - `lib/bitclust/entity_splitter.rb` — ①`resolve_header_gates`: スコープ定数（常真/常偽、
    `#@if(version >= "X")` の常真証明含む）の版ゲートのうち**エンティティ H1 を含むブロック**を
    解決（活き枝のみ残す）。版改名 H1 ペア（thread/Mutex=`Thread::Mutex`⇔`Mutex`、
    Net::HTTPURITooLong 等）がスコープ内の単一 H1 に収束（旧名は活き枝の alias として残る）。
    digest.rd の `#@if` 構造ゲート・syslog.rd の散文+H1 内包ゲートも解決。
    ②`segments`: 深さ0の H1（またはスコープ内ゲート付き H1 ブロック）で分割。
    先頭のライブラリ概要部は name=nil のベースセグメント。③`header_relations?`。
  - `MarkdownOrchestrator#units` — 分割判定=「名前付きセグメント≥2 かつ関係あり」
    （lib+単一エンティティ兼用=pathname 型は分割しない）。member 分割は同ディレクトリ、
    lib のインライン・エンティティ分割は `<libname>/` 配下（root 直下だと複数 lib の
    reopen Kernel 等が衝突するため）＋`library`/版ゲート注入。概要部が無い lib は
    front matter のみの概要ユニットを合成（発見からの消失防止）。
  - reduce にヘッダ正規化を追加: 先頭空行除去・関係行の末尾空白除去・H1〜関係間の空行除去
    （md→rd 再生成形へ正規化）。これで従来の benign 差分5件も解消。
  - `build_header_front_matter` を「#@ブロックごとに単一種」へ一般化
    （gated alias + 素 include の混在: Net::HTTPServerException）。
  - 検証: **1185/1185 units（828ソース、63分割）で byte-exact 100%**、
    出力パス衝突0、**body 関係行 0**（不変条件成立）、フルスイート green。
  - MARKUP_SPEC §1.1/§1.2 改訂済み: 関係なしマルチエンティティ容認＋関係は front matter が
    唯一の記述場所＋違反はビルド警告（リントは新パイプライン実装時）。
- **O4（実装済み 2026-07-03）**: ファイル全体を包む版ゲートの解除 → front matter `since`/`until`。実装:
  - `lib/bitclust/whole_file_gate.rb` — 全体ゲート検出（先頭ゲート＋EOF 閉じ・`#@else` 無し・
    ネスト/samplecode 対応）と `unwrap_for_scope`（スコープ下で常に真 → 単純解除、in-scope の
    since/until → 解除して gate 返却、スコープ外・else 付き・証明不能 `#@if` → 据え置き）。
    実データ22件中17件を解除: 常真 since 14（cmath, _builtin/Encoding 等）+ until 2（fiber=3.1,
    set=3.2、LIBRARIES ゲートと交差マージで単一 `until` に）+ 常真 `#@if` 1（rss、
    `version >= "1.8.2"` 形のみ証明可）。据え置き5 = out-of-scope 4（profile 等）+ else 付き 1（fiddle.rd）。
  - `lib/bitclust/markdown_orchestrator.rb` — **クロスファイル方針の集約点**。
    per-file パイプライン = prune → 全体ゲート解除 → `=class` H1 正規化 → front matter 注入。
    `reduce(relpath, rrd)` が md→rd 検証の期待値（rd 側到達点）を返す。
    bin/rrd2md --graph と tools/md-roundtrip-check.rb --inject は本クラスの薄いラッパーに。
  - `RRDToMarkdown` のメタデータ収集に**空行チェックポイントの部分コミット**を追加:
    メタ後に版分岐つき散文（set.rd/thread.rd）や `#@#` コメント（rss.rd）が続く場合、
    nest==0 の空行までをメタとして確定し残りを body へ。これで category が front matter に昇格
    （スライス4の Type B/`#@#` 据え置きを解消。空行チェックポイントが無い場合は従来どおり据え置き）。
  - 検証: 823/828 byte-exact（reduced 基準・既知5件のみ）、フルスイート green。
    set.md = type+until+category 全て front matter、thread.md/rss.md = category 昇格、
    _builtin/Encoding.md = 正規 H1 + library。

## ファイル発見（実装済み 2026-07-03、MARKUP_SPEC §1.1）

`lib/bitclust/markdown_tree.rb` — 新パイプラインの発見: glob `**/*.md` + front matter +
エンティティ H1（コードフェンス除外）で エンティティ/ライブラリ/断片 に分類。LIBRARIES 不使用。
`#@include` 参照解決（`.rd` → `.md` 補完）。**include 参照され front matter を持たないファイルは
H1 を含んでいても断片**（fiddle の版分岐チェーンは transclusion でエンティティを供給する）。
警告: 孤児・library なし/未知 library のエンティティ・front matter 外の関係・include 先欠損。

検証（`tools/md-tree-check.rb --src` でソースグラフと突き合わせ）:
- **発見ライブラリ集合 = in-scope 371 と完全一致**
- library なしエンティティ 46 = 全て期待バケット（スコープ外メンバー11・スコープ外ライブラリ13・
  ソース孤児22=全行 `#@#` の nodoc ファイル等）、**想定外 0・要対応警告 0**
- 定義重複 5 は全てソース由来の既存特性（Set=builtin 3.2↔set lib 3.2 の版相補、
  webrick/compat の Errno シム×3、WEBrick::HTTPServerError の二重定義）
- 発見で見つけて直したバグ: スコープ外ファイルの分割抑止（library なしエンティティ散乱防止）、
  ディレクトリ移動セグメントの相対 `#@include` 書き換え（cgi/core の util.rd 参照切れ）

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
