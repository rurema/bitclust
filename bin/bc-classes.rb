require 'optparse'

def main
  rejects = []
  opts = OptionParser.new
  opts.banner = "Usage: #{File.basename($0, '.*')} [-r<lib>] <lib>"
  opts.on('-r', '--reject=LIB', 'Reject library LIB') {|lib|
    rejects.concat lib.split(',')
  }
  opts.on('--help', 'Prints this message and quit.') {
    puts opts.help
    exit 0
  }
  begin
    opts.parse!(ARGV)
  rescue OptionParser::ParseError => err
    $stderr.puts err.message
    exit 1
  end
  unless ARGV.size == 1
    $stderr.puts 'wrong number of arguments'
    $stderr.puts opts.help
    exit 1
  end
  lib = ARGV[0]

  vers, table = *get_class_table(lib, rejects)
  print_table vers, table
end

def print_table(vers, table)
  thcols = [20, table.keys.map {|s| s.size }.max].max
  print_record thcols, '', vers.map {|ver| version_id(ver) }
  table.keys.sort.each do |c|
    print_record thcols, c, vers.map {|ver| table[c][ver] ? 'o' : '-' }
  end
end

def print_record(thcols, th, tds)
  printf "%-#{thcols}s ", th
  puts tds.map {|td| '%4s' % td }.join('')
end

def version_id(ver)
  ver.split[1].tr('.', '')
end

def get_class_table(lib, rejects)
  ENV.delete 'RUBYOPT'
  ENV.delete 'RUBYLIB'
  vers = []
  table = {}
  forall_ruby(ENV['PATH']) do |ruby, ver|
    puts "#{version_id(ver)}: #{ver}" if @verbose
    vers.push ver
    defined_classes(ruby, lib, rejects).each do |c|
      (table[c] ||= {})[ver] = true
    end
  end
  return vers, table
end

def defined_classes(ruby, lib, rejects)
  output = `#{ruby} -e '
    def class_extent
      result = []
      ObjectSpace.each_object(Module) do |c|
        result.push c
      end
      result
    end

    %w(#{rejects.join(" ")}).each do |lib|
      begin
        require lib
      rescue LoadError
      end
    end
    if "#{lib}" == "_builtin"
      class_extent().each do |c|
        puts c
      end
    else
      before = class_extent()
      require "#{lib}"
      after = class_extent()
      (after - before).each do |c|
        puts c
      end
    end
  '`
  output.split
end

def forall_ruby(path, &block)
  rubys(path)\
      .map {|ruby| [ruby, `#{ruby} --version`] }\
      .sort_by {|ruby, verstr| verstr }\
      .each(&block)
end

def rubys(path)
  parse_PATH(path).map {|bindir|
    Dir.glob("#{bindir}/ruby-[12]*").map {|path| File.basename(path) }
  }\
  .flatten.uniq + ['ruby']
end

def parse_PATH(str)
  str.split(':').map {|path| path.empty? ? '.' : path }
end

main
