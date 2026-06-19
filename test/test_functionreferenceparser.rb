require 'test/unit'
require 'bitclust'
require 'bitclust/functionreferenceparser'

class TestFunctionReferenceParser < Test::Unit::TestCase
  def setup
    prefix = 'db'
    src = "test.rd"

    @pwd = Dir.pwd
    Dir.chdir(@tmpdir = Dir.mktmpdir)
    File.open(src, 'w') do |file|
      file.puts <<'HERE'
--- VALUE func()
#@since 2.0.0
some text 1
#@else
some text 2
#@end
HERE
    end
    @path = File.join(@tmpdir, src)
    @db = BitClust::FunctionDatabase.new(prefix)
    @parser = BitClust::FunctionReferenceParser.new(@db)
  end

  def teardown
    Dir.chdir @pwd
    FileUtils.rm_r(@tmpdir, :force => true)
  end

  data("1.9.3" => {
         :version   => "1.9.3",
         :expected  => ["some text 2\n"],
       },
       "2.5.0" => {
         :version   => "2.5.0",
         :expected  => ["some text 1\n"],
       },
       "2.6.0" => {
         :version   => "2.6.0",
         :expected  => ["some text 1\n"],
       })
  def test_parse_file(data)
    @db.transaction {
      result =
        @parser.parse_file(@path, "test.c", {"version" => data[:version]})
      assert_equal data[:expected], result.collect(&:source)
    }
  end

  # source_location points at the file only; the line number is no longer
  # recorded (it would only churn the generated diffs).
  def test_source_location_has_no_line_number
    @db.transaction {
      result = @parser.parse_file(@path, "test.c", {"version" => "2.6.0"})
      location = result.first.source_location
      assert_equal @path, location.file
      assert_nil location.line
    }
  end
end
