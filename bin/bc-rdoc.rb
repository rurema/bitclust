#!/usr/bin/env ruby

require 'pathname'

srcdir_root = Pathname.new(__FILE__).realpath.dirname.parent.cleanpath
$LOAD_PATH.unshift srcdir_root + 'lib'

require 'bitclust'
require 'rdoc/ri/ri_reader'
require 'rdoc/ri/ri_cache'
require 'rdoc/ri/ri_paths'
require 'rdoc/markup/simple_markup/fragments'
require 'stringio'
require 'pp'
require 'optparse'

class ApplicationError < StandardError; end

def main
  Signal.trap(:PIPE) { exit 1 } rescue nil   # Win32 does not have SIGPIPE
  Signal.trap(:INT) { exit 1 }

  prefix = nil
  mode = :list
  type = :name
  parser = OptionParser.new
  parser.banner = "Usage: #{File.basename($0)} <classname>"
  parser.on('-d', '--database=PREFIX', 'BitClust database path') {|path|
    prefix = path
  }
  parser.on('--diff', 'Show difference between RD and RDoc') {
    mode = :diff
  }
  parser.on('-c', '--content', 'Prints method description') {
    type = :content
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

  # use only system database
  path = RI::Paths.path(true, false, false, false)
  reader = RI::RiReader.new(RI::RiCache.new(path))
  case mode
  when :list
    ARGV.each do |name|
      c = ri_lookup_class(reader, name)
      case type
      when :name
        c.method_entries.each do |m|
          puts m.fullname
        end
      when :content
        fmt = Formatter.new
        c.method_entries.each do |m|
          puts fmt.method_info(reader.get_method(m))
        end
      end
    end
  when :diff
    unless prefix
      $stderr.puts 'missing database prefix.  Use -d option'
      exit 1
    end
    unless ARGV.size == 1
      $stderr.puts "Usage: #{$0} --diff -d DBPATH <classname>"
      exit 1
    end
    cname = ARGV[0]
    db = BitClust::Database.new(prefix)
    begin
      bc_class = db.fetch_class(cname)
    rescue BitClust::ClassNotFound
      $stderr.puts "warning: class #{cname} not exist in BitClust database"
      bc_class = db.get_class(cname)
    end
    ri_class = ri_lookup_class(reader, cname)
    win, lose = *diff_class(bc_class, ri_class, reader)
    case type
    when :name
      win.each do |m|
        puts "+ #{m.fullname}"
      end
      lose.each do |m|
        puts "- #{m.fullname}"
      end
    when :content
      fmt = Formatter.new
      lose.each do |m|
        puts "\#@\# bc-rdoc: detected missing name: #{m.name}"
        puts fmt.method_info(m.entry)
      end
    end
  else
    raise "must not happen: #{mode.inspect}"
  end
rescue Errno::EPIPE
  exit 1
rescue ApplicationError, BitClust::UserError => err
  $stderr.puts err.message
  exit 1
end

def ri_lookup_class(reader, name)
  ns = reader.top_level_namespace.first
  name.split('::').each do |const|
    ns = ns.contained_class_named(const) or
        raise ApplicationError, "no such class in RDoc database: #{name}"
  end
  ns
end

def diff_class(bc, ri, reader)
  unzip(diff_entries(bc, bc.singleton_methods, reader.singleton_methods(ri)),
        diff_entries(bc, bc.instance_methods,  reader.instance_methods(ri)))\
      .map {|list| list.flatten }
end

def unzip(*tuples)
  [tuples.map {|s, i| s }, tuples.map {|s, i| i }]
end

def diff_entries(bc_class, _bc, _ri)
  bc = _bc.map {|m| m.names.map {|name| BCMethodEntry.new(name, m) } }.flatten.uniq.sort
  ri = _ri.map {|m|
         [RiMethodEntry.new(m.name, m)] +
             m.aliases.map {|a| RiMethodEntry.new(a.name, m) }
       }.flatten.uniq.sort
  win = bc - ri
  lose0 = ri - bc
  lose = lose0.reject {|m| true_exist?(bc_class, m) }
  [win, lose]
end

def true_exist?(klass, m)
  if m.singleton_method?
    klass.singleton_method?(m.name, true)
  else
    klass.instance_method?(m.name, true)
  end
end

def uncapsule(list)
  list.map {|m| m.entry }.uniq.sort_by {|ent| ent.name }
end

class Ent
  def initialize(name, ent)
    @name = name
    @entry = ent
  end

  attr_reader :name
  attr_reader :entry

  def ==(other)
    @name == other.name
  end

  alias eql? ==

  def hash
    @name.hash
  end

  def <=>(other)
    @name <=> other.name
  end
end

class BCMethodEntry < Ent
  def bitclust?
    true
  end

  def inspect
    "\#<BitClust #{@name} #{@entry.inspect}>"
  end

  def fullname
    "#{@entry.klass.name}#{@entry.typemark}#{@name}"
  end
end

class RiMethodEntry < Ent
  def bitclust?
    false
  end

  def inspect
    "\#<RDoc #{@name} #{@entry.fullname}>"
  end

  def singleton_method?
    @entry.singleton_method?
  end

  def fullname
    c, t, m = @entry.fullname.split(/([\.\#])/, 2)
    "#{c}#{t}#{@name}"
  end
end


module RI

  class RiReader   # reopen
    def singleton_methods(c)
      c.singleton_methods.map {|ent| get_method(ent) }
    end

    def instance_methods(c)
      c.instance_methods.map {|ent| get_method(ent) }
    end
  end

  class ClassEntry   # reopen
    def singleton_methods
      @class_methods
    end

    attr_reader :instance_methods

    def method_entries
      @class_methods.sort_by {|m| m.name } +
      @instance_methods.sort_by {|m| m.name }
    end
  end

  class MethodEntry   # reopen
    def fullname
      "#{@in_class.full_name}#{@is_class_method ? '.' : '#'}#{@name}"
    end

    def singleton_method?
      @is_class_method
    end
  end

  class MethodDescription   # reopen
    def fullname
      name = full_name()
      unless /\#/ =~ name
        components = name.split('::')
        m = components.pop
        components.join('::') + '.' + m
      else
        name
      end
    end

    def singleton_method?
      @is_class_method ||= false
      @is_class_method
    end
  end

end


module HTMLUtils

  ESC = {
    '&' => '&amp;',
    '<' => '&lt;',
    '>' => '&gt;',
    '"' => '&quot;'
  }

  def escape(str)
    t = ESC
    str.gsub(/[&"<>]/) {|s| t[s] }
  end
  module_function :escape

  UNESC = ESC.invert
  UNESC['&nbsp;'] = ' '

  def unescape(str)
    t = UNESC
    str.gsub(/&\w+;/) {|s| t[s] || s }
  end
  module_function :unescape

end


class Formatter

  include HTMLUtils

  def method_info(m)
    @f = StringIO.new
    describe_method m
    @f.string
  end

  private

  def line(s = nil)
    if s
      @f.puts s
    else
      @f.puts
    end
  end

  def describe_method(m)
    if m.params[0,1] == '('
      line "--- #{m.full_name}#{trim_space(m.params)}"
    else
      m.params.lines.each do |sig|
        line "--- #{trim_space(sig)}"
      end
    end
    unless m.aliases.empty?
      m.aliases.each do |a|
        line "alias #{a.name}"
      end
    end
    #line "\#@TODO rewrite me"
    line
    @f.puts format_elements(m.comment)
    line
  end

  def trim_space(s)
    s.sub(/\(\s+/, '(').sub(/\s+\)/, ')').sub(/\(\)/, '')
  end

  def format_elements(elems)
    return "" unless elems
    return "" if elems.empty?
    elems.map {|elem| format_element(elem) }.join("\n\n")
  end

  def format_element(e)
    case e
    when SM::Flow::P, SM::Flow::LI
      paragraph(e)
    when SM::Flow::LIST
      list(e)
    when SM::Flow::VERB
      verbatim(e)
    when SM::Flow::H
      headline(e)
    when SM::Flow::RULE
      ;
    else
      raise "unkwnown markup: #{e.class}"
    end
  end

  def headline(e)
    h = '==' + ('=' * e.level)
    text = unescape(e.text)
    "#{h} #{text}"
  end

  def paragraph(e)
    wrap(unescape(remove_inline(e.body)))
  end

  def verbatim(e)
    unescape(e.body.rstrip) #.gsub(/^/, '    ')
  end

  def list(e)
    case e.type
    when SM::ListBase::BULLET
      e.contents.map {|item| "* #{format_element(e)}" }.join("\n")
    when SM::ListBase::NUMBER,
         SM::ListBase::LOWERALPHA,
         SM::ListBase::UPPERALPHA
      num = case e.type
            when SM::ListBase::NUMBER     then '1'
            when SM::ListBase::LOWERALPHA then 'a'
            when SM::ListBase::UPPERALPHA then 'A'
            end
      e.contents.map {|item|
        str = "#{num}. #{format_element(e)}"
        num = num.succ
        str
      }.join("\n")
    when SM::ListBase::LABELED
      e.contents.map {|item| "#{item.label} #{format_element(e)}" }.join("\n")
    when SM::ListBase::NOTE
      e.contents.map {|item| "#{item.label}\t#{format_element(e)}" }.join("\n")
    else
      raise "unknown list type: #{e.type.inspect}"
    end
  end

  def remove_inline(str)
    str.gsub(/<\/?\w+>/, '')
  end

  def wrap(str)
    width = 60
    buf = ''
    line = ''
    str.split.each do |chunk|
      line << chunk << ' '
      if line.size > width
        buf << line.strip << "\n"
        line = ''
      end
    end
    buf << line
    buf.strip
  end

end

main
