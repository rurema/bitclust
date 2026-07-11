# BitClust

BitClust は Ruby リファレンスマニュアル(通称「るりま」)のドキュメント処理
フレームワークです。ドキュメントソース([rurema/doctree](https://github.com/rurema/doctree))を
パースしてデータベース化し、HTML(静的サイト・HTTP サーバ)、CHM、EPUB などに
変換します。生成されたマニュアルは https://docs.ruby-lang.org/ja/ で公開されています。

## ドキュメント

- [doc/usage.md](doc/usage.md) — インストール方法と各サブコマンドの使い方
- [doctree の docs/](https://github.com/rurema/doctree/tree/master/docs) — るりまプロジェクト全体の文書
  (ドキュメントの書き方・ビルド方法・チュートリアルなど)

## 開発を始める

```console
$ git clone https://github.com/rurema/bitclust.git
$ cd bitclust
$ bundle install
```

### テスト

```console
$ bundle exec rake test        # 全テスト(デフォルトタスク)
$ ruby test/test_rdcompiler.rb # 単一のテストファイル
```

### 型定義

RBS 型定義が `sig/` にあります。

```console
$ bundle exec rake sig     # 型定義の再生成
$ bundle exec steep check  # 型検査
```

### doctree と組み合わせて動作確認する

ドキュメント本体のビルドは doctree 側の Rake タスクから行います。
doctree の `Gemfile` は環境変数 `BITCLUST_PATH` でローカルの bitclust を
参照できるので、手元の変更を反映したマニュアルを生成して確認できます。

```console
$ git clone https://github.com/rurema/doctree.git
$ cd doctree
$ bundle install                     # ../bitclust があればそれを使う
$ bundle exec rake generate:3.4      # データベース生成
$ bundle exec rake statichtml:3.4    # 静的 HTML 生成
```

詳細は [doctree の docs/](https://github.com/rurema/doctree/tree/master/docs) を
参照してください。

## 用語集

- **entry** — ドキュメント化の対象。クラス: `Entry` `LibraryEntry` `ClassEntry` `MethodEntry` `DocEntry` `FunctionEntry`
- **screen** — ビュークラス。BitClust server、`statichtml`、`chm` サブコマンドなどが使う
- **singleton object** — `ARGF` や `main` など
- **BitClust server** — ブラウザでリファレンスを見るための HTTP サーバ(`bitclust server`)
- **Refe server** — `refe --server` で起動する DRb サーバ。BitClust DB を DRuby で公開する

## ライセンス

Ruby License
