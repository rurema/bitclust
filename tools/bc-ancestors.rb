#!/usr/bin/env ruby

require 'pathname'

bindir = Pathname.new(__FILE__).realpath.dirname
$LOAD_PATH.unshift((bindir + '../lib').realpath)

require 'bitclust'
require 'bitclust/crossrubyutils'
require 'optparse'
require 'set'

include BitClust::CrossRubyUtils

def main
  prefix = nil
  requires = []
  ver = RUBY_VERSION
  @verbose = false
  all = false
  parser = OptionParser.new
  parser.banner =<<BANNER
  Usage: #{File.basename($0, '.*')} [-r<lib>] [--ruby=<VER>] --db=PATH <classname>
         #{File.basename($0, '.*')} [-r<lib>] [--ruby=<VER>] --db=PATH --all
  NG Sample:
    $ #{File.basename($0, '.*')} -rfoo --ruby=1.9.1 --db=./db Foo
    NG : Foo
    + FooModule (The Ruby have this class/module in ancestors of the class)
    - BarModule (The Database have this class/module in ancestors of the class)
  Options:
BANNER
  parser.on('-d', '--database=PATH', 'Database prefix.') {|path|
    prefix = path
  }
  parser.on('-r LIB', 'Requires library LIB') {|lib|
    requires.push lib
  }
  parser.on('--ruby=[VER]', "The version of Ruby interpreter"){|ver|
    ver = ver
  }
  parser.on('-v', '--verbose', 'Show differences'){
    @verbose = true
  }
  parser.on('--all', 'Check anccestors for all classes'){
    all = true
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
  unless ARGV.size == 1 || all
    $stderr.puts "wrong number of arguments"
    $stderr.puts opts.help
    exit 1
  end
  classname = ARGV[0]
  db = BitClust::MethodDatabase.new(prefix)
  ruby = get_ruby(ver)
  if classname && !all
    check_ancestors(db, ruby, requires, classname)
  else
    $stderr.puts 'check all...'
    check_all_ancestors(db, ruby, requires)
  end
end

def ancestors(ruby, requires, classname)
  req = requires.map{|lib|
    unless '_builtin' == lib
      "-r#{lib}"
    else
      ''
    end
  }.join(" ")
  script =<<-SRC
  c = #{classname}
  puts c.ancestors.join("\n")
  SRC
  `#{ruby} #{req} -e '#{script}'`.split
end

def check_ancestors(db, ruby, requires, classname)
  a = ancestors(ruby, requires, classname)
  begin
    b = db.fetch_class(classname).ancestors.map(&:name)
  rescue BitClust::ClassNotFound => ex
    $stderr.puts "class not found in database : #{classname}"
    b = []
  end
  unless a.to_set == b.to_set
    puts "NG : #{classname}"
    puts (a-b).map{|c| "+ #{c}" }.join("\n")
    puts (b-a).map{|c| "- #{c}" }.join("\n")
  else
    puts "OK : #{classname}" if @verbose
  end
end

def check_all_ancestors(db, ruby, requires)
  classnames = []
  requires.each do |lib|
    classnames.push(*defined_classes(ruby, lib, []))
  end
  classnames.each do |classname|
    check_ancestors(db, ruby, requires, classname)
  end
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
      begin
        require "#{lib}"
      rescue LoadError
        $stderr.puts "\#{RUBY_VERSION} (\#{RUBY_RELEASE_DATE}): library not exist: #{lib}"
        exit
      end
      after = class_extent()
      (after - before).each do |c|
        puts c
      end
    end
  '`
  output.split
end

main
