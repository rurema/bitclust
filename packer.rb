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
output_path = "../rubyrefm-1.9.0-dynamic"
bitclust_src_path = File.dirname(__FILE__)
bitclust_dest_dir = "bitclust"
rubydoc_refm_api_src_path = "../rubydoc/refm/api/src"
database_dir = "db"
database_encoding = "euc-jp"
database_version = "1.9.0"
fu = FileUtils::Verbose

parser = OptionParser.new

parser.on('--ruby=RUBY', 'path to ruby.') {|path|
  ruby = path
}
parser.on('--bitclust-srcdir=BITCLUSTDIR', 'path to bitclust.') {|path|
  bitclust_src_path = path
}
parser.on('--bitclust-dstdir=BITCLUSTDIR', 'dirname of bitclust in output.') {|dir|
  bitclust_dest_dir = dir
}
parser.on('--rubydoc-refm-api-srcdir=SRCDIR', 'path to rubydoc/refm/api/src.') {|path|
  rubydoc_refm_api_src_path = path
}
parser.on('--output-dir=OUTPUTDIR', 'path to output.') {|path|
  output_path = path
}
parser.on('--database-dir=DATABASEDIR', 'dirname of database in output.') {|dir|
  database_dir = dir
}
parser.on('--database-encoding=ENCODING', 'encoding of database.') {|encoding|
  database_encoding = encoding
}
parser.on('--database-version=VERSION', 'version of database.') {|version|
  database_version = version
}

begin
  parser.parse!
rescue OptionParser::ParseError => err
  $stderr.puts err.message
  $stderr.puts parser.help
  exit 1
end

bitclust_command = File.join(bitclust_src_path, "bin/bitclust.rb")
database_path = File.join(output_path, database_dir)

def system_verbose(*args)
  puts args.inspect
  system(*args) or raise "failed: #{args.inspect}"
end

unless File.exist?(output_path)
  fu.mkpath(output_path)
  Dir.glob("#{bitclust_src_path}/**/*").each do |src|
    dest = File.join(output_path, bitclust_dest_dir, src)
    if File.directory?(src)
      fu.mkpath(dest)
    else
      fu.cp(src, dest)
    end
  end
end

unless File.exist?(database_path)
  system_verbose(ruby, bitclust_command, "--database=#{database_path}", "init", "encoding=#{database_encoding}", "version=#{database_version}")
  system_verbose(ruby, bitclust_command, "--database=#{database_path}", "update", "--stdlibtree=#{rubydoc_refm_api_src_path}")
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
src.gsub!(/\.start$/, "") if $".include?("exerb/mkexy.rb")
ARGV.unshift "--bind-address=127.0.0.1"
ARGV.unshift "--baseurl="
ARGV.unshift "--database=#{database_dir}"
ARGV.unshift "--debug"
eval src, binding, standalone, 1
    RUBY
  end
end

Dir.chdir(File.dirname(output_path))
archive_name = File.basename(output_path)
begin
  require "Win32API"
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
