require 'bitclust/syntax_highlighter'

class TestSyntaxHighlighter < Test::Unit::TestCase
  def highlight(src, filename = "-")
    BitClust::SyntaxHighlighter.new(src, filename).highlight
  end

  sub_test_case "syntax error" do
    test "single line" do
      src = "foo(\n"
      assert_raise(BitClust::SyntaxHighlighter::ParseError.new("-", 1, 5, "syntax error, unexpected end-of-input, expecting ')'\n#{src}")) do
        highlight(src)
      end
    end

    test "multiple line" do
      src = "a = 1\nfoo(\n"
      assert_raise(BitClust::SyntaxHighlighter::ParseError.new("-", 2, 5, "syntax error, unexpected end-of-input, expecting ')'\n#{src}")) do
        highlight(src)
      end
    end
  end

  sub_test_case "__END__" do
    test "extra data" do
      source = <<~END
      require "csv"
      csv = CSV.new(DATA.read)
      csv.read
      # => [["header1", "header2"], ["row1_1", "row1_2"], ["row2_1", "row2_2"]]
      __END__
      header1,header2
      row1_1,row1_2
      row2_1,row2_2
      END
      expected = <<~END.chomp
      <span class="nb">require</span> <span class="s2">"</span><span class="s2">csv</span><span class="s2">"</span>
      csv <span class="o">=</span> <span class="no">CSV</span><span class="p">.</span><span class="nf">new</span><span class="p">(</span><span class="no">DATA</span><span class="p">.</span><span class="nf">read</span><span class="p">)</span>
      csv<span class="p">.</span><span class="nf">read</span>
      <span class="c1"># =&gt; [[&quot;header1&quot;, &quot;header2&quot;], [&quot;row1_1&quot;, &quot;row1_2&quot;], [&quot;row2_1&quot;, &quot;row2_2&quot;]]
      </span><span class="k">__END__
      </span><span class="c1">header1,header2
      row1_1,row1_2
      row2_1,row2_2
      </span>
      END
      assert_equal(expected, highlight(source))
    end

    test "without extra data" do
      source = <<~END
      require "csv"
      csv = CSV.new(DATA.read)
      csv.read
      # => [["header1", "header2"], ["row1_1", "row1_2"], ["row2_1", "row2_2"]]
      END
      expected = <<~END.chomp
      <span class="nb">require</span> <span class="s2">"</span><span class="s2">csv</span><span class="s2">"</span>
      csv <span class="o">=</span> <span class="no">CSV</span><span class="p">.</span><span class="nf">new</span><span class="p">(</span><span class="no">DATA</span><span class="p">.</span><span class="nf">read</span><span class="p">)</span>
      csv<span class="p">.</span><span class="nf">read</span>
      <span class="c1"># =&gt; [[&quot;header1&quot;, &quot;header2&quot;], [&quot;row1_1&quot;, &quot;row1_2&quot;], [&quot;row2_1&quot;, &quot;row2_2&quot;]]
      </span>
      END
      assert_equal(expected, highlight(source))
    end
  end

  test 'htmlescape' do
    source = 'puts /<a>/'
    expected = '<span class="nb">puts</span> <span class="sr">/&lt;a&gt;/</span>'
    assert_equal(expected, highlight(source))
  end

  test 'symbol method' do
    source = <<~END
      p 1.!
      p 2
    END
    expected = <<~END
      <span class="nb">p</span> <span class="mi">1</span><span class="p">.</span><span class="o">!</span>
      <span class="nb">p</span> <span class="mi">2</span>
    END
    assert_equal(expected, highlight(source))
  end

  test 'symbol const' do
    source = <<~END
      class Foo
        def to_hash
          {:Bar => 'a',
           :Baz => 'b'
          }
        end
      end
    END
    expected = <<~END
      <span class="k">class</span> <span class="nn"></span><span class="o"></span><span class="nc">Foo</span>
        <span class="k">def</span> <span class="nf">to_hash</span>
          <span class="p">{</span><span class="ss">:Bar</span> <span class="o">=&gt;</span> <span class="s1">'a'</span>,
           <span class="ss">:Baz</span> <span class="o">=&gt;</span> <span class="s1">'b'</span>
          <span class="p">}</span>
        <span class="k">end</span>
      <span class="k">end</span>
    END
    assert_equal(expected, highlight(source))
  end

  test 'symbol list' do
    source = <<~END
      %i[hellow world].each {|s| p s }
    END
    expected = <<~END
      <span class="ss">%i[hellow world]</span><span class="p">.</span><span class="nf">each</span> <span class="p">{</span><span class="o">|</span>s<span class="o">|</span> <span class="nb">p</span> s <span class="p">}</span>
    END
    assert_equal(expected, highlight(source))

    source = <<~END
      %I[hellow world].each {|s| p s }
    END
    expected = <<~END
      <span class="ss">%I[hellow world]</span><span class="p">.</span><span class="nf">each</span> <span class="p">{</span><span class="o">|</span>s<span class="o">|</span> <span class="nb">p</span> s <span class="p">}</span>
    END
    assert_equal(expected, highlight(source))
  end

  test 'one liner module' do
    source = <<~END
      module Foo; end
    END
    expected = <<~END
      <span class="k">module</span> <span class="nn">Foo</span>; <span class="k">end</span>
    END
    assert_equal(expected, highlight(source))
  end

  test 'one liner class' do
    source = <<~END
      class Foo; end
    END
    expected = <<~END
      <span class="k">class</span> <span class="nn"></span><span class="o"></span><span class="nc">Foo</span>; <span class="k">end</span>
    END
    assert_equal(expected, highlight(source))
  end
end
