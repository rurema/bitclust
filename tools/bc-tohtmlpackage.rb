#!/usr/bin/env ruby
# -*- coding: euc-jp -*-
require 'pathname'

def srcdir_root
  (Pathname.new(__FILE__).realpath.dirname + '..').cleanpath
end
$LOAD_PATH.unshift srcdir_root() + 'lib'

require 'bitclust'
require 'fileutils'
require 'optparse'

module BitClust

  class URLMapperEx < URLMapper
    def library_url(name)
      if name == '/'
        $bitclust_html_base + "/library/index.html"
      else
        $bitclust_html_base + "/library/#{encodename_package(name)}.html"
      end
    end

    def class_url(name)
      $bitclust_html_base + "/class/#{encodename_package(name)}.html"
    end

    def method_url(spec)
      cname, tmark, mname = *split_method_spec(spec)
      $bitclust_html_base +
        "/method/#{encodename_package(cname)}/#{typemark2char(tmark)}/#{encodename_package(mname)}.html"
    end

    def function_url(name)
      $bitclust_html_base + "/function/#{name.empty? ? 'index' : name}.html"
    end

    def document_url(name)
      $bitclust_html_base + "/doc/#{encodename_package(name)}.html"
    end

    def css_url
      $bitclust_html_base + "/" + @css_url
    end

    def favicon_url
      $bitclust_html_base + "/" + @favicon_url
    end

    def library_index_url
      $bitclust_html_base + "/library/index.html"
    end

    def function_index_url
      $bitclust_html_base + "/function/index.html"
    end

  end
end

def main
  prefix = Pathname.new('./db')
  outputdir = Pathname.new('./doc')
  templatedir = srcdir_root + 'data'+ 'bitclust' + 'template'
  catalogdir = nil
  verbose = true
  parser = OptionParser.new
  parser.on('-d', '--database=PATH', 'Database prefix') do |path|
    prefix = Pathname.new(path).realpath
  end
  parser.on('-o', '--outputdir=PATH', 'Output directory') do |path|
    begin
      outputdir = Pathname.new(path).realpath
    rescue Errno::ENOENT
      FileUtils.mkdir_p(path, :verbose => verbose)
      retry
    end
  end
  parser.on('--catalog=PATH', 'Catalog directory') do |path|
    catalogdir = Pathname.new(path).realpath
  end
  parser.on('--templatedir=PATH', 'Template directory') do |path|
    templatedir = Pathname.new(path).realpath
  end
  parser.on('--fs-casesensitive', 'Filesystem is case-sensitive') do
    $fs_casesensitive = true
  end
  parser.on('--[no-]quiet', 'Be quiet') do |quiet|
    verbose = !quiet
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
    :catalogdir => catalogdir,
    :suffix => '.html',
    :templatedir => templatedir,
    :themedir => srcdir_root + 'theme' + 'default',
    :css_url => 'style.css',
    :favicon_url => 'rurema.png',
    :cgi_url => '',
    :tochm_mode => true
  }
  manager_config[:urlmapper] = BitClust::URLMapperEx.new(manager_config)

  db = BitClust::MethodDatabase.new(prefix.to_s)
  fdb = BitClust::FunctionDatabase.new(prefix.to_s)
  manager = BitClust::ScreenManager.new(manager_config)
  db.transaction do
    methods = {}
    db.methods.each_with_index do |entry, i|
      method_name = entry.klass.name + entry.typemark + entry.name
      (methods[method_name] ||= []) << entry
    end
    entries = db.docs + db.libraries.sort + db.classes.sort + methods.values
    entries.each_with_index do |c, i|
      create_html_file(c, manager, outputdir, db)
      $stderr.puts("#{i}/#{entries.size} done") if i % 100 == 0 and verbose
    end
  end
  fdb.transaction do
    functions = {}
    fdb.functions.each_with_index do |entry, i|
      create_html_file(entry, manager, outputdir, fdb)
      $stderr.puts("#{i} done") if i % 100 == 0 and verbose
    end
  end
  $bitclust_html_base = '..'
  create_file(outputdir + 'library/index.html',
              manager.library_index_screen(db.libraries.sort, {:database => db}).body,
              :verbose => verbose)
  create_file(outputdir + 'class/index.html',
              manager.class_index_screen(db.classes.sort, {:database => db}).body,
              :verbose => verbose)
  create_file(outputdir + 'function/index.html',
              manager.function_index_screen(fdb.functions.sort, { :database => fdb }).body,
              :verbose => verbose)
  create_index_html(outputdir)
  FileUtils.cp(manager_config[:themedir] + manager_config[:css_url],
               outputdir.to_s, {:verbose => verbose, :preserve => true})
  FileUtils.cp(manager_config[:themedir] + manager_config[:favicon_url],
               outputdir.to_s, {:verbose => verbose, :preserve => true})
  FileUtils.cp_r(manager_config[:themedir] + 'images',
                 outputdir.to_s, {:verbose => verbose, :preserve => true})
end

def encodename_package(str)
  if $fs_casesensitive
    BitClust::NameUtils.encodename_url(str)
  else
    BitClust::NameUtils.encodename_fs(str)
  end
end

def create_index_html(outputdir)
  path = outputdir + 'index.html'
  File.open(path, 'w'){|io|
    io.write <<HERE
<meta http-equiv="refresh" content="0; URL=doc/index.html">
<a href="doc/index.html">Go</a>
HERE
  }
end

def create_html_file(entry, manager, outputdir, db)
  e = entry.is_a?(Array) ? entry.sort.first : entry
  case e.type_id
  when :library, :class, :doc
    $bitclust_html_base = '..'
    path = outputdir + e.type_id.to_s + (encodename_package(e.name) + '.html')
    create_html_file_p(entry, manager, path, db)
    path.relative_path_from(outputdir).to_s
  when :method
    create_html_method_file(entry, manager, outputdir, db)
  when :function
    create_html_function_file(entry, manager, outputdir, db)
  else
    raise
  end
end

def create_html_method_file(entry, manager, outputdir, db)
  path = nil
  $bitclust_html_base = '../../..'
  e = entry.is_a?(Array) ? entry.sort.first : entry
  e.names.each{|name|
    path = outputdir + e.type_id.to_s + encodename_package(e.klass.name) +
           e.typechar + (encodename_package(name) + '.html')
    create_html_file_p(entry, manager, path, db)
  }
  path.relative_path_from(outputdir).to_s
end

def create_html_function_file(entry, manager, outputdir, db)
  path = nil
  $bitclust_html_base = '..'
  path = outputdir + entry.type_id.to_s + (entry.name + '.html')
  create_html_file_p(entry, manager, path, db)
  path.relative_path_from(outputdir).to_s
end

def create_html_file_p(entry, manager, path, db)
    FileUtils.mkdir_p(path.dirname) unless path.dirname.directory?
    html = manager.entry_screen(entry, {:database => db}).body
    path.open('w') do |f|
      f.write(html)
    end
end

def create_file(path, str, options={})
  verbose = options[:verbose]
  STDERR.print("creating #{path} ...") if verbose
  path.open('w') do |f|
    f.write(str)
  end
  STDERR.puts(" done.") if verbose
end

main
