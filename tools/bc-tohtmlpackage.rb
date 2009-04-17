#!/usr/bin/env ruby
# -*- coding: euc-jp -*-
require 'pathname'
def srcdir_root
  (Pathname.new(__FILE__).realpath.dirname + '..').cleanpath
end

$LOAD_PATH.unshift srcdir_root() + 'lib'

#def srcdir_root
#  #Pathname.new(__FILE__).realpath.dirname.parent.cleanpath
#  Pathname.new(__FILE__).dirname.parent.cleanpath
#end
#$LOAD_PATH.unshift srcdir_root + 'lib'

require 'bitclust'
require 'erb'
require 'fileutils'
require 'kconv'
require 'optparse'
begin
  require 'progressbar'
rescue LoadError
  class ProgressBar
    def initialize(title, total, out = STDERR)
      @title, @total, @out = title, total, out
    end
    attr_reader :title

    def inc(step = 1)
    end

    def finish
    end
  end
end

class Sitemap
  def initialize(name, local = nil)
    @name = name
    @contents = Content.new(name, local)
  end

  def method_missing(name, *args, &block)
    @contents.send(name, *args, &block)
  end

  class Content
    include Enumerable
    include ERB::Util

    def initialize(name, local = nil)
      @name = name
      @local = local
      @contents = []
    end
    attr_reader :name, :local, :contents

    def [](index)
      @contents[index]
    end

    def <<(content)
      @contents << content
    end

    def <=>(other)
      @name <=> other.name
    end

    def each
      @contents.each do |content|
        yield content
      end
    end

    def to_html
      str = "<LI> <OBJECT type=\"text/sitemap\">\n"
      str << "        <param name=\"Name\" value=\"<%=h @name%>\">\n"
      if @local
        str << "        <param name=\"Local\" value=\"<%=@local%>\">\n"
      end
      str << "        </OBJECT>\n"
      unless contents.empty?
        str << "<UL>\n"
        @contents.each do |content|
          str << content.to_html
        end
        str << "</UL>\n"
      end
      ERB.new(str).result(binding)
    end
  end
end

module BitClust

  class URLMapperEx < URLMapper
    def library_url(name)
      if name == '/'
        $bitclust_htm_base + "/library/index.html"
      else
        $bitclust_htm_base + "/library/#{encodename_fs(name)}.html"
      end
    end

    def class_url(name)
      $bitclust_htm_base + "/class/#{encodename_fs(name)}.html"
    end

    def method_url(spec)
      cname, tmark, mname = *split_method_spec(spec)
      $bitclust_htm_base + "/method/#{encodename_fs(cname)}/#{typemark2char(tmark)}/#{encodename_fs(mname)}.html"
    end

    def document_url(name)
      $bitclust_htm_base + "/doc/#{encodename_fs(name)}.html"
    end

    def css_url
      $bitclust_htm_base + "/" + @css_url
    end

    def library_index_url
      $bitclust_htm_base + "/library/index.html"
    end

  end
end

def main
  @sitemap = {
    :library => Sitemap.new('ライブラリ', 'library/index.html'),
  }
  @sitemap[:library] << Sitemap::Content.new('標準ライブラリ', 'library/_builtin.html')
  @sitemap[:library] << Sitemap::Content.new('添付ライブラリ')
  @stdlibs = {}
  @index_contents = []
  prefix = Pathname.new('./db')
  outputdir = Pathname.new('./chm')
  catalogdir = nil
  parser = OptionParser.new
  parser.on('-d', '--database=PATH', 'Database prefix') do |path|
    prefix = Pathname.new(path).realpath
  end
  parser.on('-o', '--outputdir=PATH', 'Output directory') do |path|
    outputdir = Pathname.new(path).realpath
  end
  parser.on('-c', '--catalog=PATH', 'Catalog directory') do |path|
    catalogdir = Pathname.new(path).realpath
  end
  parser.on('--help', 'Prints this message and quit') do
    puts(parser.help)
    exit(0)
  end
  begin
    parser.parse!
  rescue OptionParser::ParseError => err
    STDERR.puts(err.message)
    STDERR.puts(parser.help)
    exit(1)
  end

  manager_config = {
#    :baseurl => 'http://example.com/',
    :catalogdir => catalogdir,
    :suffix => '.html',
    :templatedir => srcdir_root + 'data'+ 'bitclust' + 'template',
    :themedir => srcdir_root + 'theme' + 'default',
    :css_url => 'style.css',
    :cgi_url => '',
    :tochm_mode => true
  }
  manager_config[:urlmapper] = BitClust::URLMapperEx.new(manager_config)

  db = BitClust::MethodDatabase.new(prefix.to_s)
  manager = BitClust::ScreenManager.new(manager_config)
  @html_files = []
  db.transaction do
    methods = {}
    pb = ProgressBar.new('method', db.methods.size)
    db.methods.each_with_index do |entry, i|
      method_name = entry.klass.name + entry.typemark + entry.name
      (methods[method_name] ||= []) << entry
      pb.inc    
    end      
    pb.finish
    entries = db.docs + db.libraries.sort + db.classes.sort + methods.values.sort 
    pb = ProgressBar.new('entry', entries.size)
    entries.each_with_index do |c, i|
      filename = create_html_file(c, manager, outputdir, db)
      @html_files << filename
      e = c.is_a?(Array) ? c.sort.first : c
      case e.type_id
      when :library
        content = Sitemap::Content.new(e.name.to_s, filename)
        if e.name.to_s != '_builtin'
          @sitemap[:library][1] << content
          @stdlibs[e.name.to_s] = content
        end
        @index_contents << Sitemap::Content.new(e.name.to_s, filename)
      when :class
        content = Sitemap::Content.new(e.name.to_s, filename)
        if e.library.name.to_s == '_builtin'
          @sitemap[:library][0] << content
        else
          @stdlibs[e.library.name.to_s] << content
        end
        @index_contents << Sitemap::Content.new("#{e.name} (#{e.library.name})", filename)
      when :method
        e.names.each do |e_name|
          name = e.typename == :special_variable ? "$#{e_name}" : e_name
          @index_contents <<
            Sitemap::Content.new("#{name} (#{e.library.name} - #{e.klass.name})", filename)
          @index_contents <<
            Sitemap::Content.new("#{e.klass.name}#{e.typemark}#{name} (#{e.library.name})", filename)
        end
      end
      pb.title.replace(e.name)
      pb.inc
    end
    pb.finish
  end
  @html_files.sort!
  $bitclust_htm_base = '..'
  create_file(outputdir + 'library/index.html', manager.library_index_screen(db.libraries.sort, {:database => db}).body)
  create_file(outputdir + 'class/index.html', manager.class_index_screen(db.classes.sort, {:database => db}).body)
  FileUtils.cp(manager_config[:themedir] + manager_config[:css_url],
               outputdir.to_s, {:verbose => true, :preserve => true})
end

def create_html_file(entry, manager, outputdir, db)
  e = entry.is_a?(Array) ? entry.sort.first : entry
  case e.type_id
  when :library, :class, :doc
    $bitclust_htm_base = '..'
    path = outputdir + e.type_id.to_s +
      (BitClust::NameUtils.encodename_fs(e.name) + '.html')
    FileUtils.mkdir_p(path.dirname) unless path.dirname.directory?
    html = manager.entry_screen(entry, {:database => db}).body
    path.open('w') do |f|
      f.write(html)
    end
    return path.relative_path_from(outputdir).to_s
  when :method
    return create_html_method_file(entry, manager, outputdir, db)
  else
    raise
  end  
end

def create_html_method_file(entry, manager, outputdir, db)
  path = nil
  $bitclust_htm_base = '../../..'
  e = entry.is_a?(Array) ? entry.sort.first : entry
  e.names.each{|name|
    path = outputdir + e.type_id.to_s + BitClust::NameUtils.encodename_fs(e.klass.name) +
    e.typechar + (BitClust::NameUtils.encodename_fs(name) + '.html')
    FileUtils.mkdir_p(path.dirname) unless path.dirname.directory?
    html = manager.entry_screen(entry, {:database => db}).body
    path.open('w') do |f|
      f.write(html)
    end   
  }
  path.relative_path_from(outputdir).to_s
end

def create_file(path, skel, sjis_flag = false)
  STDERR.print("creating #{path} ...")
  str = ERB.new(skel).result(binding)
  str = str.tosjis if sjis_flag
  path.open('w') do |f|
    f.write(str)
  end
  STDERR.puts(" done.")
end

main
