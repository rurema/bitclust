require 'test/unit'
require 'bitclust/preprocessor'
require 'stringio'

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
end

