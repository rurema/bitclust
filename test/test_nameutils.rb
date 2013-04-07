require 'test/unit'
require 'bitclust/nameutils'

class TestNameUtils < Test::Unit::TestCase

  include BitClust::NameUtils

  data("_builtin"                       => [true, "_builtin"],
       "fileutils"                      => [true, "fileutils"],
       "socket"                         => [true, "socket"],
       "open-uri"                       => [true, "open-uri"],
       "net/http"                       => [true, "net/http"],
       "racc/cparse"                    => [true, "racc/cparse"],
       "test/unit/testcase"             => [true, "test/unit/testcase"],
       "empty string"                   => [false, ""],
       "following space"                => [false, "fileutils "],
       "leading space"                  => [false, " fileutils"],
       "split by space"                 => [false, "file utils"],
       "following new line"             => [false, "fileutils\n"],
       "folowing tab"                   => [false, "fileutils\t"],
       "with extension .rb"             => [false, "fileutils.rb"],
       "CamelCase with extension .rb"   => [false, "English.rb"],
       "with extension .so"             => [false, "socket.so"],
       "sub library with extension .rb" => [false, "net/http.rb"],
       "sub library with extension .so" => [false, "racc/cparse.so"])
  def test_libname?(data)
    expected, target = data
    assert_equal(expected, libname?(target))
  end

  data("_builtin"           => ["_builtin",           "_builtin"],
       "fileutils"          => ["fileutils",          "fileutils"],
       "socket"             => ["socket",             "socket"],
       "English"            => ["English",            "English"],
       "open-uri"           => ["open=2duri",         "open-uri"],
       "net/http"           => ["net.http",           "net/http"],
       "racc/cparse"        => ["racc.cparse",        "racc/cparse"],
       "test/unit/testcase" => ["test.unit.testcase", "test/unit/testcase"])
  def test_libname2id(data)
    expected, target = data
    assert_equal(expected, libname2id(target))
  end

  data("_builtin"           => ["_builtin",           "_builtin"],
       "fileutils"          => ["fileutils",          "fileutils"],
       "socket"             => ["socket",             "socket"],
       "English"            => ["English",            "English"],
       "open=2duri"         => ["open-uri",           "open=2duri"],
       "net.http"           => ["net/http",           "net.http"],
       "racc.cparse"        => ["racc/cparse",        "racc.cparse"],
       "test.unit.testcase" => ["test/unit/testcase", "test.unit.testcase"])
  def test_libid2name(data)
    expected, target = data
    assert_equal(expected, libid2name(target))
  end

  data("fatal"                => [true,  "fatal"],
       "Array"                => [true,  "Array"],
       "String"               => [true,  "String"],
       "Net::HTTP"            => [true,  "Net::HTTP"],
       "Test::Unit::TestCase" => [true,  "Test::Unit::TestCase"],
       "ARGF.class"           => [true,  "ARGF.class"],
       "Complex::compatible"  => [true,  "Complex::compatible"],
       "empty string"         => [false, ""],
       "following space"      => [false, "Array "],
       "leading space"        => [false, " Array"],
       "split by space"       => [false, "Test Case"],
       "following new line"   => [false, "TestCase\n"],
       "leading tab"          => [false, "\tTestCase"],
       "small case"           => [false, "string"],
       "camelCase"            => [false, "stringScanner"],
       "libname"              => [false, "net/http"],
       "libid"                => [false, "net.http"],
       "libname with '-'"     => [false, "open-uri"])
  def test_classname?(data)
    expected, target = data
    assert_equal(expected, classname?(target))
  end

  data("Array"                => ["Array",              "Array"],
       "String"               => ["String",             "String"],
       "Net::HTTP"            => ["Net=HTTP",           "Net::HTTP"],
       "Test::Unit::TestCase" => ["Test=Unit=TestCase", "Test::Unit::TestCase"],
       "ARGF.class"           => ["ARGF.class",         "ARGF.class"],
       "Complex::compatible"  => ["Complex=compatible", "Complex::compatible"])
  def test_classname2id(data)
    expected, target = data
    assert_equal(expected, classname2id(target))
  end

  data("Array"              => ["Array",                "Array"],
       "String"             => ["String",               "String"],
       "Net=HTTP"           => ["Net::HTTP",            "Net=HTTP"],
       "Test=Unit=TestCase" => ["Test::Unit::TestCase", "Test=Unit=TestCase"],
       "ARGF.class"         => ["ARGF.class",           "ARGF.class"],
       "Complex=compatible" => ["Complex::compatible",  "Complex=compatible"])
  def test_classid2name(data)
    expected, target = data
    assert_equal(expected, classid2name(target))
  end

  data("String#index"      => [true, "String#index"],
       "CGI#accept"        => [true, "CGI#accept"],
       "Net::HTTP#ca_path" => [true, "Net::HTTP#ca_path"],
       "FileUtils.#cp"     => [true, "FileUtils.#cp"],
       "ARGF.class#path"   => [true, "ARGF.class#path"],
       "ARGF.class"        => [false, "ARGF.class"])
  def test_method_spec?(data)
    expected, target = data
    assert_equal(expected, method_spec?(target))
  end

  data("String/i.index._builtin"     => ["String#index",      "String/i.index._builtin"],
       "CGI/i.accept.cgi"            => ["CGI#accept",        "CGI/i.accept.cgi"],
       "Net=HTTP/i.ca_path.net.http" => ["Net::HTTP#ca_path", "Net=HTTP/i.ca_path.net.http"],
       "FileUtils/m.cp.fileutils"    => ["FileUtils.#cp",     "FileUtils/m.cp.fileutils"],
       "ARGF.class/i.filename.ARGF"  => ["ARGF.class#filename", "ARGF.class/i.filename.ARGF"])
  def test_methodid2spec(data)
    expected, target = data
    assert_equal(expected, methodid2specstring(target))
  end

  data("String/i.index._builtin"     => ["_builtin",   "String/i.index._builtin"],
       "CGI/i.accept.cgi"            => ["cgi",        "CGI/i.accept.cgi"],
       "Net=HTTP/i.ca_path.net.http" => ["net.http",   "Net=HTTP/i.ca_path.net.http"],
       "OpenURI/m.open.open=2duri"   => ["open=2duri", "OpenURI/m.open.open=2duri"])
  def test_methodid2libid(data)
    expected, target = data
    assert_equal(expected, methodid2libid(target))
  end

  data("String/i.index._builtin"     => ["String",   "String/i.index._builtin"],
       "CGI/i.accept.cgi"            => ["CGI",      "CGI/i.accept.cgi"],
       "Net=HTTP/i.ca_path.net.http" => ["Net=HTTP", "Net=HTTP/i.ca_path.net.http"])
  def test_methodid2classid(data)
    expected, target = data
    assert_equal(expected, methodid2classid(target))
  end

  data("String/i.index._builtin"     => [:instance_method,  "String/i.index._builtin"],
       "CGI/i.accept.cgi"            => [:instance_method,  "CGI/i.accept.cgi"],
       "Net=HTTP/i.ca_path.net.http" => [:instance_method,  "Net=HTTP/i.ca_path.net.http"],
       "String/s.new._builtin"       => [:singleton_method, "String/s.new._builtin"])
  def test_methodid2typename(data)
    expected, target = data
    assert_equal(expected, methodid2typename(target))
  end

  data("String/i.index._builtin"     => ["index",   "String/i.index._builtin"],
       "CGI/i.accept.cgi"            => ["accept",  "CGI/i.accept.cgi"],
       "Net=HTTP/i.ca_path.net.http" => ["ca_path", "Net=HTTP/i.ca_path.net.http"])
  def test_methodid2mname(data)
    expected, target = data
    assert_equal(expected, methodid2mname(target))
  end

  data("index"         => [true,  "index"],
       "accept"        => [true,  "accept"],
       "get"           => [true,  "get"],
       "Array"         => [true,  "Array"],
       "getIndex"      => [true,  "getIndex"],
       "PROXY"         => [true,  "PROXY"],
       "HTTP_PROXY"    => [true,  "HTTP_PROXY"],
       "gsub!"         => [true,  "gsub!"],
       "empty? "       => [true,  "empty?"],
       "instance_eval" => [true,  "instance_eval"],
       "__send"        => [true,  "__send"],
       "__send__"      => [true,  "__send__"],
       "__send!"       => [true,  "__send!"],
       "+"             => [true,  "+"],
       "-"             => [true,  "-"],
       "*"             => [true,  "*"],
       "/"             => [true,  "/"],
       "&"             => [true,  "&"],
       "|"             => [true,  "|"],
       "^"             => [true,  "^"],
       "`"             => [true,  "`"],
       ">>"            => [true,  ">>"],
       "<<"            => [true,  "<<"],
       "+@"            => [true,  "+@"],
       "-@"            => [true,  "-@"],
       "!"             => [true,  "!"],
       "!@"            => [true,  "!@"],
       "~"             => [true,  "~"],
       "**"            => [true,  "**"],
       "<"             => [true,  "<"],
       ">"             => [true,  ">"],
       "<="            => [true,  "<="],
       ">="            => [true,  ">="],
       "=="            => [true,  "=="],
       "==="           => [true,  "==="],
       "=~"            => [true,  "=~"],
       "[]"            => [true,  "[]"],
       "[]="           => [true,  "[]="],
       ""              => [false, ""],
       "!="            => [true,  "!="],
       "!~"            => [true,  "!~"],
       "&&"            => [false, "&&"],
       "||"            => [false, "||"],
       "++"            => [false, "++"],
       ">>>"           => [false, ">>>"],
       "***"           => [false, "***"],
       "===="          => [false, "===="],
       "#accept"       => [false, "#accept"],
       ".new"          => [false, ".new"],
       ".#cp"          => [false, ".#cp"],
       "$gvar"         => [false, "$gvar"],
       "CGI#accept"    => [false, "CGI#accept"],
       "String.new"    => [false, "String.new"],
       "Net::HTTP.get" => [false, "Net::HTTP.get"],
       "Net::HTTP.new" => [false, "Net::HTTP.new"])
  def test_methodname?(data)
    expected, target = data
    assert_equal(expected, methodname?(target))
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

  data(:instance_method  => [true,  :instance_method],
       :singleton_method => [true,  :singleton_method],
       :module_function  => [true,  :module_function],
       :constant         => [true,  :constant],
       :special_variable => [true,  :special_variable],
       :instance_eval    => [false, :instance_eval],
       :instance         => [false, :instance],
       :singleton        => [false, :singleton],
       "i"               => [false, "i"],
       "s"               => [false, "s"],
       :i                => [false, :i],
       :s                => [false, :s])
  def test_typename?(data)
    expected, target = data
    assert_equal(expected, typename?(target))
  end

  data do
    data_set = {}
    typemarks = [".", "#", ".#", "$", "::"]
    typemarks.each do |mark|
      data_set[mark] = [true, mark]
    end
    #marks = (0..255).map {|a| (0..255).map {|b| a.chr + b.chr } }.flatten
    marks = (0..127).map {|a| (0..127).map {|b| a.chr + b.chr } }.flatten
    (marks - typemarks).each do |m|
      data_set[m] = [false, m]
    end
    data_set
  end
  def test_typemark?(data)
    expected, target = data
    assert_equal(expected, typemark?(target))
  end

  data do
    data_set = {}
    typechars = %w( i s m c v )
    typechars.each do |char|
      data_set[char] = [true, char]
    end
    ((0..255).map {|b| b.chr } - typechars).each do |char|
      data_set[char] = [false, char]
    end
    data_set
  end
  def test_typechar?(data)
    expected, target = data
    assert_equal(expected, typechar?(target))
  end

  data(:singleton_method => ["s", :singleton_method],
       :instance_method  => ["i", :instance_method],
       :module_function  => ["m", :module_function],
       :constant         => ["c", :constant],
       :special_variable => ["v", :special_variable])
  def test_typename2char(data)
    expected, target = data
    assert_equal(expected, typename2char(target))
  end

  data("s" => [:singleton_method, "s"],
       "i" => [:instance_method,  "i"],
       "m" => [:module_function,  "m"],
       "c" => [:constant,         "c"],
       "v" => [:special_variable, "v"])
  def test_typechar2name(data)
    expected, target = data
    assert_equal(expected, typechar2name(target))
  end

  data("."  => ["s", "."],
       "#"  => ["i", "#"],
       ".#" => ["m", ".#"],
       "::" => ["c", "::"],
       "$"  => ["v", "$"])
  def test_typemark2char(data)
    expected, target = data
    assert_equal(expected, typemark2char(target))
  end

  data("s" => [".",  "s"],
       "i" => ["#",  "i"],
       "m" => [".#", "m"],
       "c" => ["::", "c"],
       "v" => ["$",  "v"])
  def test_typechar2mark(data)
    expected, target = data
    assert_equal(expected, typechar2mark(target))
  end

  data("Array"    => ["Array",      "Array"],
       "String"   => ["String",     "String"],
       "index"    => ["index",      "index"],
       "*"        => ["=2a",        "*"],
       "**"       => ["=2a=2a",     "**"],
       "open-uri" => ["open=2duri", "open-uri"],
       "net.http" => ["net=2ehttp", "net.http"])
  def test_encodename_url(data)
    expected, target = data
    assert_equal(expected, encodename_url(target))
  end

  data("Array"      => ["Array",    "Array"],
       "String"     => ["String",   "String"],
       "index"      => ["index",    "index"],
       "=2a"        => ["*",        "=2a"],
       "=2a=2a"     => ["**",       "=2a=2a"],
       "open=2duri" => ["open-uri", "open=2duri"],
       "net=2ehttp" => ["net.http", "net=2ehttp"])
  def test_decodename_url(data)
    expected, target = data
    assert_equal(expected, decodename_url(target))
  end

  data("Array"      => ["-array",        "Array"],
       "String"     => ["-string",       "String"],
       "CGI"        => ["-c-g-i",        "CGI"],
       "=2a"        => ["=2a",           "=2a"],
       "=2a=2a"     => ["=2a=2a",        "=2a=2a"],
       "open=2duri" => ["open=2duri",    "open=2duri"],
       "Net=HTTP"   => ["-net=-h-t-t-p", "Net=HTTP"])
  def test_encodeid(data)
    expected, target = data
    assert_equal(expected, encodeid(target))
  end

  data("-array"        => ["Array",      "-array"],
       "-string"       => ["String",     "-string"],
       "-c-g-i"        => ["CGI",        "-c-g-i"],
       "=2a"           => ["=2a",        "=2a"],
       "=2a=2a"        => ["=2a=2a",     "=2a=2a"],
       "open=2duri"    => ["open=2duri", "open=2duri"],
       "-net=-h-t-t-p" => ["Net=HTTP",   "-net=-h-t-t-p"])
  def test_decodeid(data)
    expected, target = data
    assert_equal(expected, decodeid(target))
  end

  data("Array"    => ["-array",     "Array"],
       "String"   => ["-string",    "String"],
       "index"    => ["index",      "index"],
       "*"        => ["=2a",        "*"],
       "**"       => ["=2a=2a",     "**"],
       "open-uri" => ["open=2duri", "open-uri"],
       "net.http" => ["net=2ehttp", "net.http"])
  def test_encodename_fs(data)
    expected, target = data
    assert_equal(expected, encodename_fs(target))
  end

  data("-array"     => ["Array",    "-array"],
       "-string"    => ["String",   "-string"],
       "index"      => ["index",    "index"],
       "=2a"        => ["*",        "=2a"],
       "=2a=2a"     => ["**",       "=2a=2a"],
       "open=2duri" => ["open-uri", "open=2duri"],
       "net=2ehttp" => ["net.http", "net=2ehttp"])
  def test_decodename_fs(data)
    expected, target = data
    assert_equal(expected, decodename_fs(target))
  end

end
