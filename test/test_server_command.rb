require 'test/unit'
require 'stringio'
require 'bitclust'
require 'bitclust/subcommands/server_command'

# bitclust server の DB 指定(rurema/bitclust の出力監査 2026-09):
# runner の DB 必須チェックはグローバル --database を見るが、server は自前の
# --database を見ていたため、片方だけでは起動できなかった。
# - server は DB を自前で受けるので runner に要求させない(needs_database? false)
# - サブコマンド側の -d/--database と、グローバル --database(options[:prefix])の
#   どちらでも起動できる
class TestServerCommand < Test::Unit::TestCase
  def build(argv)
    cmd = BitClust::Subcommands::ServerCommand.new
    cmd.parse(argv)
    cmd
  end

  def test_does_not_require_global_database
    assert_false BitClust::Subcommands::ServerCommand.new.needs_database?
  end

  def test_parse_accepts_short_option
    cmd = build(['--baseurl=', '-d', '/tmp/db-x'])
    assert_equal '/tmp/db-x', cmd.__send__(:resolve_dbpath, {:prefix => nil, :capi => false})
  end

  def test_parse_accepts_long_option
    cmd = build(['--baseurl=', '--database=/tmp/db-y'])
    assert_equal '/tmp/db-y', cmd.__send__(:resolve_dbpath, {:prefix => '/tmp/global', :capi => false})
  end

  def test_global_database_is_used_as_fallback
    cmd = build(['--baseurl='])
    assert_equal '/tmp/global', cmd.__send__(:resolve_dbpath, {:prefix => '/tmp/global', :capi => false})
  end

  def test_missing_database_aborts_with_guidance
    cmd = build(['--baseurl='])
    err = StringIO.new
    orig, $stderr = $stderr, err
    assert_raise(SystemExit) { cmd.__send__(:resolve_dbpath, {:prefix => nil, :capi => false}) }
    assert_match(/--database/, err.string)
  ensure
    $stderr = orig
  end
end
