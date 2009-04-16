require 'test/unit'
require 'bitclust/nameutils'

class TestNameUtils < Test::Unit::TestCase

  include BitClust::NameUtils

  def test_libname?
    assert_equal true, libname?("_builtin")
    assert_equal true, libname?("fileutils")
    assert_equal true, libname?("socket")
    assert_equal true, libname?("open-uri")
    assert_equal true, libname?("net/http")
    assert_equal true, libname?("racc/cparse")
    assert_equal true, libname?("test/unit/testcase")
    assert_equal false, libname?("")
    assert_equal false, libname?("fileutils ")
    assert_equal false, libname?(" fileutils")
    assert_equal false, libname?("file utils")
    assert_equal false, libname?("fileutils\n")
    assert_equal false, libname?("fileutils\t")
    assert_equal false, libname?("fileutils.rb")
    assert_equal false, libname?("English.rb")
    assert_equal false, libname?("socket.so")
    assert_equal false, libname?("net/http.rb")
    assert_equal false, libname?("racc/cparse.so")
  end

  def test_libname2id
    assert_equal "_builtin", libname2id("_builtin")
    assert_equal "fileutils", libname2id("fileutils")
    assert_equal "socket", libname2id("socket")
    assert_equal "English", libname2id("English")
    assert_equal "open=2duri", libname2id("open-uri")
    assert_equal "net.http", libname2id("net/http")
    assert_equal "racc.cparse", libname2id("racc/cparse")
    assert_equal "test.unit.testcase", libname2id("test/unit/testcase")
  end

  def test_libid2name
    assert_equal "_builtin", libid2name("_builtin")
    assert_equal "fileutils", libid2name("fileutils")
    assert_equal "socket", libid2name("socket")
    assert_equal "English", libid2name("English")
    assert_equal "open-uri", libid2name("open=2duri")
    assert_equal "net/http", libid2name("net.http")
    assert_equal "racc/cparse", libid2name("racc.cparse")
    assert_equal "test/unit/testcase", libid2name("test.unit.testcase")
  end

  def test_classname?
    assert_equal true, classname?("fatal")
    assert_equal true, classname?("Array")
    assert_equal true, classname?("String")
    assert_equal true, classname?("Net::HTTP")
    assert_equal true, classname?("Test::Unit::TestCase")
    assert_equal false, classname?("")
    assert_equal false, classname?("Array ")
    assert_equal false, classname?(" Array")
    assert_equal false, classname?("Test Case")
    assert_equal false, classname?("TestCase\n")
    assert_equal false, classname?("\tTestCase")
    assert_equal false, classname?("string")
    assert_equal false, classname?("stringScanner")
    assert_equal false, classname?("net/http")
    assert_equal false, classname?("net.http")
    assert_equal false, classname?("open-uri")
  end

  def test_classname2id
    assert_equal "Array", classname2id("Array")
    assert_equal "String", classname2id("String")
    assert_equal "Net=HTTP", classname2id("Net::HTTP")
    assert_equal "Test=Unit=TestCase", classname2id("Test::Unit::TestCase")
  end

  def test_classid2name
    assert_equal "Array", classid2name("Array")
    assert_equal "String", classid2name("String")
    assert_equal "Net::HTTP", classid2name("Net=HTTP")
    assert_equal "Test::Unit::TestCase", classid2name("Test=Unit=TestCase")
  end

  def test_method_spec?
    assert_equal true, method_spec?("String#index")
    assert_equal true, method_spec?("CGI#accept")
    assert_equal true, method_spec?("Net::HTTP#ca_path")
    assert_equal true, method_spec?("FileUtils.#cp")
  end

  def test_methodid2spec
    assert_equal "String#index", methodid2specstring("String/i.index._builtin")
    assert_equal "CGI#accept", methodid2specstring("CGI/i.accept.cgi")
    assert_equal "Net::HTTP#ca_path", methodid2specstring("Net=HTTP/i.ca_path.net.http")
    assert_equal "FileUtils.#cp", methodid2specstring("FileUtils/m.cp.fileutils")
  end

  def test_methodid2libid
    assert_equal "_builtin",   methodid2libid("String/i.index._builtin")
    assert_equal "cgi",        methodid2libid("CGI/i.accept.cgi")
    assert_equal "net.http",   methodid2libid("Net=HTTP/i.ca_path.net.http")
    assert_equal "open=2duri", methodid2libid("OpenURI/m.open.open=2duri")
  end

  def test_methodid2classid
    assert_equal "String", methodid2classid("String/i.index._builtin")
    assert_equal "CGI", methodid2classid("CGI/i.accept.cgi")
    assert_equal "Net=HTTP", methodid2classid("Net=HTTP/i.ca_path.net.http")
  end

  def test_methodid2typename
    assert_equal :instance_method, methodid2typename("String/i.index._builtin")
    assert_equal :instance_method, methodid2typename("CGI/i.accept.cgi")
    assert_equal :instance_method, methodid2typename("Net=HTTP/i.ca_path.net.http")
    assert_equal :singleton_method, methodid2typename("String/s.new._builtin")
  end

  def test_methodid2mname
    assert_equal "index", methodid2mname("String/i.index._builtin")
    assert_equal "accept", methodid2mname("CGI/i.accept.cgi")
    assert_equal "ca_path", methodid2mname("Net=HTTP/i.ca_path.net.http")
  end

  def test_methodname?
    assert_equal true, methodname?("index")
    assert_equal true, methodname?("accept")
    assert_equal true, methodname?("get")
    assert_equal true, methodname?("Array")
    assert_equal true, methodname?("getIndex")
    assert_equal true, methodname?("PROXY")
    assert_equal true, methodname?("HTTP_PROXY")
    assert_equal true, methodname?("gsub!")
    assert_equal true, methodname?("empty?")
    assert_equal true, methodname?("instance_eval")
    assert_equal true, methodname?("__send")
    assert_equal true, methodname?("__send__")
    assert_equal true, methodname?("__send!")
    assert_equal true, methodname?("+")
    assert_equal true, methodname?("-")
    assert_equal true, methodname?("*")
    assert_equal true, methodname?("/")
    assert_equal true, methodname?("&")
    assert_equal true, methodname?("|")
    assert_equal true, methodname?("^")
    assert_equal true, methodname?("`")
    assert_equal true, methodname?(">>")
    assert_equal true, methodname?("<<")
    assert_equal true, methodname?("+@")
    assert_equal true, methodname?("-@")
    assert_equal true, methodname?("!")
    assert_equal true, methodname?("!@")
    assert_equal true, methodname?("~")
    assert_equal true, methodname?("**")
    assert_equal true, methodname?("<")
    assert_equal true, methodname?(">")
    assert_equal true, methodname?("<=")
    assert_equal true, methodname?(">=")
    assert_equal true, methodname?("==")
    assert_equal true, methodname?("===")
    assert_equal true, methodname?("=~")
    assert_equal true, methodname?("[]")
    assert_equal true, methodname?("[]=")

    assert_equal false, methodname?("")
    assert_equal true,  methodname?("!=")
    assert_equal false, methodname?("!~")
    assert_equal false, methodname?("&&")
    assert_equal false, methodname?("||")
    assert_equal false, methodname?("++")
    assert_equal false, methodname?(">>>")
    assert_equal false, methodname?("***")
    assert_equal false, methodname?("====")
    assert_equal false, methodname?("#accept")
    assert_equal false, methodname?(".new")
    assert_equal false, methodname?(".#cp")
    assert_equal false, methodname?("$gvar")
    assert_equal false, methodname?("CGI#accept")
    assert_equal false, methodname?("String.new")
    assert_equal false, methodname?("Net::HTTP.get")
    assert_equal false, methodname?("Net::HTTP.new")
  end

  def test_build_method_id
    assert_equal "String/i.index._builtin",
        build_method_id("_builtin", "String", :instance_method, "index")
  end

  # library private
  #def test_split_method_id
  #  assert_equal ["String", "i", "index", "_builtin"],
  #               split_method_id("String/i.index._builtin")
  #end

  def test_typename?
    assert_equal true, typename?(:instance_method)
    assert_equal true, typename?(:singleton_method)
    assert_equal true, typename?(:module_function)
    assert_equal true, typename?(:constant)
    assert_equal true, typename?(:special_variable)
    assert_equal false, typename?(:instance_eval)
    assert_equal false, typename?(:instance)
    assert_equal false, typename?(:singleton)
    assert_equal false, typename?("i")
    assert_equal false, typename?("s")
    assert_equal false, typename?(:i)
    assert_equal false, typename?(:s)
  end

  def test_typemark?
    assert_equal true, typemark?('.')
    assert_equal true, typemark?('#')
    assert_equal true, typemark?('.#')
    assert_equal true, typemark?('$')
    assert_equal true, typemark?('::')
    #marks = (0..255).map {|a| (0..255).map {|b| a.chr + b.chr } }.flatten
    marks = (0..127).map {|a| (0..127).map {|b| a.chr + b.chr } }.flatten
    (marks - %w( . # .# $ :: )).each do |m|
      assert_equal false, typemark?(m)
    end
  end

  def test_typechar?
    typechars = %w( i s m c v )
    typechars.each do |c|
      assert_equal true, typechar?(c)
    end
    ((0..255).map {|b| b.chr } - typechars).each do |c|
      assert_equal false, typechar?(c)
    end
  end

  def test_typename2char
    assert_equal 's', typename2char(:singleton_method)
    assert_equal 'i', typename2char(:instance_method)
    assert_equal 'm', typename2char(:module_function)
    assert_equal 'c', typename2char(:constant)
    assert_equal 'v', typename2char(:special_variable)
  end

  def test_typechar2name
    assert_equal :singleton_method, typechar2name('s')
    assert_equal :instance_method,  typechar2name('i')
    assert_equal :module_function,  typechar2name('m')
    assert_equal :constant,         typechar2name('c')
    assert_equal :special_variable, typechar2name('v')
  end

  def test_typemark2char
    assert_equal 's',  typemark2char('.')
    assert_equal 'i',  typemark2char('#')
    assert_equal 'm',  typemark2char('.#')
    assert_equal 'c',  typemark2char('::')
    assert_equal 'v',  typemark2char('$')
  end

  def test_typechar2mark
    assert_equal '.',   typechar2mark('s')
    assert_equal '#',   typechar2mark('i')
    assert_equal '.#',  typechar2mark('m')
    assert_equal '::',  typechar2mark('c')
    assert_equal '$',   typechar2mark('v')
  end

  def test_encodename_url
    assert_equal "Array",      encodename_url("Array")
    assert_equal "String",     encodename_url("String")
    assert_equal "index",      encodename_url("index")
    assert_equal "=2a",        encodename_url("*")
    assert_equal "=2a=2a",     encodename_url("**")
    assert_equal "open=2duri", encodename_url("open-uri")
    assert_equal "net=2ehttp", encodename_url("net.http")
  end

  def test_decodename_url
    assert_equal "Array",      decodename_url("Array")
    assert_equal "String",     decodename_url("String")
    assert_equal "index",      decodename_url("index")
    assert_equal "*",          decodename_url("=2a")
    assert_equal "**",         decodename_url("=2a=2a")
    assert_equal "open-uri",   decodename_url("open=2duri")
    assert_equal "net.http",   decodename_url("net=2ehttp")
  end

  def test_encodeid
    assert_equal "-array",        encodeid("Array")
    assert_equal "-string",       encodeid("String")
    assert_equal "-c-g-i",        encodeid("CGI")
    assert_equal "=2a",           encodeid("=2a")
    assert_equal "=2a=2a",        encodeid("=2a=2a")
    assert_equal "open=2duri",    encodeid("open=2duri")
    assert_equal "-net=-h-t-t-p", encodeid("Net=HTTP")
  end

  def test_decodeid
    assert_equal "Array",      decodeid("-array")
    assert_equal "String",     decodeid("-string")
    assert_equal "CGI",        decodeid("-c-g-i")
    assert_equal "=2a",        decodeid("=2a")
    assert_equal "=2a=2a",     decodeid("=2a=2a")
    assert_equal "open=2duri", decodeid("open=2duri")
    assert_equal "Net=HTTP",   decodeid("-net=-h-t-t-p")
  end

  def test_encodename_fs
    assert_equal "-array",     encodename_fs("Array")
    assert_equal "-string",    encodename_fs("String")
    assert_equal "index",      encodename_fs("index")
    assert_equal "=2a",        encodename_fs("*")
    assert_equal "=2a=2a",     encodename_fs("**")
    assert_equal "open=2duri", encodename_fs("open-uri")
    assert_equal "net=2ehttp", encodename_fs("net.http")
  end

  def test_decodename_fs
    assert_equal "Array",      decodename_fs("-array")
    assert_equal "String",     decodename_fs("-string")
    assert_equal "index",      decodename_fs("index")
    assert_equal "*",          decodename_fs("=2a")
    assert_equal "**",         decodename_fs("=2a=2a")
    assert_equal "open-uri",   decodename_fs("open=2duri")
    assert_equal "net.http",   decodename_fs("net=2ehttp")
  end

end
