#!/usr/bin/env ruby
# coding: euc-jp
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

HHP_SKEL = <<EOS
[OPTIONS]
Compatibility=1.1 or later
Compiled file=refm.chm
Contents file=refm.hhc
Default Window=titlewindow
Default topic=library/index.html
Display compile progress=No
Error log file=refm.log
Full-text search=Yes
Index file=refm.hhk
Language=0x411 日本語 (日本)
Title=Rubyリファレンスマニュアル

[WINDOWS]
titlewindow="Rubyリファレンスマニュアル","refm.hhc","refm.hhk","library/index.html","library/index.html",,,,,0x21420,,0x387e,,,,,,,,0

[FILES]
<%= @html_files.join("\n") %>
EOS

HHC_SKEL = <<EOS
<!DOCTYPE HTML PUBLIC "-//IETF//DTD HTML//EN">
<HTML>
<HEAD>
</HEAD>
<BODY>
<UL><% [:library].each do |k| %>
<%= @sitemap[k].to_html %>
<% end %></UL>
</BODY>
</HTML>
EOS

HHK_SKEL = <<EOS
<!DOCTYPE HTML PUBLIC "-//IETF//DTD HTML//EN">
<HTML>
<HEAD>
</HEAD>
<BODY>
<UL><% @index_contents.sort.each do |content| %>
<%= content.to_html %>
<% end %></UL>
</BODY>
</HTML>
EOS

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
  class ScreenManagerEx < ScreenManager
    def initialize(h)
      super
      @urlmapper = URLMapperEx.new(h)
    end
  end

  class URLMapperEx < URLMapper
    def library_url(name)
      "/library/#{encodename_fs(name)}.html"
    end

    def class_url(name)
      "/class/#{encodename_fs(name)}.html"
    end

    def method_url(spec)
      cname, tmark, mname = *split_method_spec(spec)
      "/method/#{encodename_fs(cname)}/#{typemark2char(tmark)}/#{encodename_fs(mname)}.html"
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
  manager_config = {
    :baseurl => 'http://example.com/',
    :suffix => '.html',
    :templatedir => srcdir_root + 'template',
    :themedir => srcdir_root + 'theme' + 'default',
    :css_url => 'style.css',
    :cgi_url => '',
    :tochm_mode => true
  }
  parser = OptionParser.new
  parser.on('-d', '--database=PATH', 'Database prefix') do |path|
    prefix = Pathname.new(path).realpath
  end
  parser.on('-o', '--outputdir=PATH', 'Output directory') do |path|
    outputdir = Pathname.new(path).realpath
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

  db = BitClust::Database.new(prefix.to_s)
  #manager = BitClust::ScreenManager.new(manager_config)
  manager_config[:target_version] = db.propget('version')
  manager = BitClust::ScreenManagerEx.new(manager_config)
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
    entries = db.libraries.sort + db.classes.sort + methods.values.sort
    pb = ProgressBar.new('entry', entries.size)
    entries.each_with_index do |c, i|
      filename = create_html_file(c, manager, outputdir)
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
  create_file(outputdir + 'refm.hhp', HHP_SKEL, true)
  create_file(outputdir + 'refm.hhc', HHC_SKEL, true)
  create_file(outputdir + 'refm.hhk', HHK_SKEL, true)
  create_file(outputdir + 'library/index.html', manager.library_index_screen(db.libraries.sort).body)
  create_file(outputdir + 'class/index.html', manager.class_index_screen(db.classes.sort).body)
  FileUtils.cp(manager_config[:themedir] + manager_config[:css_url],
               outputdir.to_s, {:verbose => true, :preserve => true})
end

def create_html_file(entry, manager, outputdir)
  html = manager.entry_screen(entry).body
  e = entry.is_a?(Array) ? entry.sort.first : entry
  path = case e.type_id
         when :library, :class
           outputdir + e.type_id.to_s + (BitClust::NameUtils.encodename_fs(e.name) + '.html')
         when :method
           outputdir + e.type_id.to_s + BitClust::NameUtils.encodename_fs(e.klass.name) +
             e.typechar + (BitClust::NameUtils.encodename_fs(e.name) + '.html')
         else
           raise
         end
  FileUtils.mkdir_p(path.dirname) unless path.dirname.directory?
  path.open('w') do |f|
    f.write(html)
  end
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
