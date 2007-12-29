require 'bitclust/rdcompiler'
require 'bitclust/screen'
require 'test/unit'

class TestRDCompiler < Test::Unit::TestCase

  def setup
    @u = BitClust::URLMapper.new(Hash.new{'dummy'})
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
end
