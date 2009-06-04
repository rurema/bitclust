require 'test/unit'
require 'bitclust/methodsignature'

class TestMethodSignature < Test::Unit::TestCase

  def test_friendlyname
    [
      ["$_ -> String | nil", "--- $_ -> String | nil"],
      ["`command` -> String", "--- `(command) -> String"],
    ].each do |friendly_string, method_signature|
      assert_equal friendly_string, BitClust::MethodSignature.parse(method_signature).friendly_string
    end
  end
end
