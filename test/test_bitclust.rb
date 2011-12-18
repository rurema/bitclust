require 'bitclust'
require 'bitclust/subcommand'
require 'stringio'
require 'tmpdir'
require 'fileutils'

class TestBitClust < Test::Unit::TestCase
  def setup
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

    @out = StringIO.new
  end

  def teardown
    FileUtils.rm_r(@tmpdir, :force => true)
  end

  def search_capi(command, *argv)
    db = BitClust::FunctionDatabase.new(@tmpdir)
    cmd = case command
          when "lookup"
            BitClust::LookupCommand.new
          when "list"
            BitClust::ListCommand.new
          else
            raise "must not happen! command=#{command}"
          end
    @out.string = ""
    $stdout = @out
    begin
      cmd.parse(argv)
      cmd.exec(db, argv)
    ensure
      $stdout = STDOUT
    end
    @out.string
  end

  def test_list
    assert_equal("public_func\n", search_capi("list", "--function"))
  end

  def test_lookup
    assert_equal(<<-EOS, search_capi("lookup", "--function=public_func").chomp)
kind: function
header: VALUE public_func()
filename: test.c


This is public function.
    EOS
  end

  def test_lookup_html
    assert_equal(<<-EOS, search_capi("lookup", "--function=public_func", "--html").chomp)
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
