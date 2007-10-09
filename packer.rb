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
output_path = "../refmja190-#{Time.now.strftime('%Y%m%d')}"
bitclust_src_path = "."
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

fu.mkpath(output_path) unless File.exist?(output_path)
unless File.exist?(database_path)
  system_verbose(ruby, bitclust_command, "--database=#{database_path}", "init", "encoding=#{database_encoding}", "version=#{database_version}")
  system_verbose(ruby, bitclust_command, "--database=#{database_path}", "update", "--stdlibtree=#{rubydoc_refm_api_src_path}")
end

Dir.glob("#{bitclust_src_path}/**/*").each do |src|
  dest = File.join(output_path, bitclust_dest_dir, src)
  if File.directory?(src)
    fu.mkpath(dest)
  else
    fu.cp(src, dest)
  end
end

server_rb = File.join(output_path, "server.rb")
puts "write #{server_rb}"
File.open(server_rb, "wb", 0755) do |f|
  f.puts <<-RUBY
#!/usr/bin/ruby -Ke
ARGV.unshift "--bind-address=127.0.0.1"
ARGV.unshift "--baseurl="
ARGV.unshift "--database=#{database_dir}"
ARGV.unshift "--debug"
Dir.chdir File.dirname(__FILE__)
standalone = "#{bitclust_dest_dir}/standalone.rb"
#load standalone
src = File.read(standalone).sub(/\\$0/) { standalone.dump }
eval src, binding, standalone, 1
  RUBY
end
