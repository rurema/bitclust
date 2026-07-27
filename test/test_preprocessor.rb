require 'test/unit'
require 'bitclust/preprocessor'
require 'stringio'
require 'tmpdir'

class TestPreprocessor < Test::Unit::TestCase
  include BitClust
  def test_eval_cond
    params = { 'version' => '1.8.7' }

    [
     ['#@if( version > "1.8.0")',  true ],
     ['#@if( version < "1.8.0")',  false],
     ['#@if( version <= "1.8.7")', true ],
     ['#@if( version >= "1.9.1")', false],
     ['#@if( version == "1.8.7")', true ],
     ['#@if( version != "1.9.0")', true ],
     ['#@if( "1.9.0" != version)', true ],

     ['#@since 1.8.0', true ],
     ['#@since 1.8.7', true ],
     ['#@until 1.8.7', false],
     ['#@until 1.9.0', true ],

     ['#@if( version > "1.8.0" and version < "1.9.0")', true ],
     ['#@if( version > "1.8.9" and version < "1.9.0")', false],
     ['#@if( version > "1.8.9" or version < "1.9.0")',  true ],
     ['#@if( version < "1.8.0" or version > "1.9.0")',  false],
     ['#@if( version > "1.8.0" and version < "1.9.0" and version < "1.9.1")', true ],
     ['#@if( version > "1.8.0" and version < "1.9.0" and version > "1.9.1")', false],
     ['#@if( version < "1.8.0" and version > "1.9.0" or "1.9.1" != version)', true ],
    ].each{|cond, expected_result|
      s = <<HERE
#{cond}
a
\#@else
b
\#@end
HERE
      ret = Preprocessor.wrap(StringIO.new(s), params).to_a
      if expected_result
        assert_equal(["a\n"], ret)
      else
        assert_equal(["b\n"], ret)
      end
    }
  end

  def test_todo
    params = { 'version' => '1.8.7' }
    src = <<HERE
--- puts(str) -> String
\#@todo
description
HERE
    expected = <<HERE
--- puts(str) -> String
@todo
description
HERE
    ret = Preprocessor.wrap(StringIO.new(src), params).to_a
    assert_equal(expected, ret.join)
  end

  def test_todo_with_condition
    params = { 'version' => '1.9.2' }
    src = <<HERE
--- puts(str) -> String
\#@since 1.9.2
\#@todo 1.9.2
\#@else
\#@todo old
\#@end
description
HERE
    expected = <<HERE
--- puts(str) -> String
@todo 1.9.2
description
HERE
    ret = Preprocessor.wrap(StringIO.new(src), params).to_a
    assert_equal(expected, ret.join)
  end

  def test_complex_condition
    params = { 'version' => '2.4.0' }
    src = <<HERE
\#@until 1.9.2
before 1.9.2
\#@until 1.8.6
before 1.8.6
\#@end
\#@until 1.9.1
before 1.9.1
\#@end
\#@until 1.9.1
before 1.9.1
\#@end
\#@since 1.9.1
after 1.9.1
\#@end
\#@else
Display here!
\#@end
HERE
    expected = <<HERE
Display here!
HERE
    ret = Preprocessor.wrap(StringIO.new(src), params).to_a
    assert_equal(expected, ret.join)
  end

  def test_nested_condition
    params = { 'version' => '2.4.0' }
    src = <<~'HERE'
      #@until 2.4.0
      #@since 1.8.7
      #@since 1.9.3
      #@since 2.0.0
      Not display here!
      #@end
      #@end
      #@end
      #@end
      Display here!
    HERE
    expected = <<~HERE
      Display here!
    HERE
    ret = Preprocessor.wrap(StringIO.new(src), params).to_a
    assert_equal(expected, ret.join)
  end

  sub_test_case("samplecode") do

    def test_samplecode
      params = { 'version' => '1.9.2' }
      src = <<HERE
--- puts(str) -> String

xxx

\#@samplecode description
puts("xxx")
puts("yyy")
\#@end
HERE

      expected = <<HERE
--- puts(str) -> String

xxx

//emlist[description][ruby]{
puts("xxx")
puts("yyy")
//}
HERE
      ret = Preprocessor.wrap(StringIO.new(src), params).to_a
      assert_equal(expected, ret.join)
    end

    def test_samplecode_without_description
      params = { 'version' => '1.9.2' }
      src = <<HERE
--- puts(str) -> String

xxx

\#@samplecode
puts("xxx")
puts("yyy")
\#@end
HERE

      expected = <<HERE
--- puts(str) -> String

xxx

//emlist[][ruby]{
puts("xxx")
puts("yyy")
//}
HERE
      ret = Preprocessor.wrap(StringIO.new(src), params).to_a
      assert_equal(expected, ret.join)
    end

    def test_samplecode_with_condition1
      params = { 'version' => '1.9.2' }
      src = <<HERE
--- puts(str) -> String

xxx

\#@since 1.9.2
\#@samplecode description1
puts("xxx1")
puts("yyy1")
\#@end
\#@else
\#@samplecode description2
puts("xxx2")
puts("yyy2")
\#@end
\#@end
HERE

      expected = <<HERE
--- puts(str) -> String

xxx

//emlist[description1][ruby]{
puts("xxx1")
puts("yyy1")
//}
HERE
      ret = Preprocessor.wrap(StringIO.new(src), params).to_a
      assert_equal(expected, ret.join)
    end

    def test_samplecode_with_condition2
      params = { 'version' => '1.9.2' }
      src = <<HERE
--- puts(str) -> String

xxx

\#@samplecode description
\#@since 1.9.2
puts("xxx")
\#@else
puts("yyy")
\#@end
\#@end
HERE

      expected = <<HERE
--- puts(str) -> String

xxx

//emlist[description][ruby]{
puts("xxx")
//}
HERE
      ret = Preprocessor.wrap(StringIO.new(src), params).to_a
      assert_equal(expected, ret.join)
    end

    def test_samplecode_with_condition3
      params = { 'version' => '1.9.2' }
      src = <<HERE
--- puts(str) -> String

xxx

\#@since 1.9.1
\#@samplecode description
\#@since 1.9.2
puts("xxx")
\#@else
puts("yyy")
\#@end
\#@end
\#@else
zzz
\#@end
HERE

      expected = <<HERE
--- puts(str) -> String

xxx

//emlist[description][ruby]{
puts("xxx")
//}
HERE
      ret = Preprocessor.wrap(StringIO.new(src), params).to_a
      assert_equal(expected, ret.join)
    end

    def test_samplecode_with_condition4
      params = { 'version' => '1.9.2' }
      src = <<HERE
--- puts(str) -> String

xxx

\#@samplecode description
puts("xxx")
puts("yyy")
\#@since 1.9.2
puts("zzz")
\#@end
\#@end
HERE

      expected = <<HERE
--- puts(str) -> String

xxx

//emlist[description][ruby]{
puts("xxx")
puts("yyy")
puts("zzz")
//}
HERE
      ret = Preprocessor.wrap(StringIO.new(src), params).to_a
      assert_equal(expected, ret.join)
    end
  end

  # bitclust#285: GitHub が #@since 等をユーザー mention として解釈してしまう
  # 問題への対応で、@ を含まない新 prefix #% を導入する。旧 #@ も凍結タグの
  # 旧ソース再取込のため引き続き受け付ける(両対応)
  sub_test_case("percent prefix (#285)") do

    def test_percent_eval_cond
      params = { 'version' => '1.8.7' }

      [
       ['#%if( version > "1.8.0")',  true ],
       ['#%if( version < "1.8.0")',  false],
       ['#%since 1.8.0', true ],
       ['#%since 1.8.7', true ],
       ['#%until 1.8.7', false],
       ['#%until 1.9.0', true ],
      ].each{|cond, expected_result|
        s = <<HERE
#{cond}
a
#%else
b
#%end
HERE
        ret = Preprocessor.wrap(StringIO.new(s), params).to_a
        if expected_result
          assert_equal(["a\n"], ret)
        else
          assert_equal(["b\n"], ret)
        end
      }
    end

    def test_percent_comment
      params = { 'version' => '1.8.7' }
      src = <<HERE
a
#%# preprocessor comment
b
HERE
      ret = Preprocessor.wrap(StringIO.new(src), params).to_a
      assert_equal(["a\n", "b\n"], ret)
    end

    def test_percent_todo_normalized
      params = { 'version' => '1.8.7' }
      src = <<HERE
--- puts(str) -> String
#%todo
description
HERE
      expected = <<HERE
--- puts(str) -> String
@todo
description
HERE
      ret = Preprocessor.wrap(StringIO.new(src), params).to_a
      assert_equal(expected, ret.join)
    end

    def test_percent_samplecode
      params = { 'version' => '1.9.2' }
      src = <<HERE
#%samplecode description
puts("xxx")
#%since 1.9.2
puts("zzz")
#%end
#%end
HERE
      expected = <<HERE
//emlist[description][ruby]{
puts("xxx")
puts("zzz")
//}
HERE
      ret = Preprocessor.wrap(StringIO.new(src), params).to_a
      assert_equal(expected, ret.join)
    end

    def test_mixed_prefixes
      # 移行期は同一ファイル内で新旧 prefix が混在しうる
      params = { 'version' => '2.0.0' }
      src = <<HERE
#%since 1.9.3
a
\#@since 2.4.0
b
#%end
\#@end
c
HERE
      expected = <<HERE
a
c
HERE
      ret = Preprocessor.wrap(StringIO.new(src), params).to_a
      assert_equal(expected, ret.join)
    end

    def test_percent_unknown_directive
      params = { 'version' => '1.8.7' }
      src = <<HERE
#%nosuch
HERE
      assert_raise(BitClust::ParseError) do
        Preprocessor.wrap(StringIO.new(src), params).to_a
      end
    end

    def test_percent_include
      Dir.mktmpdir do |dir|
        File.write("#{dir}/inc.rd", "included\n")
        File.write("#{dir}/main.rd", <<~HERE)
          before
          #%include(inc.rd)
          after
        HERE
        ret = Preprocessor.process("#{dir}/main.rd", { 'version' => '1.8.7' })
        assert_equal("before\nincluded\nafter\n", ret.join)
      end
    end

    def test_at_include_still_works
      Dir.mktmpdir do |dir|
        File.write("#{dir}/inc.rd", "included\n")
        File.write("#{dir}/main.rd", <<~HERE)
          before
          \#@include(inc.rd)
          after
        HERE
        ret = Preprocessor.process("#{dir}/main.rd", { 'version' => '1.8.7' })
        assert_equal("before\nincluded\nafter\n", ret.join)
      end
    end
  end
end
