require 'bitclust/rdcompiler'
require 'bitclust/database'
require 'bitclust/methoddatabase'
require 'bitclust/screen'
require 'test/unit'
require 'timeout'

class TestRDCompiler < Test::Unit::TestCase
  
  def setup
    @dummy = 'dummy'
    @u = BitClust::URLMapper.new(Hash.new{@dummy})
    @c = BitClust::RDCompiler.new(@u, 1, {:database => BitClust::MethodDatabase.dummy})
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
<p>
c1
</p>
</dd>
<dt>t2</dt>
<dd>
<p>
c2-1
c2-2
</p>
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
<p>
c1
</p>
</dd>
<dt>t2</dt>
<dd>
<p>
c2
</p>
<p>
c3
</p>
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
<p>
c1
</p>
<pre>
 hoge
</pre>
</dd>
<dt>t2</dt>
<dd>
<p>
c2
</p>
</dd>
</dl>
HERE
    compile_and_assert_equal(expected, src)
    
    src = <<HERE
: t1
 c1

 c2

text
HERE
    expected = <<'HERE'
<dl>
<dt>t1</dt>
<dd>
<p>
c1
</p>
<p>
c2
</p>
</dd>
</dl>
<p>
text
</p>
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
<dt class="method-heading"><code>hoge</code></dt>
<dd class="method-description">
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

abs
//emlist{
text
//}
HERE
    expected = <<'HERE'
<dt class="method-heading"><code>self &lt;=&gt; </code></dt>
<dd class="method-description">
<p>
abs
</p>
<pre>
text
</pre>
</dd>
HERE
    compile_and_assert_equal(expected, src)

    src = <<'HERE'
--- method

: word1
  dsc
HERE
    expected = <<'HERE'
<dt class="method-heading"><code>method</code></dt>
<dd class="method-description">
<dl>
<dt>word1</dt>
<dd>
<p>
dsc
</p>
</dd>
</dl>
</dd>
HERE
    compile_and_assert_equal(expected, src)

    src = <<'HERE'
--- method
dsc

@param hoge dsc
@return dsc

@raise hoge dsc
@see hoge
HERE
    expected = <<'HERE'
<dt class="method-heading"><code>method</code></dt>
<dd class="method-description">
<p>
dsc
</p>
<dl>
<dt class='method-param'>[PARAM] hoge:</dt>
<dd>
dsc
</dd>
<dt>[RETURN]</dt>
<dd>
dsc
</dd>
<dt>[EXCEPTION] hoge:</dt>
<dd>
dsc
</dd>
</dl>
<p>
[SEE_ALSO] hoge
</p>
</dd>
HERE
    compile_and_assert_equal(expected, src)

    
    src = <<'HERE'
--- method

@param arg dsc1

           dsc2
           dsc3
HERE
    expected = <<'HERE'
<dt class="method-heading"><code>method</code></dt>
<dd class="method-description">
<dl>
<dt class='method-param'>[PARAM] arg:</dt>
<dd>
dsc1
</dd>
</dl>
<pre>
dsc2
dsc3
</pre>
</dd>
HERE
    compile_and_assert_equal(expected, src)
    
    src = <<'HERE'
--- method

@param arg dsc1
//emlist{
dsc2
dsc3
//}
HERE
    expected = <<'HERE'
<dt class="method-heading"><code>method</code></dt>
<dd class="method-description">
<dl>
<dt class='method-param'>[PARAM] arg:</dt>
<dd>
dsc1
<pre>
dsc2
dsc3
</pre>
</dd>
</dl>
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
<dt class="method-heading"><code>hoge1</code></dt>
<dt class="method-heading"><code>hoge2</code></dt>
<dd class="method-description">
<p>
bar
</p>
</dd>
</dl>
HERE
    compile_and_assert_equal(expected, src)
  end

  def test_ulist
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


  def test_invalid_case
        src = <<HERE
: t1
 c1
//e
 hoge
//}
HERE
    Timeout.timeout(10) do
      assert @c.compile(src)
    end
  end
  
  def test_bracket_link
    [
     ['[[c:String]]',      '<a href="dummy/class/String">String</a>'           ],
     ['[[c:String ]]',     '[[c:String ]]'           ],
     ['[[String]]',        '[[String]]'              ],
     ['[[c:File::Stat]]',  '<a href="dummy/class/File=Stat">File::Stat</a>'    ],
     ['[[m:String.new]]',  '<a href="dummy/method/String/s/new">String.new</a>'],
     ['[[m:String#dump]]', '<a href="dummy/method/String/i/dump">String#dump</a>'],
     ['[[m:String#[] ]]',  '<a href="dummy/method/String/i/=5b=5d">String#[]</a>'],
     ['[[f:rb_ary_new3]]', '<a href="dummy/function/rb_ary_new3">rb_ary_new3</a>'],
     ['[[f:/]]',           '<a href="dummy/function/">All C API</a>'],
     ['[[f:_index]]',           '<a href="dummy/function/">All C API</a>'],
     ['[[lib:jcode]]',     '<a href="dummy/library/jcode">jcode</a>'],
     ['[[man:tr(1)]]',     '<a class="external" href="http://www.opengroup.org/onlinepubs/009695399/utilities/tr.html">tr(1)</a>'],
     ['[[RFC:2822]]',      '<a class="external" href="http://www.ietf.org/rfc/rfc2822.txt">[RFC2822]</a>'],
     ['[[m:$~]]',          '<a href="dummy/method/Kernel/v/=7e">$~</a>'],
     ['[[m:$,]]',          '<a href="dummy/method/Kernel/v/=2c">$,</a>'],
     ['[[c:String]]]', '<a href="dummy/class/String">String</a>]'],
     ['[[c:String]][[c:String]]',
      '<a href="dummy/class/String">String</a><a href="dummy/class/String">String</a>'],
     ['[[m:File::SEPARATOR]]',          '<a href="dummy/method/File/c/SEPARATOR">File::SEPARATOR</a>'],
     ['[[url:http://i.loveruby.net]]', '<a class="external" href="http://i.loveruby.net">http://i.loveruby.net</a>'],
     ['[[ruby-list:12345]]',
      '<a class="external" href="http://blade.nagaokaut.ac.jp/cgi-bin/scat.rb/ruby/ruby-list/12345">[ruby-list:12345]</a>'],
    ].each{|src, expected|
      assert_equal expected, @c.send(:compile_text, src), src
    }
    
    [
     ['[[d:hoge/bar]]',             '<a href="dummy/hoge/bar">.*</a>'],
     ['[[ref:d:hoge/bar#frag]]',    '<a href="dummy/hoge/bar#frag">.*</a>'],
     ['[[ref:c:Hoge#frag]]',        '<a href="dummy/class/Hoge#frag">.*</a>'],
     ['[[ref:m:$~#frag]]',          '<a href="dummy/method/Kernel/v/=7e#frag">.*</a>'],
     ['[[ref:lib:jcode#frag]]',     '<a href="dummy/library/jcode#frag">.*</a>'],
     
     ['[[ref:c:Hoge]]',             'compileerror'],
     ['[[ref:ref:hoge/bar#frag]]',  'compileerror'],
    ].each{|src, expected|
      assert_match /#{expected}/, @c.send(:compile_text, src), src
    }
  end

  def test_array_join
    src = <<'HERE'
--- join(sep = $,)    -> String

@see [[m:Array#*]], [[m:$,]]
HERE
    expected = <<'HERE'
<dt class="method-heading"><code>join(sep = $,) -&gt; String</code></dt>
<dd class="method-description">
<p>
[SEE_ALSO] <a href="dummy/method/Array/i/=2a">Array#*</a>, <a href="dummy/method/Kernel/v/=2c">$,</a>
</p>
</dd>
HERE
    compile_and_assert_equal(expected, src)
  end
end
