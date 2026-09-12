require 'test/unit'
require 'stringio'
require 'tmpdir'
require 'bitclust'
require 'bitclust/subcommands/query_command'

# bitclust query(rurema/bitclust の出力監査 2026-09):
# exec が super を呼ばず @db が nil のまま eval していたため使えなかった
class TestQueryCommand < Test::Unit::TestCase
  def run_query(script, capi: false)
    Dir.mktmpdir do |dir|
      cmd = BitClust::Subcommands::QueryCommand.new
      cmd.parse([script])
      out = StringIO.new
      orig, $stdout = $stdout, out
      begin
        cmd.exec([script], {:prefix => dir, :capi => capi})
      ensure
        $stdout = orig
      end
      out.string
    end
  end

  def test_db_is_available_to_the_script
    assert_equal %Q("BitClust::MethodDatabase"\n), run_query('@db.class.name')
  end

  def test_capi_uses_function_database
    assert_equal %Q("BitClust::FunctionDatabase"\n), run_query('@db.class.name', capi: true)
  end
end
