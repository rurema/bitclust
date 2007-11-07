require 'rdoc/ri/ri_reader'
require 'rdoc/ri/ri_cache'
require 'rdoc/ri/ri_paths'

class ApplicationError < StandardError; end
class RiClassNotFound < ApplicationError; end

class RiDatabase
  def RiDatabase.open_system_db
    new(RI::Paths.path(true, false, false, false), RUBY_VERSION)
  end

  def RiDatabase.open(dir, version)
    new(RI::Paths.path(false, false, false, false, dir), version)
  end

  def initialize(ripath, version)
    @ripath = ripath
    @reader = RI::RiReader.new(RI::RiCache.new(@ripath))
    @version = version
  end

  attr_reader :version

  def get_method(m)
    @reader.get_method(m)
  end

  def current_class=(name)
    @klass = lookup_class(name)
    @singleton_methods = wrap_entries(@reader.singleton_methods(@klass))
    @instance_methods = wrap_entries(@reader.instance_methods(@klass))
  rescue RiClassNotFound
    @klass = nil
    @singleton_methods = []
    @instance_methods = []
  end

  attr_reader :class
  attr_reader :singleton_methods
  attr_reader :instance_methods

  def lookup_class(name)
    ns = @reader.top_level_namespace.first
    name.split('::').each do |const|
      ns = ns.contained_class_named(const) or
          raise RiClassNotFound, "no such class in RDoc database: #{name}"
    end
    ns
  end

  private

  def wrap_entries(ents)
    ents.map {|m|
      [RiMethodEntry.new(m.name, m)] +
      m.aliases.map {|a| RiMethodEntry.new(a.name, m) }
    }.flatten.uniq
  end
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

  def id
    if @entry.defined?
      fullname()
    else
      "#{fullname()}.#{@entry.library.name}"
    end
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
        line "--- #{trim_sig(sig)}\#@todo\n"
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

  def trim_sig(s)
    s = trim_space(s)
    s.sub!(/\A[a-z]\w+\./, '')
    s.sub!(/=>/, '->')
    s.sub!(/(->.*)\bstr(ing)?\b/){ $1 + 'String' }
    s.sub!(/(->.*)\bint(eger)?\b/){ $1 + 'Integer' }
    s.sub!(/(->.*)\b(an_)?obj\b/){ $1 + 'object' }
    s.sub!(/(->.*)\b(a_)?hash\b/){ $1 + 'Hash' }
    s.sub!(/(->.*)\b(an_)?array\b/){ $1 + 'Array' }
    s.sub!(/ or /, ' | ')    
    s
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
