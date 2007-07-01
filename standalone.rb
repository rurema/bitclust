#!/usr/bin/ruby -Ke
#
# $Id: standalone.rb 994 2004-12-08 15:16:41Z aamine $
#
# Stand-alone BitClust server based on WEBrick
#

require 'uri'
require 'webrick'
require 'optparse'

params = {
  :Port => 10080
}
baseurl = nil
dbpath = nil
srcdir = templatedir = themedir = nil
set_srcdir = lambda {|path|
  srcdir = path
  templatedir ||= "#{srcdir}/template"
  themedir ||= "#{srcdir}/theme"
  $LOAD_PATH.unshift "#{srcdir}/lib"
}
set_srcdir.call File.dirname($0)
debugp = false

parser = OptionParser.new
parser.banner = "#{$0} [--port=NUM] --baseurl=URL --database=PATH [--srcdir=PATH] [--templatedir=PATH] [--themedir=PATH] [--debug]"
parser.on('--port=NUM', 'Listening port number') {|num|
  params[:Port] = num.to_i
}
parser.on('--baseurl=URL', 'The base URL to host.') {|url|
  baseurl = url
}
parser.on('--database=PATH', 'Database root directory.') {|path|
  dbpath = path
}
parser.on('--srcdir=PATH', 'BitClust source directory.') {|path|
  set_srcdir.call path
}
parser.on('--templatedir=PATH', 'BitClust template directory.') {|path|
  templatedir = path
}
parser.on('--themedir=PATH', 'BitClust theme directory.') {|path|
  themedir = path
}
parser.on('--[no-]debug', 'Debug mode.') {|flag|
  debugp = flag
}
parser.on('--help', 'Prints this message and quit.') {
  puts parser.help
  exit 0
}
begin
  parser.parse!
rescue OptionParser::ParseError => err
  $stderr.puts err.message
  $stderr.puts parser.help
  exit 1
end
unless baseurl
  $stderr.puts "missing --baseurl"
  exit 1
end
unless dbpath
  $stderr.puts "missing --database"
  exit 1
end
unless templatedir
  $stderr.puts "missing templatedir; use --srcdir or --templatedir"
  exit 1
end
unless themedir
  $stderr.puts "missing themedir; use --srcdir or --themedir"
  exit 1
end

require 'bitclust'
require 'bitclust/interface'

db = BitClust::Database.new(dbpath)
manager = BitClust::ScreenManager.new(
  :base_url => baseurl,
  :cgi_url => "#{baseurl}/view",
  :templatedir => templatedir
)
handler = BitClust::RequestHandler.new(db, manager)

if debugp
  params[:Logger] = WEBrick::Log.new($stderr, WEBrick::Log::DEBUG)
  params[:AccessLog] = [
    [ $stderr, WEBrick::AccessLog::COMMON_LOG_FORMAT  ],
    [ $stderr, WEBrick::AccessLog::REFERER_LOG_FORMAT ],
    [ $stderr, WEBrick::AccessLog::AGENT_LOG_FORMAT   ],
  ]
else
  params[:Logger] = WEBrick::Log.new($stderr, WEBrick::Log::INFO)
  params[:AccessLog] = []
end
basepath = URI.parse(baseurl).path
server = WEBrick::HTTPServer.new(params)
server.mount File.join(basepath, 'view/'), BitClust::Interface.new { handler }
server.mount File.join(basepath, 'theme/'), WEBrick::HTTPServlet::FileHandler, themedir
if debugp
  trap(:INT) { server.shutdown }
else
  WEBrick::Daemon.start
end
server.start
