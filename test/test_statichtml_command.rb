require 'test/unit'
require 'tmpdir'
require 'stringio'
require 'bitclust'
require 'bitclust/subcommands/statichtml_command'

class TestStatichtmlURLMapperEx < Test::Unit::TestCase
  def setup
    @urlmapper = BitClust::Subcommands::StatichtmlCommand::URLMapperEx.new(
      :suffix => 'html',
      :edit_base_url => 'https://github.com/rurema/doctree/edit/master',
    )
  end

  # The edit URL must not contain a line number, so that shifting source lines
  # does not churn the generated HTML diff.
  def test_edit_url_has_no_line_number
    location = BitClust::Location.new('refm/api/src/_builtin/Array', 42)
    assert_equal('https://github.com/rurema/doctree/edit/master/refm/api/src/_builtin/Array',
                 @urlmapper.edit_url(location))
  end

  # A location restored from the database has no line number (nil); the edit URL
  # must still be a clean file link without a trailing "#L".
  def test_edit_url_without_line_in_location
    location = BitClust::Location.new('refm/api/src/_builtin/Array', nil)
    assert_equal('https://github.com/rurema/doctree/edit/master/refm/api/src/_builtin/Array',
                 @urlmapper.edit_url(location))
  end
end

class TestStatichtmlRunRubyWasm < Test::Unit::TestCase
  def build_command(themedir, outputdir)
    cmd = BitClust::Subcommands::StatichtmlCommand.new
    cmd.instance_variable_set(:@manager_config, { :themedir => Pathname.new(themedir) })
    cmd.instance_variable_set(:@outputdir, Pathname.new(outputdir))
    cmd.instance_variable_set(:@verbose, false)
    cmd
  end

  def test_option_defaults_to_nil
    cmd = BitClust::Subcommands::StatichtmlCommand.new
    assert_nil(cmd.instance_variable_get(:@run_ruby_wasm))
  end

  def test_option_is_parsed
    url = 'https://cdn.jsdelivr.net/npm/@ruby/3.4-wasm-wasi@2.9.3-2.9.4/dist/ruby+stdlib.wasm'
    cmd = BitClust::Subcommands::StatichtmlCommand.new
    cmd.parse(["--run-ruby-wasm=#{url}"])
    assert_equal(url, cmd.instance_variable_get(:@run_ruby_wasm))
  end

  def test_run_js_is_copied
    Dir.mktmpdir do |dir|
      themedir = File.join(dir, 'theme')
      outputdir = File.join(dir, 'out')
      FileUtils.mkdir_p(File.join(themedir, 'js'))
      FileUtils.mkdir_p(outputdir)
      File.write(File.join(themedir, 'js', 'run.js'), "// run\n")
      File.write(File.join(themedir, 'js', 'run-worker.js'), "// worker\n")
      cmd = build_command(themedir, outputdir)
      cmd.send(:copy_run_ruby_wasm_script)
      assert_true(File.file?(File.join(outputdir, 'js', 'run.js')))
      assert_true(File.file?(File.join(outputdir, 'js', 'run-worker.js')))
    end
  end

  def test_theme_without_run_js_is_tolerated
    Dir.mktmpdir do |dir|
      themedir = File.join(dir, 'theme')
      outputdir = File.join(dir, 'out')
      FileUtils.mkdir_p(themedir)
      FileUtils.mkdir_p(outputdir)
      cmd = build_command(themedir, outputdir)
      orig_stderr, $stderr = $stderr, StringIO.new
      begin
        assert_nothing_raised { cmd.send(:copy_run_ruby_wasm_script) }
        assert_match(/run\.js not found/, $stderr.string)
        assert_match(/run-worker\.js not found/, $stderr.string)
      ensure
        $stderr = orig_stderr
      end
      assert_false(File.exist?(File.join(outputdir, 'js', 'run.js')))
      assert_false(File.exist?(File.join(outputdir, 'js', 'run-worker.js')))
    end
  end

  # A themedir with run.js but not yet upgraded with run-worker.js (or vice
  # versa) should still copy whichever file it does have, rather than
  # aborting or silently skipping both.
  def test_partial_theme_copies_what_it_has
    Dir.mktmpdir do |dir|
      themedir = File.join(dir, 'theme')
      outputdir = File.join(dir, 'out')
      FileUtils.mkdir_p(File.join(themedir, 'js'))
      FileUtils.mkdir_p(outputdir)
      File.write(File.join(themedir, 'js', 'run.js'), "// run\n")
      cmd = build_command(themedir, outputdir)
      orig_stderr, $stderr = $stderr, StringIO.new
      begin
        cmd.send(:copy_run_ruby_wasm_script)
        assert_match(/run-worker\.js not found/, $stderr.string)
      ensure
        $stderr = orig_stderr
      end
      assert_true(File.file?(File.join(outputdir, 'js', 'run.js')))
      assert_false(File.exist?(File.join(outputdir, 'js', 'run-worker.js')))
    end
  end
end

class TestStatichtmlSitemap < Test::Unit::TestCase
  def build_command(outputdir)
    cmd = BitClust::Subcommands::StatichtmlCommand.new
    cmd.instance_variable_set(:@outputdir, Pathname.new(outputdir))
    cmd.instance_variable_set(:@verbose, false)
    cmd
  end

  def test_option_defaults_to_nil
    cmd = BitClust::Subcommands::StatichtmlCommand.new
    assert_nil(cmd.instance_variable_get(:@sitemap_baseurl))
  end

  def test_option_is_parsed
    cmd = BitClust::Subcommands::StatichtmlCommand.new
    cmd.parse(['--sitemap-baseurl=https://docs.ruby-lang.org/ja/3.4/'])
    assert_equal('https://docs.ruby-lang.org/ja/3.4/',
                 cmd.instance_variable_get(:@sitemap_baseurl))
  end

  def test_record_sitemap_path_is_noop_without_baseurl
    Dir.mktmpdir do |dir|
      cmd = build_command(dir)
      cmd.send(:record_sitemap_path, Pathname.new(dir) + 'class' + 'String.html')
      assert_empty(cmd.instance_variable_get(:@sitemap_paths))
    end
  end

  def test_record_sitemap_path_keeps_relative_path
    Dir.mktmpdir do |dir|
      cmd = build_command(dir)
      cmd.instance_variable_set(:@sitemap_baseurl, 'https://docs.ruby-lang.org/ja/3.4/')
      cmd.send(:record_sitemap_path, Pathname.new(dir) + 'class' + 'String.html')
      assert_equal(%w[class/String.html], cmd.instance_variable_get(:@sitemap_paths))
    end
  end

  def test_create_sitemap_writes_loc_urls
    Dir.mktmpdir do |dir|
      cmd = build_command(dir)
      cmd.instance_variable_set(:@sitemap_paths,
                                 ['class/String.html', 'method/String/i/upcase.html'])
      cmd.send(:create_sitemap, Pathname.new(dir), 'https://docs.ruby-lang.org/ja/3.4/')
      xml = File.read(File.join(dir, 'sitemap.xml'))
      assert_match(%r{\A<\?xml version="1\.0" encoding="UTF-8"\?>\n}, xml)
      assert_match(%r{<urlset xmlns="http://www\.sitemaps\.org/schemas/sitemap/0\.9">}, xml)
      assert_match(%r{<url><loc>https://docs\.ruby-lang\.org/ja/3\.4/class/String\.html</loc></url>}, xml)
      assert_match(%r{<url><loc>https://docs\.ruby-lang\.org/ja/3\.4/method/String/i/upcase\.html</loc></url>}, xml)
      assert_match(%r{</urlset>\n\z}, xml)
    end
  end

  def test_create_sitemap_adds_trailing_slash_to_baseurl
    Dir.mktmpdir do |dir|
      cmd = build_command(dir)
      cmd.instance_variable_set(:@sitemap_paths, ['class/String.html'])
      cmd.send(:create_sitemap, Pathname.new(dir), 'https://docs.ruby-lang.org/ja/3.4')
      xml = File.read(File.join(dir, 'sitemap.xml'))
      assert_match(%r{<loc>https://docs\.ruby-lang\.org/ja/3\.4/class/String\.html</loc>}, xml)
    end
  end

  def test_create_sitemap_escapes_special_characters
    Dir.mktmpdir do |dir|
      cmd = build_command(dir)
      cmd.instance_variable_set(:@sitemap_paths, ['method/String/i/=3d=3d.html'])
      cmd.send(:create_sitemap, Pathname.new(dir), 'https://example.com/a&b/')
      xml = File.read(File.join(dir, 'sitemap.xml'))
      assert_match(%r{<loc>https://example\.com/a&amp;b/method/String/i/=3d=3d\.html</loc>}, xml)
      assert_not_match(/a&b/, xml)
    end
  end

  def test_create_sitemap_warns_and_truncates_beyond_limit
    Dir.mktmpdir do |dir|
      cmd = build_command(dir)
      limit = BitClust::Subcommands::StatichtmlCommand::MAX_SITEMAP_URLS
      paths = (1..(limit + 1)).map {|i| "class/C#{i}.html" }
      cmd.instance_variable_set(:@sitemap_paths, paths)
      orig_stderr, $stderr = $stderr, StringIO.new
      begin
        cmd.send(:create_sitemap, Pathname.new(dir), 'https://example.com/')
        assert_match(/warning:.*#{limit}/, $stderr.string)
      ensure
        $stderr = orig_stderr
      end
      xml = File.read(File.join(dir, 'sitemap.xml'))
      assert_equal(limit, xml.scan('<url>').size)
      assert_match(%r{<loc>https://example\.com/class/C1\.html</loc>}, xml)
      assert_not_match(/C#{limit + 1}\.html/, xml)
    end
  end
end
