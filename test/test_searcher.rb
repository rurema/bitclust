require "test/unit"
require "bitclust"
require "bitclust/searcher"
require "fileutils"
require "tmpdir"

class TestTerminalView < Test::Unit::TestCase
  include BitClust

  def test_show_class
    view = TerminalView.new(Plain.new, {})
    db = Database.dummy
    foo = ClassEntry.new(db, "Foo")
    bar = ClassEntry.new(db, "Bar")
    out, err = capture_output do
      assert_nothing_raised do
        view.show_class([foo, bar])
      end
    end
    assert_equal %w[Bar Foo], out.split
    assert_empty err
  end
end

class TestSearcherWindowsDrivePath < Test::Unit::TestCase
  include BitClust

  ENV_KEYS = %w[REFE2_SERVER BITCLUST_SERVER REFE2_DATADIR BITCLUST_DATADIR]

  def setup
    @saved_env = {}
    ENV_KEYS.each {|key| @saved_env[key] = ENV.delete(key) }
    @saved_dir = Dir.pwd
    @searcher = Searcher.new
  end

  def teardown
    Dir.chdir(@saved_dir)
    ENV_KEYS.each do |key|
      if @saved_env[key]
        ENV[key] = @saved_env[key]
      else
        ENV.delete(key)
      end
    end
  end

  def test_windows_drive_path_predicate
    assert_true @searcher.send(:windows_drive_path?, "G:/Users/foo/.bitclust/db-2.2.0")
    assert_true @searcher.send(:windows_drive_path?, 'C:\Users\foo\.bitclust\db-2.2.0')
    assert_false @searcher.send(:windows_drive_path?, "/home/foo/.bitclust/db-2.2.0")
    assert_false @searcher.send(:windows_drive_path?, "druby://localhost:10001")
  end

  def test_drive_path_uri_keeps_drive_letter
    uri = @searcher.send(:drive_path_uri, "G:/Users/foo/.bitclust/db-2.2.0")
    assert_equal "file", uri.scheme
    assert_equal "G:/Users/foo/.bitclust/db-2.2.0", uri.path
  end

  def test_find_dblocation_keeps_windows_drive_letter
    with_fake_datadir("G:/Users/foo/.bitclust/db-2.2.0") do |relative_path|
      ENV["BITCLUST_DATADIR"] = relative_path
      location = @searcher.send(:find_dblocation)
      assert_equal "file", location.scheme
      assert_equal relative_path, location.path
    end
  end

  def test_find_dblocation_keeps_unix_absolute_path
    Dir.mktmpdir do |dir|
      datadir = File.join(dir, ".bitclust", "db-2.2.0")
      FileUtils.mkdir_p(datadir)
      FileUtils.touch(File.join(datadir, "properties"))
      ENV["BITCLUST_DATADIR"] = datadir
      location = @searcher.send(:find_dblocation)
      assert_equal "file", location.scheme
      assert_equal datadir, location.path
    end
  end

  def test_database_option_keeps_windows_drive_letter
    @searcher.parser.parse!(["--database=G:/Users/foo/.bitclust/db-2.2.0"])
    dblocation = @searcher.instance_variable_get(:@dblocation)
    assert_equal "file", dblocation.scheme
    assert_equal "G:/Users/foo/.bitclust/db-2.2.0", dblocation.path
  end

  private

  # datadir/properties を tmpdir 内に作り、tmpdir へ chdir したうえで
  # datadir までの相対パス(ドライブレターを含む)を渡す。":" は Unix の
  # ファイル名として有効な文字なので、Linux 上でも "G:" というディレク
  # トリを作ってドライブレター付きパスの再現ができる
  def with_fake_datadir(relative_path)
    Dir.mktmpdir do |dir|
      datadir = File.join(dir, *relative_path.split("/"))
      FileUtils.mkdir_p(datadir)
      FileUtils.touch(File.join(datadir, "properties"))
      Dir.chdir(dir) do
        yield relative_path
      end
    end
  end
end

# refe の module_function 表示(bitclust#297)。
# HTML 側(#282)と同じく、DB のバージョンが 4.0 以降なら
# "Foo.#baz" ではなく "Foo?.baz" と表示する。
class TestSearcherModuleFunctionDisplay < Test::Unit::TestCase
  include BitClust

  def record_for(version)
    db = MethodDatabase.dummy("version" => version)
    spec = MethodSpec.parse("Foo.#baz")
    SearchResult::Record.new(db, spec, spec)
  end

  def test_names_folds_module_function_typemark_for_40
    assert_equal ["Foo?.baz"], record_for("4.0").names
  end

  def test_names_keeps_typemark_before_40
    assert_equal ["Foo.#baz"], record_for("3.4").names
  end

  def test_names_without_db_version_keeps_typemark
    spec = MethodSpec.parse("Foo.#baz")
    assert_equal ["Foo.#baz"], SearchResult::Record.new(nil, spec, spec).names
  end
end

# refe のクエリ側も 4.0 以降の表示形式 "Foo?.baz" を受け付ける(bitclust#297)
class TestSearcherModuleFunctionQuery < Test::Unit::TestCase
  include BitClust

  def parse(pat)
    Searcher.new.send(:parse_method_spec_pattern, pat)
  end

  def test_question_dot_pattern
    assert_equal ["Foo", ".#", "baz"], parse("Foo?.baz")
  end

  def test_dot_hash_pattern_still_works
    assert_equal ["Foo", ".#", "baz"], parse("Foo.#baz")
  end

  def test_predicate_method_names_unaffected
    assert_equal ["Foo", "#", "empty?"], parse("Foo#empty?")
    assert_equal ["Foo", ".", "b?"], parse("Foo.b?")
  end
end
