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
<dt class="method-heading" id="dummy"><code>hoge</code><span class="permalink">[<a href="dummy/method/String/i/index">permalink</a>]</span></dt>
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
<dt class="method-heading" id="dummy"><code>self &lt;=&gt; </code><span class="permalink">[<a href="dummy/method/String/i/index">permalink</a>]</span></dt>
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
<dt class="method-heading" id="dummy"><code>method</code><span class="permalink">[<a href="dummy/method/String/i/index">permalink</a>]</span></dt>
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
<dt class="method-heading" id="dummy"><code>method</code><span class="permalink">[<a href="dummy/method/String/i/index">permalink</a>]</span></dt>
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
<dt class="method-heading" id="dummy"><code>method</code><span class="permalink">[<a href="dummy/method/String/i/index">permalink</a>]</span></dt>
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
<dt class="method-heading" id="dummy"><code>method</code><span class="permalink">[<a href="dummy/method/String/i/index">permalink</a>]</span></dt>
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

  def test_method2
    @c = BitClust::RDCompiler.new(@u, 1, {:force => true})
    src = <<'HERE'
--- hoge1
--- hoge2
bar
HERE
    expected = <<'HERE'
<dl>
<dt class="method-heading" id="dummy"><code>hoge1</code><span class="permalink">[<a href="dummy/method/String/i/index">permalink</a>]</span></dt>
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
    assert_compiled_source(expected, src)

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
       "RFC"                 => ['[[RFC:2822]]',      '<a class="external" href="http://www.ietf.org/rfc/rfc2822.txt">[RFC2822]</a>'],
       "special var $~"      => ['[[m:$~]]',          '<a href="dummy/method/Kernel/v/=7e">$~</a>'],
       "special var $,"      => ['[[m:$,]]',          '<a href="dummy/method/Kernel/v/=2c">$,</a>'],
       "extra close bracket" => ['[[c:String]]]', '<a href="dummy/class/String">String</a>]'],
       "continuity"          => ['[[c:String]][[c:String]]', '<a href="dummy/class/String">String</a><a href="dummy/class/String">String</a>'],
       "constant"            => ['[[m:File::SEPARATOR]]', '<a href="dummy/method/File/c/SEPARATOR">File::SEPARATOR</a>'],
       "url"                 => ['[[url:http://i.loveruby.net]]', '<a class="external" href="http://i.loveruby.net">http://i.loveruby.net</a>'],
       "ruby-list"           => ['[[ruby-list:12345]]', '<a class="external" href="http://blade.nagaokaut.ac.jp/cgi-bin/scat.rb/ruby/ruby-list/12345">[ruby-list:12345]</a>'],)
  def test_bracket_link(data)
    target, expected = data
    assert_equal(expected, @c.send(:compile_text, target), target)
  end

  data("doc"             => ['[[d:hoge/bar]]',            '<a href="dummy/hoge/bar">.*</a>'],
       "ref doc"         => ['[[ref:d:hoge/bar#frag]]',   '<a href="dummy/hoge/bar#frag">.*</a>'],
       "ref class"       => ['[[ref:c:Hoge#frag]]',       '<a href="dummy/class/Hoge#frag">.*</a>'],
       "ref special var" => ['[[ref:m:$~#frag]]',         '<a href="dummy/method/Kernel/v/=7e#frag">.*</a>'],
       "ref library"     => ['[[ref:lib:jcode#frag]]',    '<a href="dummy/library/jcode#frag">.*</a>'],
       "ref class"       => ['[[ref:c:Hoge]]',            'compileerror'],
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
<dt class="method-heading" id="dummy"><code>join(sep = $,) -&gt; String</code><span class="permalink">[<a href="dummy/method/String/i/index">permalink</a>]</span></dt>
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
<dt class="method-heading" id="dummy"><code>puts(str) -&gt; String</code><span class="permalink">[<a href="dummy/method/String/i/index">permalink</a>]</span></dt>
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
<dt class="method-heading" id="dummy"><code>puts(str) -&gt; String</code><span class="permalink">[<a href="dummy/method/String/i/index">permalink</a>]</span></dt>
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
end
