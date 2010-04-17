require 'bitclust'
require 'stringio'
require 'test/unit'
require 'tmpdir'
require 'fileutils'

BITCLUST_DIR = File.dirname(File.dirname(File.expand_path(__FILE__)))
require "#{BITCLUST_DIR}/bin/bitclust.rb"

class TestBitClust < Test::Unit::TestCase
  def setup
    @prefix = 'db'

    @pwd = Dir.pwd
    @tmpdir = Dir.mktmpdir
    src = "#{@tmpdir}/function/public_func"
    @srcdir = Dir.mkdir File.dirname(src)
    File.open(src, 'w') do |file|
      file.puts <<'HERE'
filename=test.c
macro=false
private=false
type=VALUE
name=public_func
params=()


This is public function.
HERE
    end
    
    @db = "-d#{@tmpdir}"
    @out = StringIO.new
  end
  def teardown
    FileUtils.rm_r(@tmpdir, :force => true)
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
