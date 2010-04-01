require 'bitclust'
require 'stringio'
require 'test/unit'

BITCLUST_DIR = File.dirname(File.dirname(File.expand_path(__FILE__)))
require "#{BITCLUST_DIR}/bin/bitclust.rb"

class TestBitClust < Test::Unit::TestCase
  def setup
    @db = "-d#{BITCLUST_DIR}/test/db-test"
    @out = StringIO.new
  end
  def capi(*argv)
    if argv.first.is_a? Symbol
      argv[0] = argv[0].to_s
    else
      argv = argv[0].split(" ")
    end
    ARGV.replace [@db, "--capi"]
    ARGV.concat argv

    @out.string = ""
    $stdout = @out
    begin
      main
    ensure
      $stdout = STDOUT
    end
    @out.string
  end

  def test_list
    assert_equal("public_func\n", capi("list --function"))
  end

  def test_lookup
    assert_equal(<<-EOS, capi("lookup --function=public_func").chomp)
kind: function
header: VALUE public_func()
filename: test.c


This is public function.
    EOS

    assert_equal(<<-EOS, capi("lookup --function=public_func --html").chomp)
<dl>
<dt>kind</dt><dd>function</dd>
<dt>header</dt><dd>VALUE public_func()</dd>
<dt>filename</dt><dd>test.c</dd>
</dl>
<p>
This is public function.
</p>
    EOS
  end
end
