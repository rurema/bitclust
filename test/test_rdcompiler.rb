require 'bitclust/rdcompiler'
require 'bitclust/database'
require 'bitclust/methoddatabase'
require 'bitclust/screen'
require 'test/unit'
require 'test/unit/rr'
require 'timeout'

class TestRDCompiler < Test::Unit::TestCase

  def setup
    @dummy = 'dummy'
    @u = BitClust::URLMapper.new(Hash.new{@dummy})
    @db = BitClust::MethodDatabase.dummy("version" => "2.0.0")
    @c = BitClust::RDCompiler.new(@u, 1, {:database => @db})
  end

  def assert_compiled_source(expected, src)
    assert_equal(expected, @c.compile(src))
  end

  def assert_compiled_method_source(expected, src)
    method_entry = Object.new
    mock(method_entry).source{ src }
    mock(method_entry).index_id.any_times{ "dummy" }
    mock(method_entry).defined?.any_times{ true }
    mock(method_entry).id.any_times{ "String/i.index._builtin" }
    assert_equal(expected, @c.compile_method(method_entry))
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
    assert_compiled_source(expected, src)
  end

  def test_dlist_with_empty_line
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
    assert_compiled_source(expected, src)
  end

  def test_dlist_with_emlist
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
    assert_compiled_source(expected, src)
  end

  def test_dlist_with_paragraph
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
    assert_compiled_source(expected, src)
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
    assert_compiled_source(expected, src)

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
    assert_compiled_source(expected, src)
  end

  def test_method
    src = <<'HERE'
--- hoge
foo
bar
 text
HERE
    expected = <<'HERE'
<dt class="method-heading" id="dummy"><code>hoge</code><span class="permalink">[<a href="dummy/method/String/i/index">permalink</a>][<a href="https://docs.ruby-lang.org/en/2.0.0/String.html#method-i-index">rdoc</a>]</span></dt>
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
    assert_compiled_method_source(expected, src)
  end

  def test_method_with_emlist
    src = <<'HERE'
--- <=>

abs
//emlist{
text
//}
HERE
    expected = <<'HERE'
<dt class="method-heading" id="dummy"><code>self &lt;=&gt; </code><span class="permalink">[<a href="dummy/method/String/i/index">permalink</a>][<a href="https://docs.ruby-lang.org/en/2.0.0/String.html#method-i-index">rdoc</a>]</span></dt>
<dd class="method-description">
<p>
abs
</p>
<pre>
text
</pre>
</dd>
HERE
    assert_compiled_method_source(expected, src)
  end

  def test_method_with_dlist
    src = <<'HERE'
--- method

: word1
  dsc
HERE
    expected = <<'HERE'
<dt class="method-heading" id="dummy"><code>method</code><span class="permalink">[<a href="dummy/method/String/i/index">permalink</a>][<a href="https://docs.ruby-lang.org/en/2.0.0/String.html#method-i-index">rdoc</a>]</span></dt>
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
    assert_compiled_method_source(expected, src)
  end

  def test_method_with_tags
    src = <<'HERE'
--- method
dsc

@param hoge dsc
@return dsc

@raise hoge dsc
@see hoge
HERE
    expected = <<'HERE'
<dt class="method-heading" id="dummy"><code>method</code><span class="permalink">[<a href="dummy/method/String/i/index">permalink</a>][<a href="https://docs.ruby-lang.org/en/2.0.0/String.html#method-i-index">rdoc</a>]</span></dt>
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
    assert_compiled_method_source(expected, src)
  end

  def test_method_with_formatted_text
    src = <<'HERE'
--- method

@param arg dsc1

           dsc2
           dsc3
HERE
    expected = <<'HERE'
<dt class="method-heading" id="dummy"><code>method</code><span class="permalink">[<a href="dummy/method/String/i/index">permalink</a>][<a href="https://docs.ruby-lang.org/en/2.0.0/String.html#method-i-index">rdoc</a>]</span></dt>
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
    assert_compiled_method_source(expected, src)
  end

  def test_method_with_param_and_emlist
    src = <<'HERE'
--- method

@param arg dsc1
//emlist{
dsc2
dsc3
//}
HERE
    expected = <<'HERE'
<dt class="method-heading" id="dummy"><code>method</code><span class="permalink">[<a href="dummy/method/String/i/index">permalink</a>][<a href="https://docs.ruby-lang.org/en/2.0.0/String.html#method-i-index">rdoc</a>]</span></dt>
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
    assert_compiled_method_source(expected, src)
  end

  def test_method_with_param_and_emlist_with_caption_and_lang
    src = <<'HERE'
--- method

@param arg dsc1
//emlist[This is caption][ruby]{
dsc2
dsc3
//}
HERE
    expected = <<'HERE'
<dt class="method-heading" id="dummy"><code>method</code><span class="permalink">[<a href="dummy/method/String/i/index">permalink</a>][<a href="https://docs.ruby-lang.org/en/2.0.0/String.html#method-i-index">rdoc</a>]</span></dt>
<dd class="method-description">
<dl>
<dt class='method-param'>[PARAM] arg:</dt>
<dd>
dsc1
<pre class="highlight ruby">
<span class="caption">This is caption</span>
<code>
dsc2
dsc3
</code></pre>
</dd>
</dl>
</dd>
HERE
    assert_compiled_method_source(expected, src)
  end

  def test_method_with_samplecode
    src = <<'HERE'
--- <=>

abs
//emlist[description][ruby]{
puts "text"
//}
HERE
    expected = <<'HERE'
<dt class="method-heading" id="dummy"><code>self &lt;=&gt; </code><span class="permalink">[<a href="dummy/method/String/i/index">permalink</a>][<a href="https://docs.ruby-lang.org/en/2.0.0/String.html#method-i-index">rdoc</a>]</span></dt>
<dd class="method-description">
<p>
abs
</p>
<pre class="highlight ruby">
<span class="caption">description</span>
<code>
<span class="nb">puts</span> <span class="s2">"</span><span class="s2">text</span><span class="s2">"</span>
</code></pre>
</dd>
HERE
    assert_compiled_method_source(expected, src)
  end

  def test_method_with_samplecode_no_caption
    src = <<'HERE'
--- <=>

abs
//emlist[][ruby]{
puts "text"
//}
HERE
    expected = <<'HERE'
<dt class="method-heading" id="dummy"><code>self &lt;=&gt; </code><span class="permalink">[<a href="dummy/method/String/i/index">permalink</a>][<a href="https://docs.ruby-lang.org/en/2.0.0/String.html#method-i-index">rdoc</a>]</span></dt>
<dd class="method-description">
<p>
abs
</p>
<pre class="highlight ruby">
<code>
<span class="nb">puts</span> <span class="s2">"</span><span class="s2">text</span><span class="s2">"</span>
</code></pre>
</dd>
HERE
    assert_compiled_method_source(expected, src)
  end

  def test_method_with_samplecode_singleton_class
    src = <<'HERE'
--- singleton_method(name) -> Method
//emlist[][ruby]{
class <<obj
  def foo
    Object.new
  end
end
class << Object.new
end
class << self
end
class << FOO::BAR::BAZ
end
p Foo.singleton_method(:foo)
//}
end
HERE
  expected = <<'HERE'
<dt class="method-heading" id="dummy"><code>singleton_method(name) -&gt; Method</code><span class="permalink">[<a href="dummy/method/String/i/index">permalink</a>][<a href="https://docs.ruby-lang.org/en/2.0.0/String.html#method-i-index">rdoc</a>]</span></dt>
<dd class="method-description">
<pre class="highlight ruby">
<code>
<span class="k">class</span> <span class="o">&lt;&lt;</span>obj
  <span class="k">def</span> <span class="nf">foo</span>
    <span class="no">Object</span><span class="p">.</span><span class="nf">new</span>
  <span class="k">end</span>
<span class="k">end</span>
<span class="k">class</span> <span class="o">&lt;&lt;</span> <span class="no">Object</span><span class="p">.</span><span class="nf">new</span>
<span class="k">end</span>
<span class="k">class</span> <span class="o">&lt;&lt;</span> <span class="nc">self</span>
<span class="k">end</span>
<span class="k">class</span> <span class="o">&lt;&lt;</span> <span class="no">FOO</span><span class="o">::</span><span class="no">BAR</span><span class="o">::</span><span class="no">BAZ</span>
<span class="k">end</span>
<span class="nb">p</span> <span class="no">Foo</span><span class="p">.</span><span class="nf">singleton_method</span><span class="p">(</span><span class="ss">:foo</span><span class="p">)</span>
</code></pre>
<p>
end
</p>
</dd>
HERE
    assert_compiled_method_source(expected, src)
  end

  def test_method2
    @c = BitClust::RDCompiler.new(@u, 1, {:database => @db, :force => true})
    src = <<'HERE'
--- hoge1
--- hoge2
bar
HERE
    expected = <<'HERE'
<dl>
<dt class="method-heading" id="dummy"><code>hoge1</code><span class="permalink">[<a href="dummy/method/String/i/index">permalink</a>][<a href="https://docs.ruby-lang.org/en/2.0.0/String.html#method-i-index">rdoc</a>]</span></dt>
<dt class="method-heading"><code>hoge2</code></dt>
<dd class="method-description">
<p>
bar
</p>
</dd>
</dl>
HERE
    assert_compiled_method_source(expected, src)
  end

  def test_ulist_simple
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
    assert_compiled_source(expected, src)
  end

  def test_ulist_multiple_list
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
    assert_compiled_source(expected, src)
  end

  def test_ulist_continuous_line
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
    assert_compiled_source(expected, src)

  end

  def test_ulist_nested
    src = <<HERE
  * hoge1
    * fuga1
      bar
  * hoge2
    * fuga2
HERE
    expected = <<HERE
<ul>
<li>hoge1<ul>
<li>fuga1
bar</li>
</ul>
</li>
<li>hoge2<ul>
<li>fuga2</li>
</ul>
</li>
</ul>
HERE
    assert_compiled_source(expected, src)
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
    assert_compiled_source(expected, src)
  end

  def test_olist_nested
    src = <<HERE
  (1) hoge1
    (11) fuga1
  (2) hoge2
    (12) fuga2
HERE
    expected = <<HERE
<ol>
<li>hoge1<ol>
<li>fuga1</li>
</ol>
</li>
<li>hoge2<ol>
<li>fuga2</li>
</ol>
</li>
</ol>
HERE
    assert_compiled_source(expected, src)
  end

  def test_ulist_olist_nested
    src = <<HERE
  * hoge1
    (1) fuga1
    (2) fuga2
  * hoge2
    (1) boo1
    (2) boo2
HERE
    expected = <<HERE
<ul>
<li>hoge1<ol>
<li>fuga1</li>
<li>fuga2</li>
</ol>
</li>
<li>hoge2<ol>
<li>boo1</li>
<li>boo2</li>
</ol>
</li>
</ul>
HERE
    assert_compiled_source(expected, src)
  end

  def test_olist_nested_3level
    src = <<HERE
  (1) hoge1
    (11) fuga1
      (111) boo1
  (2) hoge2
    (22) fuga2
      (222) boo2
HERE
    expected = <<HERE
<ol>
<li>hoge1<ol>
<li>fuga1<ol>
<li>boo1</li>
</ol>
</li>
</ol>
</li>
<li>hoge2<ol>
<li>fuga2<ol>
<li>boo2</li>
</ol>
</li>
</ol>
</li>
</ol>
HERE
    assert_compiled_source(expected, src)
  end

  def test_olist_ulist
    src = <<HERE
  (1) aaa
  (1) bbb
  (1) ccc
    * xxx
    * yyy
HERE
    expected = <<HERE
<ol>
<li>aaa</li>
<li>bbb</li>
<li>ccc<ul>
<li>xxx</li>
<li>yyy</li>
</ul>
</li>
</ol>
HERE
    assert_compiled_source(expected, src)
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

  data("class"               => ['[[c:String]]',      '<a href="dummy/class/String">String</a>'],
       "with garbage"        => ['[[c:String ]]',     '[[c:String ]]'],
       "missing type"        => ['[[String]]',        '[[String]]'],
       "nested class"        => ['[[c:File::Stat]]',  '<a href="dummy/class/File=Stat">File::Stat</a>'],
       "singleton method"    => ['[[m:String.new]]',  '<a href="dummy/method/String/s/new">String.new</a>'],
       "instance method"     => ['[[m:String#dump]]', '<a href="dummy/method/String/i/dump">String#dump</a>'],
       "indexer"             => ['[[m:String#[] ]]',  '<a href="dummy/method/String/i/=5b=5d">String#[]</a>'],
       "C API"               => ['[[f:rb_ary_new3]]', '<a href="dummy/function/rb_ary_new3">rb_ary_new3</a>'],
       "C API root"          => ['[[f:/]]',           '<a href="dummy/function/">All C API</a>'],
       "C API index"         => ['[[f:_index]]',      '<a href="dummy/function/">All C API</a>'],
       "standard library"    => ['[[lib:jcode]]',     '<a href="dummy/library/jcode">jcode</a>'],
       "man command"         => ['[[man:tr(1)]]',     '<a class="external" href="http://www.opengroup.org/onlinepubs/009695399/utilities/tr.html">tr(1)</a>'],
       "man header"          => ['[[man:sys/socket.h(header)]]', '<a class="external" href="http://www.opengroup.org/onlinepubs/009695399/basedefs/sys/socket.h.html">sys/socket.h(header)</a>'],
       "man system call"     => ['[[man:fopen(3linux)]]', '<a class="external" href="http://man7.org/linux/man-pages/man3/fopen.3.html">fopen(3linux)</a>'],
       "RFC"                 => ['[[RFC:2822]]',      '<a class="external" href="https://tools.ietf.org/html/rfc2822">[RFC2822]</a>'],
       "special var $~"      => ['[[m:$~]]',          '<a href="dummy/method/Kernel/v/=7e">$~</a>'],
       "special var $,"      => ['[[m:$,]]',          '<a href="dummy/method/Kernel/v/=2c">$,</a>'],
       "extra close bracket" => ['[[c:String]]]', '<a href="dummy/class/String">String</a>]'],
       "continuity"          => ['[[c:String]][[c:String]]', '<a href="dummy/class/String">String</a><a href="dummy/class/String">String</a>'],
       "constant"            => ['[[m:File::SEPARATOR]]', '<a href="dummy/method/File/c/SEPARATOR">File::SEPARATOR</a>'],
       "url"                 => ['[[url:http://i.loveruby.net]]', '<a class="external" href="http://i.loveruby.net">http://i.loveruby.net</a>'],
       "ruby-list"           => ['[[ruby-list:12345]]', '<a class="external" href="https://blade.ruby-lang.org/ruby-list/12345">[ruby-list:12345]</a>'],
       "bugs.r-l.o feature"  => ['[[feature:12345]]', '<a class="external" href="https://bugs.ruby-lang.org/issues/12345">[feature#12345]</a>'],
       "bugs.r-l.o bug"      => ['[[bug:12345]]', '<a class="external" href="https://bugs.ruby-lang.org/issues/12345">[bug#12345]</a>'],
       "bugs.r-l.o misc"     => ['[[misc:12345]]', '<a class="external" href="https://bugs.ruby-lang.org/issues/12345">[misc#12345]</a>'])
  def test_bracket_link(data)
    target, expected = data
    assert_equal(expected, @c.send(:compile_text, target), target)
  end

  data("doc"             => ['[[d:hoge/bar]]',            '<a href="dummy/hoge/bar">.*</a>'],
       "ref doc"         => ['[[ref:d:hoge/bar#frag]]',   '<a href="dummy/hoge/bar#frag">.*</a>'],
       "ref class"       => ['[[ref:c:Hoge#frag]]',       '<a href="dummy/class/Hoge#frag">.*</a>'],
       "ref special var" => ['[[ref:m:$~#frag]]',         '<a href="dummy/method/Kernel/v/=7e#frag">.*</a>'],
       "ref library"     => ['[[ref:lib:jcode#frag]]',    '<a href="dummy/library/jcode#frag">.*</a>'],
       "ref class error" => ['[[ref:c:Hoge]]',            'compileerror'],
       "ref ref"         => ['[[ref:ref:hoge/bar#frag]]', 'compileerror'],)
  def test_bracket_link_doc(data)
    target, expected = data
    assert_match(/#{expected}/, @c.send(:compile_text, target), target)
  end

  def test_array_join
    src = <<'HERE'
--- join(sep = $,)    -> String

@see [[m:Array#*]], [[m:$,]]
HERE
    expected = <<'HERE'
<dt class="method-heading" id="dummy"><code>join(sep = $,) -&gt; String</code><span class="permalink">[<a href="dummy/method/String/i/index">permalink</a>][<a href="https://docs.ruby-lang.org/en/2.0.0/String.html#method-i-index">rdoc</a>]</span></dt>
<dd class="method-description">
<p>
[SEE_ALSO] <a href="dummy/method/Array/i/=2a">Array#*</a>, <a href="dummy/method/Kernel/v/=2c">$,</a>
</p>
</dd>
HERE
    assert_compiled_method_source(expected, src)
  end

  def test_todo
    src = <<'HERE'
--- puts(str)    -> String
@todo

description
HERE
    expected = <<'HERE'
<dt class="method-heading" id="dummy"><code>puts(str) -&gt; String</code><span class="permalink">[<a href="dummy/method/String/i/index">permalink</a>][<a href="https://docs.ruby-lang.org/en/2.0.0/String.html#method-i-index">rdoc</a>]</span></dt>
<dd class="method-description">
<p class="todo">
[TODO]
</p>
<p>
description
</p>
</dd>
HERE
    assert_compiled_method_source(expected, src)
  end

  def test_todo_with_comment
    src = <<'HERE'
--- puts(str)    -> String
@todo 1.9.2

description
HERE
    expected = <<'HERE'
<dt class="method-heading" id="dummy"><code>puts(str) -&gt; String</code><span class="permalink">[<a href="dummy/method/String/i/index">permalink</a>][<a href="https://docs.ruby-lang.org/en/2.0.0/String.html#method-i-index">rdoc</a>]</span></dt>
<dd class="method-description">
<p class="todo">
[TODO] 1.9.2
</p>
<p>
description
</p>
</dd>
HERE
    assert_compiled_method_source(expected, src)
  end


  class BitClust::RDCompiler; public :man_url; end

  data("tr(1)" => {
         :params => ["1", "tr"],
         :expected => "http://www.opengroup.org/onlinepubs/009695399/utilities/tr.html"
       },
       "fopen(3)" => {
         :params => ["3", "fopen"],
         :expected => "http://www.opengroup.org/onlinepubs/009695399/functions/fopen.html"
       },
       "sys/socket.h(header)" => {
         :params => ["header", "sys/socket.h"],
         :expected => "http://www.opengroup.org/onlinepubs/009695399/basedefs/sys/socket.h.html"
       },
       "fopen(3linux)" => {
         :params => ["3linux", "fopen"],
         :expected => "http://man7.org/linux/man-pages/man3/fopen.3.html"
       },
       "fopen(3freebsd)" => {
         :params => ["3freebsd", "fopen"],
         :expected => "http://www.freebsd.org/cgi/man.cgi?query=fopen&sektion=3&manpath=FreeBSD+9.0-RELEASE"
       },
       "tr(foo)" => {
         :params => ["foo", "tr"],
         :expected => nil
       })
  def test_man_url(data)
    assert_equal(data[:expected], @c.man_url(*data[:params]))
  end

  class BitClust::RDCompiler; public :rdoc_url; end
  data("String#index" => {
          :method_id => "String/i.index._builtin",
          :version   => "2.0.0",
          :expected  => "https://docs.ruby-lang.org/en/2.0.0/String.html#method-i-index"
       },
       "String.new" => {
          :method_id => "String/s.new._builtin",
          :version   => "2.0.0",
          :expected  => "https://docs.ruby-lang.org/en/2.0.0/String.html#method-c-new"
       },
       "String#<=>" => {
          :method_id => "String/i.=3c=3d=3e._builtin",
          :version   => "2.0.0",
          :expected  => "https://docs.ruby-lang.org/en/2.0.0/String.html#method-i-3C-3D-3E"
       },
       "String#empty?" => {
          :method_id => "String/i.empty=3f._builtin",
          :version   => "2.0.0",
          :expected  => "https://docs.ruby-lang.org/en/2.0.0/String.html#method-i-empty-3F"
       },
       "String#index v1.9.3" => {
          :method_id => "String/i.index._builtin",
          :version   => "1.9.3",
          :expected  => "https://docs.ruby-lang.org/en/1.9.3/String.html#method-i-index"
       },
       "String#index v1.8.7" => {
          :method_id => "String/i.index._builtin",
          :version   => "1.8.7",
          :expected  => "https://docs.ruby-lang.org/en/1.8.7/String.html#method-i-index"
       },
       "File::Stat#file?" => {
          :method_id => "File=Stat/i.file=3f._builtin",
          :version   => "2.0.0",
          :expected  => "https://docs.ruby-lang.org/en/2.0.0/File/Stat.html#method-i-file-3F"
       },
       "Net::HTTP#get" => {
          :method_id => "Net=HTTP/i.get.net.http",
          :version   => "2.0.0",
          :expected  => "https://docs.ruby-lang.org/en/2.0.0/Net/HTTP.html#method-i-get"
       },
       "ARGF.class#binmode" => {
          :method_id => "ARGF.class/i.binmode.argf._builtin",
          :version   => "2.0.0",
          :expected  => "https://docs.ruby-lang.org/en/2.0.0/ARGF.html#method-i-binmode"
       })
  def test_rdoc_url(data)
    assert_equal(data[:expected], @c.rdoc_url(data[:method_id], data[:version]))
  end

  class BitClust::RDCompiler; public :rdoc_link; end
  data("String#index" => {
          :method_id => "String/i.index._builtin",
          :version   => "2.0.0",
          :expected  => %Q(<a href="https://docs.ruby-lang.org/en/2.0.0/String.html#method-i-index">rdoc</a>)
       })
  def test_rdoc_link(data)
    assert_equal(data[:expected], @c.rdoc_link(data[:method_id], data[:version]))
  end

  def test_paragraph_with_single_line
    source = <<~SOURCE
      a
    SOURCE
    expected = <<~HTML
      <p>
      a
      </p>
    HTML
    assert_equal(
      expected,
      @c.compile(source)
    )
  end

  def test_paragraph_with_newline_between_ascii_and_ascii
    source = <<~SOURCE
      a
      a
    SOURCE
    expected = <<~HTML
      <p>
      a
      a
      </p>
    HTML
    assert_equal(
      expected,
      @c.compile(source)
    )
  end

  def test_paragraph_with_newline_between_ascii_and_non_ascii
    source = <<~SOURCE
      a
      あ
    SOURCE
    expected = <<~HTML
      <p>
      a
      あ
      </p>
    HTML
    assert_equal(
      expected,
      @c.compile(source)
    )
  end

  def test_paragraph_with_newline_between_non_ascii_and_ascii
    source = <<~SOURCE
      あ
      a
    SOURCE
    expected = <<~HTML
      <p>
      あ
      a
      </p>
    HTML
    assert_equal(
      expected,
      @c.compile(source)
    )
  end

  def test_paragraph_with_newline_between_non_ascii_and_non_ascii
    source = <<~SOURCE
      あ
      あ
    SOURCE
    expected = <<~HTML
      <p>
      ああ
      </p>
    HTML
    assert_equal(
      expected,
      @c.compile(source)
    )
  end

  def test_definition_list_with_ascii
    source = <<~SOURCE
      : b
        あ
        あ
    SOURCE
    expected = <<~HTML
      <dl>
      <dt>b</dt>
      <dd>
      <p>
      ああ
      </p>
      </dd>
      </dl>
    HTML
    assert_equal(
      expected,
      @c.compile(source)
    )
  end

  def test_definition_list_with_non_ascii
    source = <<~SOURCE
      : b
        a
        a
    SOURCE
    expected = <<~HTML
      <dl>
      <dt>b</dt>
      <dd>
      <p>
      a
      a
      </p>
      </dd>
      </dl>
    HTML
    assert_equal(
      expected,
      @c.compile(source)
    )
  end

  def test_entry_info_with_ascii
    source = <<~SOURCE
      --- b

      @param arg あ
        あ
    SOURCE
    expected = <<~HTML
      <dt class="method-heading" id="dummy"><code>b</code><span class="permalink">[<a href="dummy/method/String/i/index">permalink</a>][<a href="https://docs.ruby-lang.org/en/2.0.0/String.html#method-i-index">rdoc</a>]</span></dt>
      <dd class="method-description">
      <dl>
      <dt class='method-param'>[PARAM] arg:</dt>
      <dd>
      ああ
      </dd>
      </dl>
      </dd>
    HTML
    assert_compiled_method_source(expected, source)
  end

  def test_entry_info_with_non_ascii
    source = <<~SOURCE
      --- b
      @param arg a
        a
    SOURCE
    expected = <<~HTML
      <dt class="method-heading" id="dummy"><code>b</code><span class="permalink">[<a href="dummy/method/String/i/index">permalink</a>][<a href="https://docs.ruby-lang.org/en/2.0.0/String.html#method-i-index">rdoc</a>]</span></dt>
      <dd class="method-description">
      <dl>
      <dt class='method-param'>[PARAM] arg:</dt>
      <dd>
      a
      a
      </dd>
      </dl>
      </dd>
    HTML
    assert_compiled_method_source(expected, source)
  end

  def test_entry_paragraph_with_ascii
    source = <<~SOURCE
      --- b
      あ
      あ
    SOURCE
    expected = <<~HTML
      <dt class="method-heading" id="dummy"><code>b</code><span class="permalink">[<a href="dummy/method/String/i/index">permalink</a>][<a href="https://docs.ruby-lang.org/en/2.0.0/String.html#method-i-index">rdoc</a>]</span></dt>
      <dd class="method-description">
      <p>
      ああ
      </p>
      </dd>
    HTML
    assert_compiled_method_source(expected, source)
  end

  def test_entry_paragraph_with_non_ascii
    source = <<~SOURCE
      --- b
      a
      a
    SOURCE
    expected = <<~HTML
      <dt class="method-heading" id="dummy"><code>b</code><span class="permalink">[<a href="dummy/method/String/i/index">permalink</a>][<a href="https://docs.ruby-lang.org/en/2.0.0/String.html#method-i-index">rdoc</a>]</span></dt>
      <dd class="method-description">
      <p>
      a
      a
      </p>
      </dd>
    HTML
    assert_compiled_method_source(expected, source)
  end

  def test_entry_see_with_ascii
    source = <<~SOURCE
      --- b
      @see あ
        あ
    SOURCE
    expected = <<~HTML
      <dt class="method-heading" id="dummy"><code>b</code><span class="permalink">[<a href="dummy/method/String/i/index">permalink</a>][<a href="https://docs.ruby-lang.org/en/2.0.0/String.html#method-i-index">rdoc</a>]</span></dt>
      <dd class="method-description">
      <p>
      [SEE_ALSO] ああ
      </p>
      </dd>
    HTML
    assert_compiled_method_source(expected, source)
  end

  def test_entry_see_with_non_ascii
    source = <<~SOURCE
      --- b
      @see a
        a
    SOURCE
    expected = <<~HTML
      <dt class="method-heading" id="dummy"><code>b</code><span class="permalink">[<a href="dummy/method/String/i/index">permalink</a>][<a href="https://docs.ruby-lang.org/en/2.0.0/String.html#method-i-index">rdoc</a>]</span></dt>
      <dd class="method-description">
      <p>
      [SEE_ALSO] a
      a
      </p>
      </dd>
    HTML
    assert_compiled_method_source(expected, source)
  end
end
