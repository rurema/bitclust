require 'test/unit'
require 'bitclust/methodsignature'

class TestMethodSignature < Test::Unit::TestCase

  data("special var" => ["$_ -> String | nil", "--- $_ -> String | nil"],
       "backquote"   => ["`command` -> String", "--- `(command) -> String"])
  def test_friendlyname(data)
    friendly_string, method_signature = data
    assert_equal(friendly_string, BitClust::MethodSignature.parse(method_signature).friendly_string)
  end
end
