require 'bitclust'
require 'stringio'
require 'test/unit'

class TestBitClust < Test::Unit::TestCase
  RUBYBIN = "ruby"

  def setup
    testdir = File.dirname(File.expand_path(__FILE__))
    bindir = File.dirname(testdir)
    @db = "-d#{testdir}/db-test"
    @dir = "#{bindir}/bin"
  end
  def capi(*argv)
    if argv.first.is_a? Symbol
      argv[0] = argv[0].to_s
      args = argv.join(' ')
    else
      args = argv[0]
    end
    args = "#{@db} --capi #{args}"

    return `#{RUBYBIN} #{@dir}/bitclust.rb #{args}`
  end

  def test_list
    assert_equal(capi("list --function"), "public_func\n")
  end
end
