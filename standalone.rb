#!/usr/bin/ruby -Ke
#
# $Id$
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
srcdir = libdir = datadir = themedir = nil
encoding = 'euc-jp'   # encoding of view
set_srcdir = lambda {|path|
  srcdir = path
  datadir ||= "#{srcdir}/data/bitclust"
  themedir ||= "#{srcdir}/theme"
  libdir ||= "#{srcdir}/lib"
}
set_srcdir.call File.dirname($0)
debugp = false
autop = false
browser = nil
pid_file = nil

parser = OptionParser.new
parser.banner = "#{$0} [--bind-address=ADDR] [--port=NUM] --baseurl=URL --database=PATH [--srcdir=PATH] [--datadir=PATH] [--themedir=PATH] [--debug] [--auto] [--browser=BROWSER] [--pid-file=PATH]"
parser.on('--bind-address=ADDR', 'Bind address') {|addr|
  params[:BindAddress] = addr
}
parser.on('--port=NUM', 'Listening port number') {|num|
  params[:Port] = num.to_i
}
parser.on('--baseurl=URL', 'The base URL to host.') {|url|
  baseurl = url
}
parser.on('--database=PATH', 'MethodDatabase root directory.') {|path|
  dbpath = path
}
parser.on('--srcdir=PATH', 'BitClust source directory.') {|path|
  set_srcdir.call path
}
parser.on('--datadir=PATH', 'BitClust data directory.') {|path|
  datadir = path
}
parser.on('--themedir=PATH', 'BitClust theme directory.') {|path|
  themedir = path
}
parser.on('--[no-]debug', 'Debug mode.') {|flag|
  debugp = flag
}
parser.on('--[no-]auto', 'Auto mode.') {|flag|
  autop = flag
}
parser.on('--browser=BROWSER', 'Open with the browser.') {|path|
  browser = path
}
parser.on('--pid-file=PATH', 'Write pid of the daemon to the specified file.') {|path|
  pid_file = path
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
  $stderr.puts "missing base URL.  Use --baseurl"
  exit 1
end
unless dbpath || autop
  $stderr.puts "missing database path.  Use --database"
  exit 1
end
unless datadir
  $stderr.puts "missing datadir.  Use --datadir"
  exit 1
end
unless themedir
  $stderr.puts "missing themedir.  Use --themedir"
  exit 1
end
if pid_file 
  if File.exist?(pid_file)
    $stderr.puts "There is still #{pid_file}.  Is another process running?"
    exit 1
  end
  pid_file = File.expand_path(pid_file)
end

$LOAD_PATH.unshift libdir
require 'bitclust'
require 'bitclust/interface'

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

if autop
  handlers = {}
  Dir.glob("db-*").each do |dbpath|
    next unless /db-([\d_]+)/ =~ dbpath
    dbpath = File.expand_path(dbpath)
    version = $1.tr("_", ".")
    db = BitClust::MethodDatabase.new(dbpath)
    manager = BitClust::ScreenManager.new(
      :base_url => baseurl,
      :cgi_url => "#{baseurl}/#{version}",
      :datadir => datadir,
      :encoding => encoding
    )
    handlers[version] = BitClust::RequestHandler.new(db, manager)
    server.mount "#{basepath}/#{version}/", BitClust::Interface.new { handlers[version] }
    $bitclust_context_cache = nil # clear cache
  end
  server.mount_proc("#{basepath}/") do |req, res|
    raise WEBrick::HTTPStatus::NotFound if req.path != '/'
    links = "<ul>"
    handlers.keys.sort.each do |version|
      links << %Q(<li><a href="#{version}/">#{version}</a></li>)
    end
    links << "</ul>"
    if File.exist?("readme.html")
      res.body = File.read("readme.html").sub(%r!\./bitclust!, '').sub(/<!--links-->/) { links }
    else
      res.body = "<html><head><title>bitclust</title></head><body>#{links}</body></html>"
    end
    res['Content-Type'] = 'text/html; charset=euc-jp'
  end
else
  db = BitClust::MethodDatabase.new(dbpath)
  manager = BitClust::ScreenManager.new(
    :base_url => baseurl,
    :cgi_url => "#{baseurl}/view",
    :datadir => datadir,
    :encoding => encoding
  )
  handler = BitClust::RequestHandler.new(db, manager)
  server.mount File.join(basepath, 'view/'), BitClust::Interface.new { handler }
end

server.mount File.join(basepath, 'theme/'), WEBrick::HTTPServlet::FileHandler, themedir

# Redirect from '/' to 'view/'
server.mount_proc('/') do |req, res|
  viewpath = File.join(basepath, 'view/')
  res.body = "<html><head><meta http-equiv='Refresh' content='0;URL=#{viewpath}'></head></html>"
end

if debugp
  trap(:INT) { server.shutdown }
else
  WEBrick::Daemon.start do
    trap(:TERM) {
      server.shutdown 
      begin
        File.unlink pid_file if pid_file
      rescue Errno::ENOENT
      end
    }
    File.open(pid_file, 'w') {|f| f.write Process.pid } if pid_file
  end
end
exit if $".include?("exerb/mkexy.rb")
if autop && !browser
  case RUBY_PLATFORM
  when /mswin/
    browser = "start"
  end
end
system("#{browser} http://localhost:#{params[:Port]}/") if browser
server.start
