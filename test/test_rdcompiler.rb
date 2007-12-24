require 'bitclust/rdcompiler'
require 'bitclust/screen'
require 'test/unit'

class TestRDCompiler < Test::Unit::TestCase

  def setup
    @u = BitClust::URLMapper.new(Hash.new{'dummy'})
    @c = BitClust::RDCompiler.new(@u)
  end
  
  def test_dlist  
    ret = @c.compile <<'HERE'
: t1
 c1
: t2
 c2-1
 c2-2
HERE
    assert_equal <<'HERE', ret
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
    ret = @c.compile <<HERE
: t1
 c1

: t2
 c2
HERE
    assert_equal <<'HERE', ret
<dl>
<dt>t1</dt>
<dd>
c1

</dd>
<dt>t2</dt>
<dd>
c2
</dd>
</dl>
HERE
    
    ret = @c.compile <<HERE
: t1
 c1
//emlist{
 hoge
//}
: t2
 c2
HERE

    assert_equal <<'HERE', ret
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

  end

  def test_pre
    ret = @c.compile <<'HERE'
 <
 hoge

 foo
HERE

    assert_equal <<'HERE', ret
<pre>
&lt;
hoge

foo
</pre>
HERE
  end

  def test_method
    
    ret = @c.compile <<'HERE'
--- hoge
foo
bar
 text
HERE
    assert_equal <<'HERE', ret
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
    
    ret = @c.compile <<'HERE'
--- <=>
HERE
   assert_equal <<'HERE', ret
<dt><code>&lt;=&gt;</code></dt>
<dd>
</dd>
HERE
    
    c = BitClust::RDCompiler.new(@u, 1, {:force => true})
    ret = c.compile <<'HERE'
--- hoge1
--- hoge2
bar
HERE
    
    assert_equal <<'HERE', ret
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

  end

  def test_ul
        
    ret = @c.compile <<'HERE'
 * hoge1
 * hoge2
HERE
   assert_equal <<'HERE', ret
<ul>
<li>hoge1</li>
<li>hoge2</li>
</ul>
HERE
        
    ret = @c.compile <<'HERE'
 * hoge1

 * hoge2
HERE
   assert_equal <<'HERE', ret
<ul>
<li>hoge1</li>
</ul>
<ul>
<li>hoge2</li>
</ul>
HERE
 
  end
end
