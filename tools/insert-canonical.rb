require "optparse"
require "uri"
require "fileutils"
require "tempfile"
require "strscan"

canonical_base_url = "https://docs.ruby-lang.org/ja/latest/"
base_dir = nil

parser = OptionParser.new
parser.on("--canonical-base-url=URL", "Canonical base URL") do |url|
  canonical_base_url = URI(url)
end
parser.on("--base-dir=DIR", "Base directory") do |dir|
  base_dir = dir
end

begin
  parser.parse!
rescue OptionParser::ParseError => ex
  $stderr.puts ex.message
  $stderr.push parser.help
  exit(false)
end

def insert_canonical_url(canonical_base_url, entry)
  canonical_link = %Q(<link rel="canonical" href="#{canonical_base_url + entry}">\n)
  scanner = StringScanner.new(File.read(entry))
  Tempfile.create(File.basename(entry)) do |file|
    loop do
      if scanner.scan(%r!( +)<link rel="icon" type="image/png" href=".+">\n!)
        matched = scanner.matched
        file.write(matched)
        file.write(scanner[1])
        file.write(canonical_link)
      end
      ch = scanner.getch
      if ch
        file.write(ch)
      else
        break
      end
    end
    mode = File.stat(entry).mode
    file.flush
    FileUtils.cp(file.path, entry)
    File.chmod(mode, entry)
  end
end

Dir.chdir(base_dir) do
  Dir.glob("**/*.html") do |entry|
    print entry
    insert_canonical_url(canonical_base_url, entry)
    print "\r"
    print " " * entry.bytesize
    print "\r"
  end
  puts "done"
end
