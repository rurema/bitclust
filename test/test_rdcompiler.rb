require 'bitclust/rdcompiler'
require 'bitclust/screen'
require 'test/unit'

class TestRDCompiler < Test::Unit::TestCase
  
  def setup
    @dummy = 'dummy'
    @u = BitClust::URLMapper.new(Hash.new{@dummy})
    @c = BitClust::RDCompiler.new(@u)
  end

  def compile_and_assert_equal(expected, src)
    assert_equal expected, @c.compile(src)
  end
  
  def test_dlist  
    src = <<'HERE'
: t1
 c1
: t2
 c2-1
 c2-2
HERE
    expected = <<'HERE'
<dl>
<dt>t1</dt>
<dd>
c1
</dd>
<dt>t2</dt>
<dd>
c2-1
c2-2
</dd>
</dl>
HERE
    compile_and_assert_equal(expected, src)
    
    src = <<HERE
: t1
 c1

: t2
 c2

 c3
HERE
    expected = <<HERE
<dl>
<dt>t1</dt>
<dd>
c1

</dd>
<dt>t2</dt>
<dd>
c2

c3
</dd>
</dl>
HERE
    compile_and_assert_equal(expected, src)
    
    src = <<HERE
: t1
 c1
//emlist{
 hoge
//}
: t2
 c2
HERE
    expected = <<'HERE'
<dl>
<dt>t1</dt>
<dd>
c1
</dd>
</dl>
<pre>
 hoge
</pre>
<dl>
<dt>t2</dt>
<dd>
c2
</dd>
</dl>
HERE
    compile_and_assert_equal(expected, src)
  end

  def test_pre
    src = <<'HERE'
 <
 hoge

 foo
HERE
    expected = <<'HERE'
<pre>
&lt;
hoge

foo
</pre>
HERE
    compile_and_assert_equal(expected, src)
        
    src = <<'HERE'
 pretext

 * hoge1
HERE
    expected = <<'HERE'
<pre>
pretext

* hoge1
</pre>
HERE
    compile_and_assert_equal(expected, src)    
  end

  def test_method  
    src = <<'HERE'
--- hoge
foo
bar
 text
HERE
    expected = <<'HERE'
<dt><code>hoge</code></dt>
<dd>
<p>
foo
bar
</p>
<pre>
text
</pre>
</dd>
HERE
    compile_and_assert_equal(expected, src)
    
    src = <<'HERE'
--- <=>
HERE
    expected = <<'HERE'
<dt><code>&lt;=&gt;</code></dt>
<dd>
</dd>
HERE
    compile_and_assert_equal(expected, src)

    src = <<'HERE'
--- method

: word1
  dsc
HERE
    expected = <<'HERE'
<dt><code>method</code></dt>
<dd>
<dl>
<dt>word1</dt>
<dd>
dsc
</dd>
</dl>
</dd>
HERE
    compile_and_assert_equal(expected, src)

    src = <<'HERE'
--- method
dsc

@param hoge bar
@return hoge
@raise hoge
@see hoge
HERE
    expected = <<'HERE'
<dt><code>method</code></dt>
<dd>
<p>
dsc
</p>
<p>
[PARAM] hoge:
bar
</p>
<p>
[RETURN]
hoge
</p>
<p>
[EXCEPTION] hoge:

</p>
<p>
[SEE_ALSO] hoge
</p>
</dd>
HERE
    compile_and_assert_equal(expected, src)
  end

  def test_method2   
    @c = BitClust::RDCompiler.new(@u, 1, {:force => true})   
    src = <<'HERE'
--- hoge1
--- hoge2
bar
HERE
    expected = <<'HERE'
<dl>
<dt><code>hoge1</code></dt>
<dt><code>hoge2</code></dt>
<dd>
<p>
bar
</p>
</dd>
</dl>
HERE
    compile_and_assert_equal(expected, src)
  end

  def test_ul        
    src =  <<'HERE'
 * hoge1
 * hoge2
HERE
    expected = <<'HERE'
<ul>
<li>hoge1</li>
<li>hoge2</li>
</ul>
HERE
    compile_and_assert_equal(expected, src)
    
    src = <<'HERE'
 * hoge1

 * hoge2
HERE
   expected = <<'HERE'
<ul>
<li>hoge1</li>
</ul>
<ul>
<li>hoge2</li>
</ul>
HERE
    compile_and_assert_equal(expected, src)

    src = <<'HERE'
 * hoge1
   bar
 * hoge2
HERE
   expected = <<'HERE'
<ul>
<li>hoge1
bar</li>
<li>hoge2</li>
</ul>
HERE
    compile_and_assert_equal(expected, src)

  end

  def test_olist
    src = <<'HERE'
 (1) hoge1
     bar
 (2) hoge2
HERE
   expected = <<'HERE'
<ol>
<li>hoge1
bar</li>
<li>hoge2</li>
</ol>
HERE
    compile_and_assert_equal(expected, src)    
  end
  
  def test_braket_link
    [
     ['[[c:String]]',      '<a href="dummy/class/String">String</a>'           ],
     ['[[c:String ]]',     '<a href="dummy/class/String">String</a>'           ],
     ['[[c:File::Stat]]',  '<a href="dummy/class/File=Stat">File::Stat</a>'    ],
     ['[[m:String.new]]',  '<a href="dummy/method/String/s/new">String.new</a>'],
     ['[[m:String#dump]]', '<a href="dummy/method/String/i/dump">String#dump</a>'],
     ['[[m:String#[] ]]',  '<a href="dummy/method/String/i/=5b=5d">String#[]</a>'],
     ['[[lib:jcode]]',     '<a href="dummy/library/jcode">jcode</a>'],
     ['[[d:hoge/bar]]',    '<a href="dummy/hoge/bar">hoge/bar</a>'],
     ['[[man:tr(1)]]',     '<a href="http://www.opengroup.org/onlinepubs/009695399/utilities/tr.html">tr(1)</a>'],
     ['[[RFC:2822]]',      '<a href="http://www.ietf.org/rfc/rfc2822.txt">[RFC2822]</a>'],
     ['[[m:$~]]',          '<a href="dummy/method/Kernel/v/=7e">$~</a>'],
     ['[[c:String]]]', '<a href="dummy/class/String">String</a>]'],     
     ['[[c:String]][[c:String]]',
      '<a href="dummy/class/String">String</a><a href="dummy/class/String">String</a>'],     
     ['[[m:File::SEPARATOR]]',          '<a href="dummy/method/File/c/SEPARATOR">File::SEPARATOR</a>'],     
     ['[[url:http://i.loveruby.net]]', '<a href="http://i.loveruby.net">http://i.loveruby.net</a>'],
     ['[[ruby-list:12345]]',
      '<a href="http://blade.nagaokaut.ac.jp/cgi-bin/scat.rb/ruby/ruby-list/12345">[ruby-list:12345]</a>'],
    ].each{|src, expected|
      assert_equal expected, @c.send(:compile_text, src)
    }
  end
end
