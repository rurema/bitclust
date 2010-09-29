#!/usr/bin/ruby -Ke

require 'fileutils'
require 'optparse'

ruby = nil
begin
  require "rbconfig"
  ruby = File.join(
    Config::CONFIG["bindir"],
    Config::CONFIG["ruby_install_name"] + Config::CONFIG["EXEEXT"]
  )
rescue LoadError
  ruby = "ruby"
end

bitclust_src_path = File.dirname(File.expand_path(__FILE__))
parent_path = File.dirname(bitclust_src_path)
output_path = File.join(parent_path, "ruby-refm-1.9.1-dynamic")
bitclust_dest_dir = "bitclust"
rubydoc_refm_api_src_path = File.join(parent_path, "rubydoc/refm/api/src")
database_encoding = "euc-jp"
database_versions = [
  "1.8.7",
  "1.9.2",
]
database_version_to_dir = proc {|version| "db-" + version.tr(".", "_") }
title = "bitclust"

fu = FileUtils::Verbose

parser = OptionParser.new

parser.on('--ruby=RUBY', 'path to ruby.') {|path|
  ruby = path
}
parser.on('--bitclust-srcdir=BITCLUSTDIR', 'path to bitclust.') {|path|
  bitclust_src_path = File.expand_path(path)
}
parser.on('--bitclust-dstdir=BITCLUSTDIR', 'dirname of bitclust in output.') {|dir|
  bitclust_dest_dir = dir
}
parser.on('--rubydoc-refm-api-srcdir=SRCDIR', 'path to rubydoc/refm/api/src.') {|path|
  rubydoc_refm_api_src_path = File.expand_path(path)
}
parser.on('--output-dir=OUTPUTDIR', 'path to output.') {|path|
  output_path = File.expand_path(path)
}
parser.on('--database-encoding=ENCODING', 'encoding of database.') {|encoding|
  database_encoding = encoding
}
parser.on('--database-versions=VERSION,VERSION', 'versions of database.', Array) {|versions|
  database_versions = versions
}

begin
  parser.parse!
rescue OptionParser::ParseError => err
  $stderr.puts err.message
  $stderr.puts parser.help
  exit 1
end

bitclust_command = File.join(bitclust_src_path, "bin/bitclust.rb")

def system_verbose(*args)
  puts args.inspect
  system(*args) or raise "failed: #{args.inspect}"
end

unless File.exist?(File.join(output_path, bitclust_dest_dir))
  fu.mkpath(File.join(output_path, bitclust_dest_dir))
  Dir.glob("#{bitclust_src_path}/**/*").each do |src|
    dest = File.join(output_path, bitclust_dest_dir, src[bitclust_src_path.size..-1])
    if File.directory?(src)
      fu.mkpath(dest)
    else
      fu.cp(src, dest)
    end
  end
end

database_versions.each do |version|
  database_path = File.join(output_path, database_version_to_dir.call(version))
  unless File.exist?(database_path)
    system_verbose(ruby, "-Ke", bitclust_command, "--database=#{database_path}", "init", "encoding=#{database_encoding}", "version=#{version}")
    system_verbose(ruby, "-Ke", bitclust_command, "--database=#{database_path}", "update", "--stdlibtree=#{rubydoc_refm_api_src_path}")
  end
end

server_rb = File.join(output_path, "server.rb")
unless File.exist?(server_rb)
  puts "write #{server_rb}"
  File.open(server_rb, "wb", 0755) do |f|
    f.puts <<-RUBY
#!/usr/bin/ruby -Ke
Dir.chdir File.dirname(__FILE__)
standalone = "#{bitclust_dest_dir}/standalone.rb"
src = File.read(standalone).sub(/\\$0/) { standalone.dump }
ARGV.unshift "--bind-address=127.0.0.1"
ARGV.unshift "--baseurl="
ARGV.unshift "--debug"
ARGV.unshift "--auto"
eval src, binding, standalone, 1
    RUBY
  end
end

readme_html = File.join(output_path, "readme.html")
unless File.exist?(readme_html)
  puts "write #{readme_html}"
  File.open(readme_html, "wb") do |f|
    f.puts <<-HTML
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN" "http://www.w3.org/TR/html4/loose.dtd">

<html lang="ja-JP">
<head>
  <meta http-equiv="Content-Type" content="text/html; charset=euc-jp">
  <meta http-equiv="Content-Language" content="ja-JP">
  <link rel="stylesheet" type="text/css" href="./bitclust/theme/default/style.css">
  <title>Ruby リファレンスマニュアル刷新計画</title>
</head>
<body>
<h1>Ruby リファレンスマニュアル刷新計画</h1>

<h2>これは何？</h2>
<p>
Ruby リファレンスマニュアルの簡易 Web サーバシステムです。
</p>

<!--links-->

<p>
使い方に関しては以下の URL を参照してください。
</p>
<ul>
  <li><a href="http://doc.loveruby.net/wiki/ReleasePackageHowTo.html">http://doc.loveruby.net/wiki/ReleasePackageHowTo.html</a></li>
</ul>

<p>
プロジェクト全体に関しては以下の URL を参照してください。
</p>
<ul>
  <li><a href="http://doc.loveruby.net/wiki/FrontPage.html">http://doc.loveruby.net/wiki/FrontPage.html</a></li>
</ul>

</body>
</html>
    HTML
  end
end

database_versions.each do |version|
  database_dir = database_version_to_dir.call(version)
  refe = File.join(output_path, database_dir.sub(/db/, "refe"))
  refe_cmd = refe + ".cmd"
  unless File.exist?(refe_cmd)
    puts "write #{refe_cmd}"
    File.open(refe_cmd, "wb") do |f|
      f.puts(<<-CMD.gsub(/\r?\n/, "\r\n"))
@echo off
pushd "%~dp0"
ruby -Ke -I bitclust/lib bitclust/bin/refe.rb -d #{database_dir} -e sjis %*
popd
      CMD
    end
  end
  unless File.exist?(refe)
    puts "write #{refe}"
    File.open(refe, "wb", 0755) do |f|
      f.puts <<-SH
#!/bin/sh
cd "`dirname "$0"`"
exec ruby -Ke -I bitclust/lib bitclust/bin/refe.rb -d #{database_dir} "$@"
      SH
    end
  end
end

Dir.chdir(File.dirname(output_path))
archive_name = File.basename(output_path)
begin
  require "Win32API"
  # make server.exe using exerb
  Dir.chdir(File.basename(output_path)) do
    system_verbose("ruby", "-rexerb/mkexy", "server.rb")
    File.open("server.exy", "r+") do |f|
      yaml = f.read
      f.rewind
      f.truncate(0)
      yaml.each do |line|
        f.puts line unless /bitclust/ =~ line
      end
    end
    system_verbose("ruby", "-S", "exerb", "server.exy")
  end

  # call DLL to make archives
  buf = ' '*32*1024
  [
    ["7-zip32", "SevenZip", "-tzip -mx9 a #{archive_name}.zip #{archive_name}"],
    ["tar32", "Tar", "-z9 -cvf #{archive_name}.tar.gz #{archive_name}"],
    ["tar32", "Tar", "--bzip2 -cvf #{archive_name}.tar.bz2 #{archive_name}"],
  ].each do |dllname, funcname, args|
    func = Win32API.new(dllname, funcname, ['N','P','P','N'], 'N')
    puts "#{dllname}: #{funcname} #{args}"
    p func.call(0, args, buf, buf.size)
    puts buf.split(/\x0/,2)[0].rstrip
  end
rescue LoadError
  begin
    system_verbose("7za", "-tzip", "a", archive_name+".zip", archive_name)
  rescue
    system_verbose("zip", "-r", archive_name+".zip", archive_name)
  end
  ENV['GZIP'] = '--best'
  system("tar", "--owner=root", "--group=root", "-zcvf", archive_name+".tar.gz", archive_name)
  system("tar", "--owner=root", "--group=root", "--bzip2", "-cvf", archive_name+".tar.bz2", archive_name)
end
