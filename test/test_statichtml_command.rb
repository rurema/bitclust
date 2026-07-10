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
      cmd = build_command(themedir, outputdir)
      cmd.send(:copy_run_ruby_wasm_script)
      assert_true(File.file?(File.join(outputdir, 'js', 'run.js')))
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
      ensure
        $stderr = orig_stderr
      end
      assert_false(File.exist?(File.join(outputdir, 'js', 'run.js')))
    end
  end
end
