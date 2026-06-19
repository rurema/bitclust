# frozen_string_literal: true
require 'test/unit'
require 'json'
require 'fileutils'
require 'bitclust'
require 'bitclust/methoddatabase'
require 'bitclust/search_index_generator'

class TestSearchIndexGenerator < Test::Unit::TestCase
  def setup
    @prefix = 'db_si'
    @base = 'tree_si'
    @root = "#{@base}/refm/api/src"
    setup_files
    @db = BitClust::MethodDatabase.new(@prefix)
    @db.init
    @db.transaction do
      [%w[version 3.4], %w[encoding utf-8]].each do |k, v|
        @db.propset(k, v)
      end
    end
    @db.transaction do
      @db.update_by_stdlibtree(@root)
    end
    @gen = BitClust::SearchIndexGenerator.new
  end

  def teardown
    FileUtils.rm_r([@prefix, @base], :force => true)
  end

  def find_entry(index, full_name)
    index.find { |e| e[:full_name] == full_name }
  end

  def test_class_entry
    index = @gen.build_index(@db)
    e = find_entry(index, 'Foo')
    assert_not_nil e
    assert_equal 'Foo', e[:name]
    assert_equal 'class', e[:type]
    assert_equal 'class/-foo.html', e[:path]
  end

  def test_module_entry_type
    index = @gen.build_index(@db)
    e = find_entry(index, 'Kernel')
    assert_not_nil e
    assert_equal 'module', e[:type]
    assert_equal 'class/-kernel.html', e[:path]
  end

  def test_instance_method_entry
    index = @gen.build_index(@db)
    e = find_entry(index, 'Foo#foo')
    assert_not_nil e
    assert_equal 'foo', e[:name]
    assert_equal 'instance_method', e[:type]
    assert_equal 'method/-foo/i/foo.html', e[:path]
  end

  def test_module_function_is_class_method
    index = @gen.build_index(@db)
    e = find_entry(index, 'Kernel.#at_exit')
    assert_not_nil e
    assert_equal 'at_exit', e[:name]
    assert_equal 'class_method', e[:type]
    assert_equal 'method/-kernel/m/at_exit.html', e[:path]
  end

  def test_constant_entry
    index = @gen.build_index(@db)
    e = find_entry(index, 'Foo::AAA')
    assert_not_nil e
    assert_equal 'AAA', e[:name]
    assert_equal 'constant', e[:type]
    assert_equal 'method/-foo/c/-a-a-a.html', e[:path]
  end

  def test_same_method_name_in_two_classes
    index = @gen.build_index(@db)
    assert_not_nil find_entry(index, 'Foo#foo')
    assert_not_nil find_entry(index, 'Bar#foo')
  end

  def test_no_duplicate_paths
    index = @gen.build_index(@db)
    paths = index.map { |e| e[:path] }
    assert_equal paths.uniq.size, paths.size, 'index must not contain duplicate paths'
  end

  def test_document_entry_uses_title_and_slug
    index = @gen.build_index(@db)
    e = index.find { |x| x[:type] == 'document' && x[:path] == 'doc/glossary.html' }
    assert_not_nil e
    assert_equal 'Ruby用語集 (glossary)', e[:full_name]
    assert_equal 'Ruby用語集 (glossary)', e[:name]
  end

  def test_to_js_format
    js = @gen.to_js(@db)
    assert_match(/\Avar search_data = \{/, js)
    assert(js.end_with?(';'), 'to_js output must end with a semicolon')

    json = js.sub(/\Avar search_data = /, '').sub(/;\z/, '')
    data = JSON.parse(json)
    assert_kind_of Array, data['index']
    assert(data['index'].any? { |e| e['full_name'] == 'Foo#foo' })
  end

  private

  def setup_files
    FileUtils.mkdir_p("#{@root}/_builtin")

    File.open("#{@root}/LIBRARIES", 'w+') do |file|
      file.puts '_builtin'
    end

    File.open("#{@root}/_builtin.rd", 'w+') do |file|
      file.puts <<'HERE'
description

= class Foo < Object
description
== Instance Methods
--- foo
== Constants
--- AAA
= class Bar < Object
== Instance Methods
--- foo
= module Kernel
description
== Module Functions
--- at_exit{ ... } -> Proc
aaa

HERE
    end

    # Prose doc pages are loaded from <stdlibtree>/../../doc/**/*.rd
    docdir = "#{@base}/refm/doc"
    FileUtils.mkdir_p(docdir)
    File.open("#{docdir}/glossary.rd", 'w+') do |file|
      file.puts '= Ruby用語集'
      file.puts
      file.puts '用語の説明。'
    end
  end
end
