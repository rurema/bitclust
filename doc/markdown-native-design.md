# ネイティブ MD パース設計（フェーズ3 M3）

M3 のゴール: ブリッジ（md→rd 変換して既存機構に渡す）を廃止し、
md ツリーを直接パースして DB を構築、描画は MDCompiler（GFM モード）を
既定にする。エントリの `source` には md 断片がそのまま入る。

**ステータス（2026-07-07）: 達成。** `--markdowntree` はネイティブパースが
既定（`BITCLUST_MD_BRIDGE=1` で旧ブリッジ経路）、描画は screen/statichtml/
lookup とも MDCompiler（GFM）へ配線済み。下記 M3 ゲートは 1〜3 全通過、
4 の statichtml 実機比較は 13,535 ページ中、残差は既知の無害差分1件のみ
（`JSON::State#generate`、markdown-operations.md §4）。移行順序 1〜5 完了、
6（ブリッジ廃止）のみ判断待ち（roundtrip 検証用に温存する選択肢を含む）。

## 戦略

MDCompiler（RDCompiler のサブクラスで行ディスパッチのみ差し替え、M1 で
全量等価を証明済み）と同じパターンを RRDParser に適用する:

- **MDParser < RRDParser**: 行ディスパッチだけ md 記法に差し替える
  - `= class X < Y` → `# class X < Y`（H1）
  - `== Class Methods` 等 → `## Class Methods`（レベル2ヘッダ、名称は同一）
  - `--- sig` → `### def sig` / `### module_function def` / `### const` / `### gvar`
    （キーワードを剥がして既存の Signature パースに渡す）
  - `category`/`require`/`sublibrary` ヘッダ行 → front matter
    （`type: library` / `category:` / `require:` / `sublibrary:`）
  - `include`/`extend`/`alias` ヘッダ行 → front matter（案B: 関係は front matter のみ）
  - `library.source` / `klass.source` / チャンク src → **md のまま**格納
- **Preprocessor は無変更**: `#@since`/`#@until`/`#@include` 等は md でも
  同一記法なので、`Preprocessor.wrap` をファイル先頭からそのまま通す。
  front matter 内の `#@` 行も先に版解決される（ブリッジが rd ヘッダを
  再生成していたのと同じ意味論）
- **複数ファイルの組み立て**: 旧来は lib.rd の `#@include` 展開で
  1 ストリームに繋いでいたが、md では front matter の `library:` が
  所属を表す。update フローが MarkdownTree の発見結果を使い、
  ライブラリごとに「lib ファイル → メンバーファイル（reopen/redefine 後置）」の
  順で MDParser を呼ぶ。`Context` は同じ libname で呼べば同一 Library に
  追記されるため、ファイル単位のパースで自然に合流する
- **メンバーゲート**: front matter の `since:`/`until:` を版と比較して
  ファイル単位でスキップ（ブリッジのゲートラッパーと同じ意味論）

## 描画の配線

- DB プロパティ `source_format=markdown` を native update 時に設定
- screen.rb / lookup_command の `RDCompiler.new` を「DB が markdown なら
  `MDCompiler.new(..., gfm: true)`」に切り替えるヘルパへ集約
- `source_location` は manual/ の実パスを直接指せる（remap 不要になる）

## 検証（M3 ゲート）

1. **構造等価**: native DB とブリッジ DB で library/class/entry 集合・
   属性が一致（新ツール md-parse-check）
2. **ソース対応**: native の entry.source（md）を `MarkdownToRRD.convert`
   すると bridge DB の entry.source（rd）に一致
3. **HTML 等価**: native DB + MDCompiler（M1 モード）＝ bridge DB +
   RDCompiler がバイト一致。GFM モードの差は --gfm 正規化で消える
   （M2 で証明済みの性質を DB パース経路でも維持）
4. statichtml 実機比較

## 移行順序

1. MDParser 単体（エンティティ/ライブラリファイルのパース）— TDD
2. update フロー（MarkdownTree 駆動のライブラリ組み立て）+ md-parse-check
3. doc ページの native 格納（md source の DocEntry）
4. capi の native パース
5. 描画配線 + statichtml 比較
6. ブリッジ廃止（bridge は roundtrip 検証用に温存も可）
