# frozen_string_literal: true
require 'test/unit'
require 'bitclust'
require 'bitclust/methoddatabase'
require 'bitclust/subcommands/rbssig_command'
require 'stringio'
require 'tmpdir'
require 'fileutils'
require 'json'

# rbssig サブコマンド(RBS シグネチャ表示)。
#
#   bitclust rbssig --sig-dir=DIR <dbpath>
#   bitclust rbssig --sig-root=RBS_CHECKOUT <dbpath>
#
# RBS シグネチャは 4.0 以降のドキュメント専用なので、DB の version が
# 4.0 未満ならエラーにする(比較は display_typemark と同じく Gem::Version。
# 文字列比較だと "10.0" が "4.0" より小さく見える)。
#
# テストリスト:
# [x] グローバル --database 不要(needs_database? が false)
# [x] --sig-root/--sig-dir がどちらも無いとエラー
# [x] dbpath がちょうど 1 個でないとエラー
# [x] DB の version が 4.0 未満だとエラー
# [x] version 10.0 は 4.0 以降として通る(Gem::Version 比較)
# [x] 4.0 の DB に rbs_sig が書き込まれ、統計行が出力される
# [x] --dry-run は統計だけ表示して実 DB には書き込まない
# [x] --sig-root は core/ と stdlib/ を持つチェックアウトを読める
# [x] Runner に登録されている(bitclust rbssig として呼べる)
class TestRbssigCommand < Test::Unit::TestCase
  def setup
    @tmpdir = Dir.mktmpdir
    @sig_dir = File.join(@tmpdir, 'sig')
    FileUtils.mkdir_p(@sig_dir)
    File.write(File.join(@sig_dir, 'foo.rbs'), <<~RBS)
      class Foo
        def bar: (Integer) -> String
      end
    RBS
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def test_needs_no_global_database_option
    cmd = BitClust::Subcommands::RbssigCommand.new
    assert_false cmd.needs_database?
  end

  def test_no_sig_source_is_an_error
    db = build_db('4.0')
    assert_command_error([db])
  end

  def test_requires_exactly_one_dbpath
    db = build_db('4.0')
    assert_command_error(["--sig-dir=#{@sig_dir}"])
    assert_command_error(["--sig-dir=#{@sig_dir}", db, db])
  end

  def test_old_database_version_is_an_error
    db = build_db('3.4')
    assert_command_error(["--sig-dir=#{@sig_dir}", db])
  end

  def test_version_10_passes_the_gate
    db = build_db('10.0')
    out = run_command(["--sig-dir=#{@sig_dir}", db])
    assert_match(/version 10\.0/, out)
    assert_equal [['t', '('], ['c', 'Integer'], ['t', ') -> '], ['c', 'String']],
                 find_entry(db, 'bar').rbs_signature_segments[0]
  end

  def test_fills_rbs_sig_and_prints_stats
    db = build_db('4.0')
    out = run_command(["--sig-dir=#{@sig_dir}", db])
    assert_equal '(Integer) -> String',
                 find_entry(db, 'bar').rbs_signature_segments[0].map {|_k, t| t }.join
    assert_nil find_entry(db, 'nope').rbs_signature_segments
    assert_match(
      /\Adb-4\.0 \(version 4\.0\): entries_updated=1 sigs_matched=1 methods_missed=1\n\z/,
      out)
  end

  def test_dry_run_leaves_database_untouched
    db = build_db('4.0')
    out = run_command(["--sig-dir=#{@sig_dir}", db, '--dry-run'])
    assert_nil find_entry(db, 'bar').rbs_signature_segments
    assert_match(/entries_updated=1/, out)
  end

  def test_sig_root_reads_core_and_stdlib_layout
    root = File.join(@tmpdir, 'rbs-checkout')
    FileUtils.mkdir_p("#{root}/core")
    File.write("#{root}/core/foo.rbs", <<~RBS)
      class Foo
        def bar: (String) -> Integer
      end
    RBS
    # core_root を与えると rbs は stringio を暗黙に要求するので、
    # 本物のチェックアウトと同じく stdlib/ も置く
    FileUtils.mkdir_p("#{root}/stdlib/stringio/0")
    File.write("#{root}/stdlib/stringio/0/stringio.rbs", "class StringIO\nend\n")

    db = build_db('4.0')
    run_command(["--sig-root=#{root}", db])
    assert_equal '(String) -> Integer',
                 find_entry(db, 'bar').rbs_signature_segments[0].map {|_k, t| t }.join
  end

  def test_registered_in_runner
    require 'bitclust/runner'
    runner = BitClust::Runner.new
    runner.prepare
    subcommands = runner.instance_variable_get(:@subcommands)
    assert_kind_of BitClust::Subcommands::RbssigCommand, subcommands['rbssig']
  end

  private

  def build_db(version)
    root = "#{@tmpdir}/tree-#{version}/refm/api/src"
    FileUtils.mkdir_p("#{root}/_builtin")
    File.write("#{root}/LIBRARIES", "_builtin\n")
    File.write("#{root}/_builtin.rd", <<~RD)
      description

      = class Foo < Object
      == Instance Methods
      --- bar(val) -> String

      説明

      --- nope -> nil

      説明
    RD
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

  def find_entry(prefix, name)
    db = BitClust::MethodDatabase.new(prefix)
    db.get_class('Foo').entries.find {|m| m.name?(name) }
  end

  def run_command(argv)
    cmd = BitClust::Subcommands::RbssigCommand.new
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

  def assert_command_error(argv)
    cmd = BitClust::Subcommands::RbssigCommand.new
    cmd.parse(argv)
    assert_raise(SystemExit) do
      capture_stderr { cmd.exec(argv, { prefix: nil, capi: false }) }
    end
  end

  def capture_stderr
    orig = $stderr
    $stderr = StringIO.new
    yield
  ensure
    $stderr = orig
  end
end
