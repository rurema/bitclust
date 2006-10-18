#!/usr/bin/env ruby

require 'rdoc/ri/ri_reader'
require 'rdoc/ri/ri_cache'
require 'rdoc/ri/ri_paths'
require 'rdoc/markup/simple_markup/fragments'
require 'stringio'
require 'optparse'

class ApplicationError < StandardError; end

def main
  Signal.trap(:PIPE, 'EXIT')
  Signal.trap(:INT, 'EXIT')

  mode = :listcontent
  parser = OptionParser.new
  parser.banner = "Usage: #{File.basename($0)} <classname>"
  parser.on('-l', '--list', 'list method names.'){
    mode = :listname
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
  unless ARGV.size == 1
    $stderr.puts "arg must be 1"
    exit 1
  end
  target_class = ARGV[0]

  path = RI::Paths.path(true, false, false, false)
  reader = RI::RiReader.new(RI::RiCache.new(path))
  c = lookup_class(reader, target_class)
  case mode
  when :listname
    c.method_entries.each do |m|
      puts m.fullname
    end
  when :listcontent
    fmt = Formatter.new
    c.method_entries.each do |m|
      puts fmt.method_info(reader.get_method(m))
    end
  else
    raise "must not happen: #{mode.inspect}"
  end
rescue Errno::EPIPE
  exit 1
rescue ApplicationError => err
  $stderr.puts err.message
  exit 1
end

def lookup_class(reader, name)
  nss = reader.lookup_namespace_in(name, reader.top_level_namespace)
  nss.detect {|ns| ns.full_name == name } or
      raise ApplicationError, "no such class: #{name}"
end


module RI

  class ClassEntry   # reopen
    def method_entries
      @class_methods.sort_by {|m| m.name } +
      @instance_methods.sort_by {|m| m.name }
    end
  end

  class MethodEntry   # reopen
    def fullname
      "#{@in_class.full_name}#{@is_class_method ? '.' : '#'}#{@name}"
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
      e.contents.each do |item|
        "* #{format_element(e)}"
      end
    when SM::ListBase::NUMBER,
         SM::ListBase::LOWERALPHA,
         SM::ListBase::UPPERALPHA
      num = case e.type
            when SM::ListBase::NUMBER     then '1'
            when SM::ListBase::LOWERALPHA then 'a'
            when SM::ListBase::UPPERALPHA then 'A'
            end
      e.contents.each do |item|
        "#{num}. #{format_element(e)}"
        num = num.succ
      end
    when SM::ListBase::LABELED
      e.contents.each do |item|
        "#{item.label} #{format_element(e)}"
      end
    when SM::ListBase::NOTE
      e.contents.each do |item|
        "#{item.label}\t#{format_element(e)}"
      end
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
