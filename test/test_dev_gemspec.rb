# frozen_string_literal: true
require 'test/unit'
require 'rbconfig'
require 'tmpdir'
require 'fileutils'
require 'open3'

class TestDevGemspec < Test::Unit::TestCase
  ROOT = File.expand_path('..', __dir__)
  TOOLS = %w[forall-ruby.rb gencatalog.rb md-db-check.rb md-tree-check.rb].freeze

  def setup
    @spec = Dir.chdir(ROOT) { Gem::Specification.load('bitclust-dev.gemspec') }
  end

  def test_executables_are_listed_explicitly
    assert_equal(TOOLS, @spec.executables.sort)
  end

  def test_files_are_the_executables_only
    assert_equal(TOOLS.map {|name| "tools/#{name}" }, @spec.files.sort)
  end

  def test_executables_exist_and_are_executable
    @spec.executables.each do |name|
      path = File.join(ROOT, @spec.bindir, name)
      assert_true(File.executable?(path), path)
    end
  end

  # gem として入れると tools/ の隣に lib/ は無い(lib は bitclust-core 側)
  def test_forall_ruby_runs_without_sibling_lib
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, 'tools'))
      tool = File.join(dir, 'tools', 'forall-ruby.rb')
      FileUtils.cp(File.join(ROOT, 'tools', 'forall-ruby.rb'), tool)
      out, status = Open3.capture2e(RbConfig.ruby, '-I', File.join(ROOT, 'lib'), tool, '-e', 'print 1 + 1')
      assert_true(status.success?, out)
      assert_match(/^2$/, out)
    end
  end
end
