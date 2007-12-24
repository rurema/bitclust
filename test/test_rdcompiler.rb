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

  
end
