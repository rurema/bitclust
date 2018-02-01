require 'bitclust/syntax_highlighter'

class TestSyntaxHighlighter < Test::Unit::TestCase
  def highlight(src, filename = "-")
    BitClust::SyntaxHighlighter.new(src, filename).highlight
  end

  sub_test_case "syntax error" do
    test "single line" do
      src = "...\n"
      assert_raise(BitClust::SyntaxHighlighter::ParseError.new("-", 1, 3, "syntax error, unexpected ...")) do
        highlight(src)
      end
    end

    test "multiple line" do
      src = "a = 1\n...\n"
      assert_raise(BitClust::SyntaxHighlighter::ParseError.new("-", 2, 3, "syntax error, unexpected ..., expecting end-of-input")) do
        highlight(src)
      end
    end
  end
end
