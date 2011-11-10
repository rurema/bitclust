#!/usr/bin/ruby -Ke
#
# $Id$
#
# Stand-alone BitClust server based on WEBrick
#

require 'uri'
require 'webrick'
require 'optparse'
require 'pathname'

def srcdir_root
  Pathname.new(__FILE__).realpath.dirname.parent.cleanpath
end

params = {
  :Port => 10080
}
baseurl = nil
dbpath = nil
srcdir = libdir = datadir = themedir = theme = templatedir = nil
encoding = 'euc-jp'   # encoding of view
set_srcdir = lambda {|path|
  srcdir = path
  datadir ||= "#{srcdir}/data/bitclust"
  themedir ||= "#{srcdir}/theme"
  libdir ||= "#{srcdir}/lib"
}

debugp = false
autop = false
browser = nil
pid_file = nil
capi = false

parser = OptionParser.new
parser.banner = "#{$0} [--bind-address=ADDR] [--port=NUM] --baseurl=URL --database=PATH [--srcdir=PATH] [--datadir=PATH] [--themedir=PATH] [--debug] [--auto] [--browser=BROWSER] [--pid-file=PATH] [--capi]"
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
parser.on('--templatedir=PATH', 'Template directory.') {|path|
  templatedir = path
}
parser.on('--themedir=PATH', 'BitClust theme directory.') {|path|
  themedir = path
}
parser.on('--theme=THEME', 'BitClust theme.') {|th|
  theme = th
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
parser.on('--capi', 'see also FunctionDatabase.') {|path|
  capi = true
}
begin
  parser.parse!
rescue OptionParser::ParseError => err
  $stderr.puts err.message
  $stderr.puts parser.help
  exit 1
end

set_srcdir.call srcdir_root unless srcdir

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
require 'bitclust/app'

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
  app = BitClust::App.new(                          
    :dbpath => Dir.glob("db-*"),
    :baseurl => baseurl,
    :datadir => datadir,
    :templatedir => templatedir,
    :theme => theme,                          
    :encoding => encoding,
    :capi => capi
    )
  app.interfaces.each do |version, interface|
    server.mount File.join(basepath, version), interface
  end
  server.mount(File.join(basepath, '/'), app)
else
  viewpath = File.join(basepath, 'view')
  app = BitClust::App.new(
    :viewpath => viewpath,
    :dbpath => dbpath,
    :baseurl => baseurl,
    :datadir => datadir,
    :templatedir => templatedir,                          
    :theme => theme,
    :encoding => encoding,
    :capi => capi
    )
  app.interfaces.each do |viewpath, interface|
    server.mount viewpath, interface
  end
  # Redirect from '/' to "#{viewpath}/"
  server.mount('/', app)
end

server.mount File.join(basepath, 'theme/'), WEBrick::HTTPServlet::FileHandler, themedir

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
