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

require 'bitclust/crossrubyutils'
require 'optparse'

include BitClust::CrossRubyUtils

def main
  @requires = []
  @verbose = false
  opts = OptionParser.new
  opts.banner = "Usage: #{File.basename($0, '.*')} [-r<lib>] <classname>"
  opts.on('-r LIB', 'Requires library LIB') {|lib|
    @requires.push lib
  }
  opts.on('-v', '--verbose', "Prints each ruby's version") {
    @verbose = true
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
  print_crossruby_table {|ruby| defined_methods(ruby, classname) }
end

def crossrubyutils_sort_entries(ents)
  ents.sort_by {|m| m_order(m) }
end

ORDER = { '.' => 1, '#' => 2, '::' => 3 }

def m_order(m)
  m, t, c = *m.reverse.split(/(\#|\.|::)/, 2)
  [ORDER[t], m.reverse]
end

def defined_methods(ruby, classname)
  req = @requires.map {|lib| "-r#{lib}" }.join(' ')
  `#{ruby} #{req} -e '
    #{classname}.singleton_methods(false).each do |m|
      puts "#{classname}.\#{m}"
    end
    #{classname}.instance_methods(false).each do |m|
      puts "#{classname}\\#\#{m}"
    end
    (#{classname}.constants - #{classname}.ancestors[1..-1].map {|c| c.constants }.flatten).each do |m|
      puts "#{classname}::\#{m}"
    end
  '`.split
end

main
