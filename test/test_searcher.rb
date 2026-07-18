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
