# -*- coding: utf-8 -*-

require 'bitclust'
require 'bitclust/subcommand'

require 'fileutils'
# TODO Remove this line when we drop 1.8 support
require 'kconv'
require 'bitclust/progress_bar'

module BitClust
  module Subcommands
    class ChmCommand < Subcommand

      HHP_SKEL = <<EOS
[OPTIONS]
Compatibility=1.1 or later
Compiled file=refm.chm
Contents file=refm.hhc
Default Window=titlewindow
Default topic=doc/index.html
Display compile progress=No
Error log file=refm.log
Full-text search=Yes
Index file=refm.hhk
Language=0x411 日本語 (日本)
Title=Rubyリファレンスマニュアル

[WINDOWS]
titlewindow="Rubyリファレンスマニュアル","refm.hhc","refm.hhk","doc/index.html","doc/index.html",,,,,0x21420,,0x387e,,,,,,,,0

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

      class URLMapperEx < URLMapper
        def library_url(name)
          if name == '/'
            "/library/index.html"
          else
            "/library/#{encodename_fs(name)}.html"
          end
        end

        def class_url(name)
          "/class/#{encodename_fs(name)}.html"
        end

        def method_url(spec)
          cname, tmark, mname = *split_method_spec(spec)
          "/method/#{encodename_fs(cname)}/#{typemark2char(tmark)}/#{encodename_fs(mname)}.html"
        end

        def document_url(name)
          "/doc/#{encodename_fs(name)}.html"
        end
      end

      def initialize
        super
        @sitemap = {
          :library => Sitemap.new('ライブラリ', 'library/index.html'),
        }
        @sitemap[:library] << Sitemap::Content.new('標準ライブラリ', 'library/_builtin.html')
        @sitemap[:library] << Sitemap::Content.new('添付ライブラリ')
        @stdlibs = {}
        @index_contents = []
        @parser.banner = "Usage: #{File.basename($0, '.*')} chm [options]"
        @parser.on('-o', '--outputdir=PATH', 'Output directory') do |path|
          begin
            @outputdir = Pathname.new(path).realpath
          rescue Errno::ENOENT
            FileUtils.mkdir_p(path, :verbose => true)
            retry
          end
        end
      end

      def exec(argv, options)
        create_manager_config
        prefix = options[:prefix]
        db = MethodDatabase.new(prefix.to_s)
        manager = ScreenManager.new(@manager_config)
        @html_files = []
        db.transaction do
          methods = {}
          db.methods.each do |entry|
            method_name = entry.klass.name + entry.typemark + entry.name
            (methods[method_name] ||= []) << entry
          end

          entries = db.docs + db.libraries.sort + db.classes.sort + methods.values.sort
          pb = ProgressBar.new('entry', entries.size)
          entries.each do |c|
            filename = create_html_file(c, manager, @outputdir, db)
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
        create_file(@outputdir + 'refm.hhp', HHP_SKEL, true)
        create_file(@outputdir + 'refm.hhc', HHC_SKEL, true)
        create_file(@outputdir + 'refm.hhk', HHK_SKEL, true)
        create_file(@outputdir + 'library/index.html', manager.library_index_screen(db.libraries.sort, {:database => db}).body)
        create_file(@outputdir + 'class/index.html', manager.class_index_screen(db.classes.sort, {:database => db}).body)
        FileUtils.cp(@manager_config[:themedir] + @manager_config[:css_url],
                     @outputdir.to_s, {:verbose => true, :preserve => true})
      end

      private

      def create_manager_config
        @manager_config = {
          :baseurl     => 'http://example.com/',
          :suffix      => '.html',
          :templatedir => srcdir_root + 'data'+ 'bitclust' + 'template',
          :themedir    => srcdir_root + 'theme' + 'default',
          :css_url     => 'style.css',
          :cgi_url     => '',
          :tochm_mode  => true
        }
        @manager_config[:urlmapper] = URLMapperEx.new(@manager_config)
      end

      def create_html_file(entry, manager, outputdir, db)
        html = manager.entry_screen(entry, {:database => db}).body
        e = entry.is_a?(Array) ? entry.sort.first : entry
        path = case e.type_id
               when :library, :class, :doc
                 outputdir + e.type_id.to_s + (NameUtils.encodename_fs(e.name) + '.html')
               when :method
                 outputdir + e.type_id.to_s + NameUtils.encodename_fs(e.klass.name) +
                   e.typechar + (NameUtils.encodename_fs(e.name) + '.html')
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
        $stderr.print("creating #{path} ...")
        str = ERB.new(skel).result(binding)
        # TODO Use String#encode when we drop 1.8 support
        str = str.tosjis if sjis_flag
        path.open('w') do |f|
          f.write(str)
        end
        $stderr.puts(" done.")
      end
    end
  end
end
