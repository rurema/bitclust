# frozen_string_literal: true
require 'test/unit'
require 'test/unit/rr'
require 'tmpdir'
require 'bitclust'
require 'bitclust/subcommands/epub_command'
require 'bitclust/generators/epub'

# `bitclust epub` は常に失敗していた:
#
# 1) --catalog=PATH は @catalogdir に保存されるが、exec は（定義されていない
#    ため常に nil の）@catalog をジェネレータへ渡していた。ジェネレータは
#    それを statichtml へ --catalog=（空文字列）として渡し、
#    Pathname.new("").realpath が Errno::ENOENT で失敗する。
# 2) @catalogdir の既定値が nil だったので、--catalog を指定しない限り
#    `bitclust epub -o DIR` は必ず失敗していた
#    （chm_command / statichtml_command と同じく、既定は同梱の
#    data/bitclust/catalog にすべき）。
class TestEPUBCommandCatalog < Test::Unit::TestCase
  def test_default_catalogdir_is_the_bundled_catalog
    cmd = BitClust::Subcommands::EPUBCommand.new
    cmd.parse([])
    expected = cmd.srcdir_root + "data/bitclust/catalog"
    assert_equal(expected, cmd.instance_variable_get(:@catalogdir))
    assert_true(expected.directory?, "#{expected} must exist so --catalog can be omitted")
  end

  def test_catalog_option_overrides_the_default
    Dir.mktmpdir do |dir|
      cmd = BitClust::Subcommands::EPUBCommand.new
      cmd.parse(["--catalog=#{dir}"])
      assert_equal(Pathname.new(dir).realpath, cmd.instance_variable_get(:@catalogdir))
    end
  end

  def capture_generator_options(cmd)
    captured = nil
    fake_generator = Object.new
    stub(fake_generator).generate { nil }
    stub(BitClust::Generators::EPUB).new {|opts| captured = opts; fake_generator }
    cmd.exec([], { :prefix => nil, :capi => false })
    captured
  end

  def test_exec_passes_the_default_catalogdir_to_the_generator
    cmd = BitClust::Subcommands::EPUBCommand.new
    cmd.parse([])
    opts = capture_generator_options(cmd)
    assert_equal(cmd.instance_variable_get(:@catalogdir), opts[:catalog])
  end

  def test_exec_passes_the_overridden_catalogdir_to_the_generator
    Dir.mktmpdir do |dir|
      cmd = BitClust::Subcommands::EPUBCommand.new
      cmd.parse(["--catalog=#{dir}"])
      opts = capture_generator_options(cmd)
      assert_equal(Pathname.new(dir).realpath, opts[:catalog])
    end
  end
end
