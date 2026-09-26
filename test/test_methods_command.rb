# frozen_string_literal: true
require 'test/unit'
require 'bitclust'
require 'bitclust/subcommands/methods_command'

class TestMethodsCommand < Test::Unit::TestCase
  def setup
    @cmd = BitClust::Subcommands::MethodsCommand.new
  end

  def test_needs_no_database
    assert_false(@cmd.needs_database?)
  end

  def test_content_option_is_not_accepted
    assert_raise(OptionParser::InvalidOption) do
      @cmd.parse(['-c', 'Object'])
    end
  end

  def test_ri_database_option_is_not_accepted
    assert_raise(OptionParser::InvalidOption) do
      @cmd.parse(['--ri-database=/tmp/ri', 'Object'])
    end
  end

  def test_diff_and_ruby_options_are_kept
    assert_nothing_raised do
      @cmd.parse(['--ruby=3.4.8', '--diff=refm/api/src/_builtin/Object', 'Object'])
    end
  end
end
