#@since 1.9.1
cgi ライブラリのコア機能を提供するライブラリです。
#@end

# class CGI < Object
include CGI::QueryExtension

CGI スクリプトを書くために必要な機能を提供するクラスです。

## Class Methods
### def parse(query) -> Hash

与えられたクエリ文字列をパースします。

- **param** `query` -- クエリ文字列を指定します。

例：
```````````
require "cgi"

params = CGI.parse("query_string")
  # {"name1" => ["value1", "value2", ...],
  #  "name2" => ["value1", "value2", ...], ... }
```````````

#@since 1.9.1
### def accept_charset -> String

受けとることができるキャラクタセットを文字列で返します。
デフォルトは UTF-8 です。

### def accept_charset=(charset)

受けとることができるキャラクタセットを設定します。

- **param** `charset` -- 文字列でキャラクタセットの名前を指定します。

- **SEE** [d:spec/m17n]

#@end
#@until 1.9.1
#@include(util.rd)
#@end
## Instance Methods

#@since 1.9.1
### def accept_charset -> String

受けとることができるキャラクタセットを文字列で返します。
デフォルトは UTF-8 です。

- **SEE** [m:CGI.accept_charset], [m:CGI.accept_charset=]

### def nph? -> bool
#@#nodoc

#@end

### def header(options = "text/html") -> String

HTTP ヘッダを options に従って生成します。 [m:CGI#out] と違い、標準出力には出力しません。
[m:CGI#out] を使わずに自力で HTML を出力したい場合などに使います。
このメソッドは文字列エンコーディングを変換しません。

ヘッダのキーとしては以下が利用可能です。

- **`type`**:
  Content-Type ヘッダです。デフォルトは "text/html" です。
- **`charset`**:
  ボディのキャラクタセットを Content-Type ヘッダに追加します。
- **`nph`**:
  真偽値を指定します。真ならば、HTTP のバージョン、ステータスコード、
  Date ヘッダをセットします。また Server と Connection の各ヘッダにもデフォルト値をセットします。
  偽を指定する場合は、これらの値を明示的にセットしてください。
- **`status`**:
  HTTP のステータスコードを指定します。
  このリストの下に利用可能なステータスコードのリストがあります。
- **`server`**:
  サーバソフトウェアの名称指定します。Server ヘッダに対応します。
- **`connection`**:
  接続の種類を指定します。Connection ヘッダに対応します。
- **`length`**:
  送信するコンテンツの長さを指定します。Content-Length ヘッダに対応します。
- **`language`**:
  送信するコンテンツの言語を指定します。Content-Language ヘッダに対応します。
- **`expires`**:
  送信するコンテンツの有効期限を [c:Time] のインスタンスで指定します。
  Expires ヘッダに対応します。
- **`cookie`**:
  クッキーとして文字列か [c:CGI::Cookie] のインスタンス、またはそれらの配列かハッシュを指定します。
  一つ以上の Set-Cookie ヘッダに対応します。

status パラメータには以下の文字列が使えます。

```````````
"OK"                  --> "200 OK"
"PARTIAL_CONTENT"     --> "206 Partial Content"
"MULTIPLE_CHOICES"    --> "300 Multiple Choices"
"MOVED"               --> "301 Moved Permanently"
"REDIRECT"            --> "302 Found"
"NOT_MODIFIED"        --> "304 Not Modified"
"BAD_REQUEST"         --> "400 Bad Request"
"AUTH_REQUIRED"       --> "401 Authorization Required"
"FORBIDDEN"           --> "403 Forbidden"
"NOT_FOUND"           --> "404 Not Found"
"METHOD_NOT_ALLOWED"  --> "405 Method Not Allowed"
"NOT_ACCEPTABLE"      --> "406 Not Acceptable"
"LENGTH_REQUIRED"     --> "411 Length Required"
"PRECONDITION_FAILED" --> "412 Precondition Failed"
"SERVER_ERROR"        --> "500 Internal Server Error"
"NOT_IMPLEMENTED"     --> "501 Method Not Implemented"
"BAD_GATEWAY"         --> "502 Bad Gateway"
"VARIANT_ALSO_VARIES" --> "506 Variant Also Negotiates"
```````````

- **param** `options` -- [[c:Hash]] か文字列で HTTP ヘッダを生成するための情報を指定します。

例：
```````````
header
  # Content-Type: text/html

header("text/plain")
  # Content-Type: text/plain

header({"nph"        => true,
        "status"     => "OK",  # == "200 OK"
          # "status"     => "200 GOOD",
        "server"     => ENV['SERVER_SOFTWARE'],
        "connection" => "close",
        "type"       => "text/html",
        "charset"    => "iso-2022-jp",
          # Content-Type: text/html; charset=iso-2022-jp
        "language"   => "ja",
        "expires"    => Time.now + 30,
        "cookie"     => [cookie1, cookie2],
        "my_header1" => "my_value",
        "my_header2" => "my_value"})
```````````

例：
```````````
cgi = CGI.new('html3')
print cgi.header({"charset" => "shift_jis", "status" => "OK"})
print "<html><head><title>TITLE</title></head>\r\n"
print "<body>BODY</body></html>\r\n"
```````````

- **SEE** [ruby-list:35911]

### def out(options = "text/html") { .... }

HTTP ヘッダと、ブロックで与えられた文字列を標準出力に出力します。

HEADリクエスト (REQUEST_METHOD == "HEAD") の場合は HTTP ヘッダのみを出力します。

charset が "iso-2022-jp"・"euc-jp"・"shift_jis" のいずれかで
ある場合は文字列エンコーディングを自動変換し、language を "ja"にします。

- **param** `options` -- [[c:Hash]] か文字列で HTTP ヘッダを生成するための情報を指定します。

例：
```````````
cgi = CGI.new
cgi.out{ "string" }
  # Content-Type: text/html
  # Content-Length: 6
  #
  # string

cgi.out("text/plain"){ "string" }
  # Content-Type: text/plain
  # Content-Length: 6
  #
  # string

cgi.out({"nph"        => true,
         "status"     => "OK",  # == "200 OK"
         "server"     => ENV['SERVER_SOFTWARE'],
         "connection" => "close",
         "type"       => "text/html",
         "charset"    => "iso-2022-jp",
           # Content-Type: text/html; charset=iso-2022-jp
         "language"   => "ja",
         "expires"    => Time.now + (3600 * 24 * 30),
         "cookie"     => [cookie1, cookie2],
         "my_header1" => "my_value",
         "my_header2" => "my_value"}){ "string" }
```````````

- **SEE** [m:CGI#header]

### def print(*strings)
#@todo

引数の文字列を標準出力に出力します。
cgi.print は $DEFAULT_OUTPUT.print と等価です。

例：
``````````
cgi = CGI.new
cgi.print "This line is a part of content body.\r\n"
``````````

## Constants

### const CR -> String

キャリッジリターンを表す文字列です。

### const LF -> String

ラインフィードを表す文字列です。

### const EOL -> String

改行文字です。

#@# --- REVISION -> String
#@# nodoc

#@since 1.9.2
### const NEEDS_BINMODE -> bool

ファイルを開くときにバイナリモードが必要かどうかを表す定数です。
プラットフォーム依存の定数です。
#@end

### const PATH_SEPARATOR -> Hash

パスの区切り文字を格納します。

### const HTTP_STATUS -> Hash

HTTP のステータスコードを表すハッシュです。

#@until 1.9.1
#@# 1.9.1 以降は cgi/util.rd を参照
### const RFC822_DAYS -> [String]

[rfc:822] で定義されている曜日の略称を返します。

- **SEE** [rfc:822]

### const RFC822_MONTHS -> [String]

[rfc:822] で定義されている月名の略称を返します。

- **SEE** [rfc:822]
#@end
#@since 1.9.1
### const MAX_MULTIPART_LENGTH -> Integer

Maximum content length of multipart data

### const MAX_MULTIPART_COUNT -> Integer

Maximum number of request parameters when multipart

#@end
# module CGI::QueryExtension

クエリ文字列を扱うためのメソッドを定義しているモジュールです。

## Instance Methods

### def [](key) -> Array

文字列 key に対応するパラメータを配列で返します。
key に対応するパラメータが見つからなかった場合は、nil を返します。（[m:CGI#params]と等価です）

フォームから入力された値や、URL に埋め込まれた QUERY_STRING のパース結果の取得などに使用します。

- **param** `key` -- キーを文字列で指定します。

### def accept -> String

ENV['HTTP_ACCEPT'] を返します。

### def accept_charset -> String

ENV['HTTP_ACCEPT_CHARSET'] を返します。

### def accept_encoding -> String

ENV['HTTP_ACCEPT_ENCODING'] を返します。

### def accept_language -> String

ENV['HTTP_ACCEPT_LANGUAGE'] を返します。

### def auth_type -> String

ENV['AUTH_TYPE'] を返します。

### def cache_control -> String

ENV['HTTP_CACHE_CONTROL'] を返します。

### def content_length -> Integer

ENV['CONTENT_LENGTH'] を返します。

### def content_type -> String

ENV['CONTENT_TYPE'] を返します。

### def cookies -> Hash

クッキーの名前と値をペアにした要素を持つハッシュを返します。

### def cookies=(value)

クッキーをセットします。

- **param** `value` -- クッキーの名前と値をペアにした要素を持つハッシュを指定します。

### def from -> String

ENV['HTTP_FROM'] を返します。

### def gateway_interface -> String

ENV['GATEWAY_INTERFACE'] を返します。

### def has_key?(*args) -> bool
### def key?(*args) -> bool
### def include?(*args) -> bool

与えられたキーがクエリに含まれている場合は、真を返します。
そうでない場合は、偽を返します。

- **param** `args` -- キーを一つ以上指定します。

### def host -> String

ENV['HTTP_HOST'] を返します。

### def keys(*args) -> [String]

すべてのパラメータのキーを配列として返します。

### def multipart? -> bool

マルチパートフォームの場合は、真を返します。
そうでない場合は、偽を返します。

``````````
例：
cgi = CGI.new
if cgi.multipart?
  field1=cgi['field1'].read
else
  field1=cgi['field1']
end
``````````

### def negotiate -> String

ENV['HTTP_NEGOTIATE'] を返します。

### def params -> Hash

パラメータを格納したハッシュを返します。

フォームから入力された値や、URLに埋め込まれた QUERY_STRING のパース結果の取得などに使用します。

`````````
cgi = CGI.new
cgi.params['developer']     # => ["Matz"] (Array)
cgi.params['developer'][0]  # => "Matz"
cgi.params['']              # => nil
`````````

### def params=(hash)

与えられたハッシュをパラメータにセットします。

- **param** `hash` -- ハッシュを指定します。


### def path_info -> String

ENV['PATH_INFO'] を返します。

### def path_translated -> String

ENV['PATH_TRANSLATED'] を返します。

### def pragma -> String

ENV['HTTP_PRAGMA'] を返します。

### def query_string -> String

ENV['QUERY_STRING'] を返します。

### def raw_cookie -> String

ENV["HTTP_COOKIE"] を返します。

### def raw_cookie2 -> String

ENV["HTTP_COOKIE2"] を返します。

### def referer -> String

ENV['HTTP_REFERER'] を返します。

### def remote_addr -> String

ENV['REMOTE_ADDR'] を返します。

### def remote_host -> String

ENV['REMOTE_HOST'] を返します。

### def remote_ident -> String

ENV['REMOTE_IDENT'] を返します。

### def remote_user -> String

ENV['REMOTE_USER'] を返します。

### def request_method -> String

ENV['REQUEST_METHOD'] を返します。

### def script_name -> String

ENV['SCRIPT_NAME'] を返します。

### def server_name -> String

ENV['SERVER_NAME'] を返します。

### def server_port -> Integer

ENV['SERVER_PORT'] を返します。

### def server_protocol -> String

ENV['SERVER_PROTOCOL'] を返します。

### def server_software -> String

ENV['SERVER_SOFTWARE'] を返します。

### def user_agent -> String

ENV['HTTP_USER_AGENT'] を返します。

#@since 1.9.1
### def create_body(is_large) -> StringIO | Tempfile
#@# nodoc

### def files -> Hash

アップロードされたファイルの名前とその内容を表すオブジェクトをペアとする要素を持つハッシュを返します。

### def unescape_filename? -> bool
#@# nodoc

#@end

# module CGI::QueryExtension::Value
#@# nodoc

## Instance Methods

### def [](idx, *args)
#@todo

### def first -> self
### def last  -> self
#@todo

### def set_params(params)
#@todo

### def to_a -> Array
### def to_ary -> Array
#@todo

# class CGI::InvalidEncoding < Exception

不正な文字エンコーディングが現れたときに発生する例外です。

