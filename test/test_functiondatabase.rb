require 'test/unit'
require 'bitclust'
require 'bitclust/functiondatabase'
require 'tmpdir'
require 'fileutils'

class TesFunctionDatabase < Test::Unit::TestCase
  def setup
    prefix = 'db'
    src = "test.rd"

    @pwd = Dir.pwd
    Dir.chdir(@tmpdir = Dir.mktmpdir)
    File.open(src, 'w') do |file|
      file.puts <<'HERE'
--- VALUE func1()

some text

--- VALUE func2()

some text
HERE
    end
    @db = BitClust::FunctionDatabase.new(prefix)
    @db.transaction {
      @db.update_by_file(src, src)
    }
  end

  def teardown
    Dir.chdir @pwd
    FileUtils.rm_r(@tmpdir, :force => true)
  end

  def test_search_functions__function
    result = @db.search_functions('func1')
    assert_not_nil result.first
    assert_equal 1, result.size
    assert_equal 'func1', result.first.name
  end

  def test_search_functions__functions
    result = @db.search_functions('func')
    assert_not_nil result.first
    assert_equal 2, result.size
    assert_equal %w[func1 func2], result.map(&:name)
  end

  def test_search_functions__nonexistent
    assert_raise(BitClust::FunctionNotFound) do
      @db.search_functions('nonexistent')
    end
  end
end
