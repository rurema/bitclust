# frozen_string_literal: true
require 'test/unit'
require 'bitclust/rbs_overload_matcher'

# RbsOverloadMatcher(RBS シグネチャ表示)。引数パターンごとに説明チャンクが
# 分かれているメソッド(Array.new / Array#[] 等)で、RBS の各オーバーロードを
# 「ブロック有無 → 引数名の一致 → アリティ範囲の重なり」のスコアで最も近い
# チャンクへ振り分ける。RBS の引数名は rdoc の call-seq 由来で rurema の
# 引数名とよく一致するのが根拠。確実な対応が取れない場合は先頭チャンクに
# 寄せる(重複表示はしない)。
#
# オーバーロードは rbs_sig property の JSON をそのまま(文字列キーの Hash)
# 受け取る。チャンクは正規化済みシグネチャ行("--- " 始まり)の配列の配列。
#
# テストリスト:
# [x] チャンクが 1 つなら全オーバーロードをそこへ(スコア不要)
# [x] メタの無いオーバーロード(旧形式・attr・(?))は先頭チャンクへ
# [x] Array#[] 型: 引数名 range / start+length で振り分け・名前が合わない
#     ものはアリティ同点 → 先頭チャンク
# [x] Array.new 型: () はアリティで・(ary) は名前で・ブロック付きは
#     ブロックチャンクへ
# [x] ブロック必須オーバーロードはブロック無しチャンクより有りを選ぶ
# [x] チャンク側の引数解析: 省略可能引数・*rest・キーワード・&block・
#     引数リスト無し
# [x] 解析できないシグネチャ行だけのチャンクには振り分けない
class TestRbsOverloadMatcher < Test::Unit::TestCase
  M = BitClust::RbsOverloadMatcher

  def test_single_chunk_takes_everything
    overloads = [
      {'segments' => [], 'params' => ['x'], 'arity' => [1, 1]},
      {'segments' => [], 'params' => [], 'arity' => [0, 0], 'block' => 'req'},
    ]
    assert_equal [[0, 1]], M.assign(overloads, [['--- foo(x) -> nil']])
  end

  def test_overload_without_meta_goes_to_first_chunk
    overloads = [{'segments' => []}]
    chunks = [['--- foo(x) -> nil'], ['--- foo(x, y) -> nil']]
    assert_equal [[0], []], M.assign(overloads, chunks)
  end

  # Array#[] の実データ(rbs v3.10.0)。(int index) は nth/range どちらとも
  # 名前が合わずアリティも同点 → 先頭の nth チャンクへ。range と
  # start+length は引数名で決まる
  def test_aref_like_assignment
    chunks = [
      ['--- [](nth) -> object | nil'],
      ['--- [](range) -> Array | nil'],
      ['--- [](start, length) -> Array | nil'],
    ]
    overloads = [
      {'segments' => [], 'params' => ['index'], 'arity' => [1, 1]},
      {'segments' => [], 'params' => ['start', 'length'], 'arity' => [2, 2]},
      {'segments' => [], 'params' => ['range'], 'arity' => [1, 1]},
    ]
    assert_equal [[0], [2], [1]], M.assign(overloads, chunks)
  end

  # Array.new の実データ(rbs v3.10.0)。() はアリティ 0 を含む先頭チャンク
  # だけに重なる。(ary) と (size, ?val) は引数名で分かれ、ブロック付きは
  # ブロックチャンクへ
  def test_new_like_assignment
    chunks = [
      ['--- new(size = 0, val = nil) -> Array'],
      ['--- new(ary) -> Array'],
      ['--- new(size) {|index| ... } -> Array'],
    ]
    overloads = [
      {'segments' => [], 'params' => [], 'arity' => [0, 0]},
      {'segments' => [], 'params' => ['ary'], 'arity' => [1, 1]},
      {'segments' => [], 'params' => ['size', 'val'], 'arity' => [1, 2]},
      {'segments' => [], 'params' => ['size'], 'arity' => [1, 1], 'block' => 'req'},
    ]
    assert_equal [[0, 2], [1], [3]], M.assign(overloads, chunks)
  end

  def test_required_block_prefers_block_chunk
    chunks = [
      ['--- each -> Enumerator'],
      ['--- each {|item| ... } -> self'],
    ]
    overloads = [
      {'segments' => [], 'params' => [], 'arity' => [0, 0]},
      {'segments' => [], 'params' => [], 'arity' => [0, 0], 'block' => 'req'},
    ]
    assert_equal [[0], [1]], M.assign(overloads, chunks)
  end

  # 省略可能ブロック(?{ ... })はどちらのチャンクとも矛盾しない。
  # 引数名の一致で決まる
  def test_optional_block_is_neutral
    chunks = [
      ['--- open(path) -> IO'],
      ['--- open(fd) {|io| ... } -> object'],
    ]
    overloads = [
      {'segments' => [], 'params' => ['fd'], 'arity' => [1, 1], 'block' => 'opt'},
    ]
    assert_equal [[], [0]], M.assign(overloads, chunks)
  end

  # チャンク側の引数リスト解析。省略可能引数で最小アリティが下がり、
  # *rest で上限が消え、キーワード名も名前照合に使われる
  def test_chunk_parsing_of_optional_rest_and_keywords
    chunks = [
      ['--- foo(a, b = 1, *rest, key: 0) -> nil'],
      ['--- foo(x, y) -> nil'],
    ]
    overloads = [
      {'segments' => [], 'params' => ['key'], 'arity' => [5, 5]},
      {'segments' => [], 'params' => ['x', 'y'], 'arity' => [2, 2]},
    ]
    assert_equal [[0], [1]], M.assign(overloads, chunks)
  end

  # &block 引数はブロック有りとして扱う
  def test_chunk_block_argument_counts_as_block
    chunks = [
      ['--- foo -> Enumerator'],
      ['--- foo(&block) -> object'],
    ]
    overloads = [
      {'segments' => [], 'params' => [], 'arity' => [0, 0], 'block' => 'req'},
    ]
    assert_equal [[], [0]], M.assign(overloads, chunks)
  end

  # 引数リストの無いシグネチャはアリティ 0 扱い
  def test_chunk_without_params_is_zero_arity
    chunks = [
      ['--- size -> Integer'],
      ['--- size(n) -> Integer'],
    ]
    overloads = [
      {'segments' => [], 'params' => [], 'arity' => [0, 0]},
      {'segments' => [], 'params' => ['n'], 'arity' => [1, 1]},
    ]
    assert_equal [[0], [1]], M.assign(overloads, chunks)
  end

  # 同一チャンクに複数シグネチャ行(別名など)がある場合は特徴を合算する
  def test_multiple_signature_lines_in_one_chunk
    chunks = [
      ['--- collect {|item| ... } -> [object]', '--- map {|item| ... } -> [object]'],
      ['--- collect -> Enumerator', '--- map -> Enumerator'],
    ]
    overloads = [
      {'segments' => [], 'params' => [], 'arity' => [0, 0], 'block' => 'req'},
      {'segments' => [], 'params' => [], 'arity' => [0, 0]},
    ]
    assert_equal [[0], [1]], M.assign(overloads, chunks)
  end

  # 解析できない行だけのチャンクは振り分け先にならない
  def test_unparseable_chunk_is_skipped
    chunks = [
      ['?????'],
      ['--- foo(x) -> nil'],
    ]
    overloads = [
      {'segments' => [], 'params' => [], 'arity' => [0, 0]},
    ]
    assert_equal [[], [0]], M.assign(overloads, chunks)
  end

  def test_empty_chunks_returns_empty
    assert_equal [], M.assign([{'segments' => []}], [])
  end
end
