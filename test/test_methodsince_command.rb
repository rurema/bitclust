# frozen_string_literal: true
require 'test/unit'
require 'bitclust'
require 'bitclust/methoddatabase'
require 'bitclust/subcommands/methodsince_command'
require 'stringio'
require 'tmpdir'
require 'fileutils'

# methodsince サブコマンド(bitclust#132 P2)。
#
# テストリスト:
# [x] グローバル --database 不要(needs_database? が false)
# [x] --update が無いとエラー
# [x] ラダー DB を走査して --update 対象に since/until が書き込まれる
#     (フロアのメソッドには付かず、ゲート付きメソッドには付く)
# [x] 統計行が "basename (version V): entries_updated=.. since_filled=..
#     until_filled=.. floor_skipped=.." の形式で出力される
# [x] --update は複数指定でき、対象ごとに統計行が出力される
# [x] --update に無い位置引数の DB はラダーには参加するが書き込まれない
# [x] --dry-run は統計を表示するだけで実DBファイルには一切書き込まない
# [x] Runner に登録されている(bitclust methodsince として呼べる)
class TestMethodsinceCommand < Test::Unit::TestCase
  def setup
    @tmpdir = "methodsince_test_tmp"
    FileUtils.rm_rf(@tmpdir)
    @db10 = build_db('1.0', <<~'RD')
      description

      = class Foo < Object
      == Instance Methods
      --- old

      説明
    RD
    @db20 = build_db('2.0', <<~'RD')
      description

      = class Foo < Object
      == Instance Methods
      --- old

      説明

      #@since 2.0
      --- newone

      説明
      #@end
    RD
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def build_db(version, builtin_rd)
    root = "#{@tmpdir}/tree-#{version}/refm/api/src"
    FileUtils.mkdir_p("#{root}/_builtin")
    File.write("#{root}/LIBRARIES", "_builtin\n")
    File.write("#{root}/_builtin.rd", builtin_rd)
    prefix = "#{@tmpdir}/db-#{version}"
    db = BitClust::MethodDatabase.new(prefix)
    db.init
    db.transaction do
      db.propset('version', version)
      db.propset('encoding', 'utf-8')
    end
    db.transaction do
      db.update_by_stdlibtree(root)
    end
    prefix
  end

  def run_command(argv)
    cmd = BitClust::Subcommands::MethodsinceCommand.new
    cmd.parse(argv)
    out = StringIO.new
    orig_stdout = $stdout
    $stdout = out
    begin
      cmd.exec(argv, { prefix: nil, capi: false })
    ensure
      $stdout = orig_stdout
    end
    out.string
  end

  def find_entry(prefix, name)
    db = BitClust::MethodDatabase.new(prefix)
    db.get_class('Foo').entries.find {|m| m.name?(name) }
  end

  def test_needs_no_global_database_option
    cmd = BitClust::Subcommands::MethodsinceCommand.new
    assert_false cmd.needs_database?
  end

  def test_no_update_is_an_error
    cmd = BitClust::Subcommands::MethodsinceCommand.new
    argv = [@db10, @db20]
    cmd.parse(argv)
    assert_raise(SystemExit) do
      capture_stderr { cmd.exec(argv, { prefix: nil, capi: false }) }
    end
  end

  def test_fills_since_into_update_target
    run_command([@db10, "--update=#{@db20}"])
    assert_nil find_entry(@db20, 'old').since_of('old')
    assert_equal '2.0', find_entry(@db20, 'newone').since_of('newone')
  end

  def test_prints_one_stats_line_per_target
    out = run_command([@db10, "--update=#{@db20}"])
    assert_match(
      /\Adb-2\.0 \(version 2\.0\): entries_updated=\d+ since_filled=\d+ until_filled=\d+ floor_skipped=\d+\n\z/,
      out)
  end

  def test_multiple_update_targets_each_get_a_stats_line
    out = run_command(["--update=#{@db10}", "--update=#{@db20}"])
    lines = out.lines
    assert_equal 2, lines.size
    assert_match(/\Adb-1\.0 /, lines[0])
    assert_match(/\Adb-2\.0 /, lines[1])
  end

  def test_positional_ladder_db_is_not_written_to
    before = File.read(property_file_path(@db10, 'old'))
    run_command([@db10, "--update=#{@db20}"])
    after = File.read(property_file_path(@db10, 'old'))
    assert_equal before, after
  end

  def test_dry_run_leaves_real_database_untouched
    run_command([@db10, "--update=#{@db20}", '--dry-run'])
    assert_nil find_entry(@db20, 'newone').since_of('newone')
  end

  def test_dry_run_still_prints_computed_stats
    out = run_command([@db10, "--update=#{@db20}", '--dry-run'])
    assert_match(/since_filled=1\b/, out)
  end

  def test_registered_in_runner
    require 'bitclust/runner'
    runner = BitClust::Runner.new
    runner.prepare
    subcommands = runner.instance_variable_get(:@subcommands)
    assert_kind_of(BitClust::Subcommands::MethodsinceCommand, subcommands['methodsince'])
  end

  private

  def property_file_path(prefix, name)
    id = BitClust::NameUtils.build_method_id('_builtin', 'Foo', :instance_method, name)
    File.join(prefix, BitClust::NameUtils.encodeid("method/#{id}"))
  end

  def capture_stderr
    orig = $stderr
    $stderr = StringIO.new
    yield
  ensure
    $stderr = orig
  end
end
