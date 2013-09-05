require 'test/unit'
require 'bitclust'
require 'bitclust/methoddatabase'

class TestMethodDatabase < Test::Unit::TestCase
  def setup
    @prefix = 'db'
    @root = 'src'
    setup_files
    @db = BitClust::MethodDatabase.new(@prefix)
    # init database
    @db.init
    @db.transaction {
      [
       %w[version 1.9.1],
       %w[encoding utf-8]
      ].each do |k,v|
        @db.propset(k, v)
      end
    }
    # update database
    @db.transaction {
      @db.update_by_stdlibtree(@root)
    }
  end

  def teardown
    FileUtils.rm_r([@prefix, @root], :force => true)
  end

  def test_search_methods__method
    result = @db.search_methods(BitClust::MethodNamePattern.new(nil, nil, 'at_exit'))
    assert_not_nil result.records.first.entry
    assert_equal 1, result.records.size
    assert_equal 'at_exit', result.records.first.entry.name
  end

  def test_search_methods__methods
    result = @db.search_methods(BitClust::MethodNamePattern.new(nil, nil, 'foo'))
    assert_not_nil result.records.first.entry
    assert_equal 2, result.records.size
    assert_equal %w[Foo Bar], result.records.map(&:entry).map(&:klass).map(&:name)
    assert_equal 'foo', result.records.first.entry.name
  end

  def test_search_methods__constant
    result = @db.search_methods(BitClust::MethodNamePattern.new(nil, nil, 'AAA'))
    assert_not_nil result.records.first.entry
    assert_equal 1, result.records.size
    assert_equal 'AAA', result.records.first.entry.name
  end

  def test_dynamic_include
    assert_equal(["BazA"],
                 @db.get_class("A").dynamically_included.map{|m| m.name})
    assert_equal(["BazB"],
                 @db.get_class("B").dynamically_included.map{|m| m.name})
  end

  private
  def setup_files
    FileUtils.mkdir_p("#{@root}/_builtin")

    File.open("#{@root}/LIBRARIES", 'w+') do |file|
      file.puts '_builtin'
      file.puts 'dyn_include_open_a'
      file.puts 'dyn_include_reopen_a'
      file.puts 'dyn_include_reopen_b'
      file.puts 'dyn_include_open_b'
    end

    File.open("#{@root}/_builtin.rd", 'w+') do |file|
      file.puts <<'HERE'
description

= class Foo < Object
desctiption
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

    File.open("#{@root}/dyn_include_open_a.rd", 'w+') do |file|
      file.puts "= class A"
    end

    File.open("#{@root}/dyn_include_reopen_a.rd", 'w+') do |file|
      file.puts "= module BazA"
      file.puts "= reopen A"
      file.puts "include BazA"
    end

    File.open("#{@root}/dyn_include_open_b.rd", 'w+') do |file|
      file.puts "= class B"
    end

    File.open("#{@root}/dyn_include_reopen_b.rd", 'w+') do |file|
      file.puts "= module BazB"
      file.puts "= reopen B"
      file.puts "include BazB"
    end
  end
end
