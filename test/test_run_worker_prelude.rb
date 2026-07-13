require 'test/unit'

# theme/default/js/run-worker.js の PRELUDE(Ruby コード)の検証。
# Kernel#puts/print/p は $stdout が IO でないとき #write 経由で書き込むが、
# マニュアルのサンプルは $stderr.puts や $stdout.putc のように IO のメソッドを
# 直接呼ぶこともある(旧実装の StringIO はそれらを備えていた)。JS ブリッジを
# スタブした実 Ruby で PRELUDE を eval し、両方の経路の出力を確認する。
class TestRunWorkerPrelude < Test::Unit::TestCase
  WORKER_JS = File.expand_path('../theme/default/js/run-worker.js', __dir__)

  module JSStub
    OUTPUT = []
    def self.global
      self
    end

    def self.call(name, text)
      raise ArgumentError, "unexpected JS call: #{name}" unless name == :postOutput
      OUTPUT << text.to_s
    end
  end

  def setup
    src = File.read(WORKER_JS)
    prelude = src[/export const PRELUDE = `\n(.*?)\n`/m, 1]
    assert_not_nil(prelude, 'PRELUDE not found in run-worker.js')
    # ruby.wasm 上でだけ存在する js gem をスタブに差し替える
    @prelude = prelude.sub(/\Arequire "js"\n/, '')
    JSStub::OUTPUT.clear
    Object.const_set(:JS, JSStub)
  end

  def teardown
    Object.send(:remove_const, :JS) if Object.const_defined?(:JS)
    Object.send(:remove_const, :JSStreamIO) if Object.const_defined?(:JSStreamIO)
  end

  def run_with_prelude
    orig_stdout = $stdout
    orig_stderr = $stderr
    begin
      eval(@prelude, TOPLEVEL_BINDING)
      yield
    ensure
      $stdout = orig_stdout
      $stderr = orig_stderr
    end
    JSStub::OUTPUT.join
  end

  def test_kernel_methods_stream_through_post_output
    out = run_with_prelude do
      puts 'hello'
      print 'a', 'b'
      p 123
    end
    assert_equal("hello\nab123\n", out)
  end

  def test_direct_io_methods_match_old_stringio_behavior
    out = run_with_prelude do
      $stdout.puts 'direct'
      $stderr.puts 'err'
      $stdout.putc 'XY'
      $stdout.print 'pr'
      $stdout.printf('%05d', 42)
      $stdout << 'chained' << '!'
      $stdout.flush
      $stdout.puts ['a', ['b']]
      $stdout.puts
    end
    assert_equal("direct\nerr\nXpr00042chained!a\nb\n\n", out)
  end

  def test_stream_reports_not_a_tty_and_accepts_sync
    run_with_prelude do
      assert_false($stdout.tty?)
      assert_false($stderr.isatty)
      assert_true($stdout.sync)
      $stdout.sync = true
    end
  end
end
