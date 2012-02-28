require 'bitclust'
require 'bitclust/runner'
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

class TestRunner < Test::Unit::TestCase
  def setup
    @runner = BitClust::Runner.new
    home_directory = Pathname(ENV['HOME'])
    @config_path = home_directory + ".bitclust/config"
    @config = {
      :default_version => "1.9.3",
      :database_prefix => "/home/user/.bitclust/db"
    }
    @prefix = "/home/user/.bitclust/db-1.9.3"
    @db = Object.new
  end

  def test_run_setup
    command = mock(Object.new)
    mock(::BitClust::SetupCommand).new.returns(command)
    command.parse([])
    command.exec(nil, []).returns(nil)
    @runner.run(["setup"])
  end

  def test_run_server
    command = mock(Object.new)
    mock(::BitClust::ServerCommand).new.returns(command)
    command.parse([])
    command.exec(nil, []).returns(nil)
    @runner.run(["server"])
  end

  def test_run_init
    command = mock(Object.new)
    mock(::BitClust::InitCommand).new.returns(command)
    mock(@runner).load_config.returns(@config)
    mock(BitClust::MethodDatabase).new(@prefix).returns(@db)
    command.parse(["version=1.9.3", "encoding=euc-jp"])
    command.exec(@db, ["version=1.9.3", "encoding=euc-jp"]).returns(nil)
    @runner.run(["init", "version=1.9.3", "encoding=euc-jp"])
  end

  def test_run_list
    command = mock(Object.new)
    mock(::BitClust::ListCommand).new.returns(command)
    mock(@runner).load_config.returns(@config)
    mock(BitClust::MethodDatabase).new(@prefix).returns(@db)
    command.parse(["--library"])
    command.exec(@db, ["--library"])
    @runner.run(["list", "--library"])
  end

  def test_run_lookup
    command = mock(Object.new)
    mock(::BitClust::ListCommand).new.returns(command)
    mock(@runner).load_config.returns(@config)
    mock(BitClust::MethodDatabase).new(@prefix).returns(@db)
    command.parse(["--library=optparse"])
    command.exec(@db, ["--library=optparse"])
    @runner.run(["list", "--library=optparse"])
  end

  def test_run_searcher
    command = mock(Object.new)
    mock(::BitClust::Searcher).new.returns(command)
    mock(@runner).load_config.returns(@config)
    mock(BitClust::MethodDatabase).new(@prefix).returns(@db)
    command.parse(["String#gsub"])
    command.exec(@db, ["String#gsub"])
    @runner.run(["search", "String#gsub"])
  end

  def test_run_query
    command = mock(Object.new)
    mock(::BitClust::QueryCommand).new.returns(command)
    mock(@runner).load_config.returns(@config)
    mock(BitClust::MethodDatabase).new(@prefix).returns(@db)
    command.parse(["db.properties"])
    command.exec(@db, ["db.properties"])
    @runner.run(["query", "db.properties"])
  end

  def test_run_update
    command = mock(Object.new)
    mock(::BitClust::UpdateCommand).new.returns(command)
    mock(@runner).load_config.returns(@config)
    mock(BitClust::MethodDatabase).new(@prefix).returns(@db)
    command.parse(["_builtin/String"])
    command.exec(@db, ["_builtin/String"])
    @runner.run(["update", "_builtin/String"])
  end

  def test_run_property
    command = mock(Object.new)
    mock(::BitClust::PropertyCommand).new.returns(command)
    mock(@runner).load_config.returns(@config)
    mock(BitClust::MethodDatabase).new(@prefix).returns(@db)
    command.parse(["--list"])
    command.exec(@db, ["--list"])
    @runner.run(["property", "--list"])
  end
end
