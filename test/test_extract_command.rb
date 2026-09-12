require 'test/unit'
require 'stringio'
require 'tmpdir'
require 'bitclust'
require 'bitclust/subcommands/extract_command'
require 'bitclust/subcommands/htmlfile_command'

# extract / htmlfile は旧 RD ソース(refm)専用(rurema/bitclust の出力監査 2026-09):
# Markdown(manual/ の .md)を渡すと無関係なパースエラーになっていたので、
# 未対応であることを案内して失敗する
class TestRdOnlyCommandsRejectMarkdown < Test::Unit::TestCase
  def with_md_file
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'Array.md')
      File.write(path, "---\nlibrary: _builtin\n---\n# class Array < Object\n")
      yield path
    end
  end

  def capture_stderr
    err = StringIO.new
    orig, $stderr = $stderr, err
    yield
    err.string
  ensure
    $stderr = orig
  end

  def test_extract_explains_markdown_is_unsupported
    with_md_file do |path|
      cmd = BitClust::Subcommands::ExtractCommand.new
      cmd.parse([path])
      msg = capture_stderr { assert_raise(SystemExit) { cmd.exec([path], {:prefix => nil, :capi => false}) } }
      assert_match(/Markdown/, msg)
      assert_match(/refm/, msg)
    end
  end

  def test_htmlfile_explains_markdown_is_unsupported
    with_md_file do |path|
      cmd = BitClust::Subcommands::HtmlfileCommand.new
      cmd.parse([path])
      msg = capture_stderr { assert_raise(SystemExit) { cmd.exec([path], {:prefix => nil, :capi => false}) } }
      assert_match(/Markdown/, msg)
      assert_match(/rake generate|bitclust server/, msg)
    end
  end
end
