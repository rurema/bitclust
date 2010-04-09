#!/usr/bin/env ruby
#
# bc-methods.rb -- list all methods of existing rubys.
#
# This program is derived from bc-vdtb.rb, posted in
# [ruby-reference-manual:160] by sheepman.
#

require 'pathname'

bindir = Pathname.new(__FILE__).realpath.dirname
$LOAD_PATH.unshift((bindir + '../lib').realpath)

require 'bitclust'
require 'bitclust/crossrubyutils'
require 'optparse'

include BitClust::CrossRubyUtils

def main
  @requires = []
  @verbose = false
  @ver = RUBY_VERSION
  mode = :list
  target = nil
  opts = OptionParser.new
  opts.banner = "Usage: #{File.basename($0, '.*')} [-r<lib>] <classname>"
  opts.on('-r LIB', 'Requires library LIB') {|lib|
    @requires.push lib
  }
  opts.on('-v', '--verbose', "Prints each ruby's version") {
    @verbose = true
  }
  opts.on('--diff=RDFILE', 'RD file name') {|path|
    mode = :diff
    target = path
  }
  opts.on('-c', '') {
    @content = true
    require 'bitclust/ridatabase'
  }
  opts.on('--ruby=[VER]', "The version of Ruby interpreter"){|ver|
    @ver = ver
  }
  opts.on('--ri-database', 'The path of ri database'){|path|
    @ri_path = path
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
    $stderr.puts "wrong number of arguments"
    $stderr.puts opts.help
    exit 1
  end
  classname = ARGV[0]

  case mode
  when :list
    print_crossruby_table {|ruby| defined_methods(ruby, classname) }
  when :diff
    unless ruby = get_ruby(@ver)
      raise "Not found Ruby interpreter of the given version"
    end
    keys = defined_methods(ruby, classname) 
    lib = BitClust::RRDParser.parse_stdlib_file(target, { 'version' => @ver })
    c = lib.fetch_class(classname)
    list0 = lib.classes.find_all{|c0| /\A#{classname}\b/o =~ c0.name }
    list0 = c.entries + list0
    list = list0.map {|ent| ent.labels.map {|n| expand_mf(n) } }.flatten
    if @content      
      ri = @ri_path ? RiDatabase.open(@ri_path, nil) : RiDatabase.open_system_db
      ri.current_class = c.name
      mthds = ( ri.singleton_methods + ri.instance_methods )
      fmt = Formatter.new
      (keys - list).sort.each do |name|
        mthd = mthds.find{|m| name == m.fullname }
        if mthd
          puts fmt.method_info(mthd.entry)
        else
          name = name.sub(/\A\w+#/, '')
          puts "--- #{name}\n\#@todo\n\n"
        end
      end
    else
      (keys - list).sort.each do |name|
        puts "-#{name}"
      end
      (list - keys).sort.each do |name|
        puts "+#{name}" 
      end
    end
  else
    raise "must not happen: #{mode.inspect}"
  end
end

def expand_mf(n)
  if /\.\#/ =~ n
    [n.sub(/\.\#/, '.'), n.sub(/\.\#/, '#')]
  else
    n
  end
end

def crossrubyutils_sort_entries(ents)
  ents.sort_by {|m| m_order(m) }
end

ORDER = { '.' => 1, '#' => 2, '::' => 3 }

def m_order(m)
  m, t, c = *m.reverse.split(/(\#|\.|::)/, 2)
  [ORDER[t] || 0, m.reverse]
end

def defined_methods(ruby, classname)
  req = @requires.map {|lib| "-r#{lib}" }.join(' ')
  avoid_tracer = ""
  avoid_tracer = "Tracer.off" if @requires.include?("tracer")
  if classname == 'Object'
     `#{ruby} #{req} -e '
     c = #{classname}
     c.singleton_methods(false).each do |m|
       puts "#{classname}.\#{m}"
     end
     c.instance_methods(true).each do |m|
       puts "#{classname}\\#\#{m}"
     end
   '`.split
  elsif classname == 'Kernel'
    `#{ruby} #{req} -e '
     c = #{classname}
     c.singleton_methods(true).each do |m|
       puts "#{classname}.\#{m}"
     end
     ( c.private_instance_methods(false) && c.methods(false) ).each do |m|
       puts "#{classname}\\#\#{m}"
     end
     Object::constants.delete_if{|c| cl = Object.const_get(c).class; cl == Class or cl == Module }.each do |m|
       puts "#{classname}::\#{m}"
     end
     global_variables.each do |m|
       puts "#{classname}\#{m}"
     end
   '`.split
  else
    `#{ruby} #{req} -e '
    #{avoid_tracer}
    c = #{classname}
    c.singleton_methods(false).each do |m|
      puts "#{classname}.\#{m}"
    end
    c.instance_methods(false).each do |m|
      puts "#{classname}\\#\#{m}"
    end
    c.ancestors.map {|mod| mod.constants }.inject {|r,n| r-n }.each do |m|
      puts "#{classname}::\#{m}"
    end
  '`.split
  end
end

main
