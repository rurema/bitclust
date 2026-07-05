# frozen_string_literal: true

require 'test/unit'

require 'bitclust/capi_converter'
require 'bitclust/markdown_to_rrd'

# CapiConverter: refm/capi（C API リファレンス）の md 変換。
# 構造は「--- シグネチャ + 本文」の列のみ（見出し・include・emlist なし、
# library 等のクロスファイル情報も無い）。front matter 不使用。
#
# テストリスト:
# [x] シグネチャ: --- <C sig> ↔ ### <C sig>（def 等のキーワードは付けない）
# [x] MACRO / static プレフィクスも素通し
# [x] 本文の [[f:...]] 参照 ↔ [f:...]
# [x] インデントコード例（api と同じフェンス化）
# [x] #@since/#@until ディレクティブのパススルー
# [x] 定義リスト・ネストリスト（api と同じ変換）
# [x] convert(rrd) を md→rd すると元に戻る（roundtrip）
class TestCapiConverter < Test::Unit::TestCase
  def convert(rrd)
    BitClust::CapiConverter.convert(rrd)
  end

  def roundtrip(rrd)
    BitClust::MarkdownToRRD.convert(convert(rrd), capi: true)
  end

  def test_signature
    assert_equal "### VALUE rb_ary_new()\n\n空の Ruby の配列を作成し返します。\n",
      convert("--- VALUE rb_ary_new()\n\n空の Ruby の配列を作成し返します。\n")
  end

  def test_macro_and_static_signatures
    assert_equal "### MACRO type* ALLOC(type)\n", convert("--- MACRO type* ALLOC(type)\n")
    assert_equal "### static VALUE assign(VALUE self, NODE *lhs)\n",
      convert("--- static VALUE assign(VALUE self, NODE *lhs)\n")
  end

  def test_function_reference
    assert_equal "[f:SPECIAL_CONST_P](obj) が真のとき落ちます。\n",
      convert("[[f:SPECIAL_CONST_P]](obj) が真のとき落ちます。\n")
  end

  def test_indented_code_block
    # フェンス個数はベースインデント幅をエンコードする（3+4=7個。api と同仕様）
    rrd = "使用例\n\n    VALUE ary;\n    ary = rb_ary_new();\n"
    md = convert(rrd)
    assert_match(/^`{7}\nVALUE ary;\nary = rb_ary_new\(\);\n`{7}$/, md)
    assert_equal rrd, roundtrip(rrd)
  end

  def test_directives_pass_through
    rrd = "\#@until 2.2.0\n--- void Check_SafeStr(VALUE v)\n\n古い API です。\n\#@end\n"
    assert_equal "\#@until 2.2.0\n### void Check_SafeStr(VALUE v)\n\n古い API です。\n\#@end\n",
      convert(rrd)
  end

  def test_roundtrip_composite
    rrd = <<~RRD
      --- MACRO int BUILTIN_TYPE(VALUE obj)

      obj の構造体型 ID を返します。
      [[f:SPECIAL_CONST_P]](obj) が真のオブジェクトに対して使うと落ちます。

      : argcが0以上の時
        その関数がとる引数の数を意味します。

        * 必須引数の数 (省略可能な引数があるなら省略不可)
        * 省略可能な引数の数 (ゼロ個ならば省略可)

      --- VALUE rb_ary_new2(long len)

      使用例

          VALUE ary;
          ary = rb_ary_new2(len);
    RRD
    assert_equal rrd, roundtrip(rrd)
  end
end
