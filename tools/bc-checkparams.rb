#! /usr/bin/ruby

require 'optparse'
require 'pathname'

bindir = Pathname.new(__FILE__).realpath.dirname
$LOAD_PATH.unshift((bindir + '../lib').realpath)

require 'bitclust/preprocessor'
require 'bitclust/lineinput'
require 'bitclust/parseutils'
require 'bitclust/methodsignature'

def main
  option = OptionParser.new
  version = '1.9.1'
  option.banner = "Usage: #{File.basename($0, '.*')} <filename>"
  option.on('--ruby=[VER]', "The version of Ruby interpreter"){|ver|
    version = ver
  }
  option.on('--help', 'Prints this message and quit.') {
    puts option.help
    exit 0
  }
  begin
    option.parse!(ARGV)
  rescue OptionParser::ParseError => ex
    $stderr.puts err.message
    exit 1
  end
  unless ARGV.size == 1
    $stderr.puts "wrong number of arguments"
    $stderr.puts opts.help
    exit 1
  end
  filename = ARGV[0]
  path = Pathname.new(filename)

  params = { "version" => version }
  parser = BitClust::RDParser.new(BitClust::Preprocessor.read(path, params))
  parser.parse
end

module BitClust
  class RDParser
    def initialize(src)
      @f = LineInput.new(StringIO.new(src))
      @option = { :force => true }
    end

    def parse
      while @f.next?
        case @f.peek
        when /\A---/
          method_entry_chunk
        else
          @f.gets
        end
      end
    end

    def method_entry_chunk
      @f.while_match(/\A---/) do |line|
        method_signature line
      end
      props = {}
      @f.while_match(/\A:/) do |line|
        k, v = line.sub(/\A:/, '').split(':', 2)
        props[k.strip] = v.strip
      end
      while @f.next?
        case @f.peek
        when /\A===+/
          @f.gets
        when /\A==?/
          if @option[:force]
            break
          else
            raise "method entry includes headline: #{@f.peek.inspect}"
          end
        when /\A---/
          break
        when /\A\s+\*\s/
          ulist
        when /\A\s+\(\d+\)\s/
          olist
        when /\A:\s/
          dlist
        when %r<\A//emlist\{>
          emlist
        when /\A\s+\S/
          list
        when /@see/
          see
        when /\A@[a-z]/
          method_info
        else
          if @f.peek.strip.empty?
            @f.gets
          else
            method_entry_paragraph
          end
        end
      end
    end

    def headline(line)
      # nop
    end

    def ulist
      @f.while_match(/\A\s+\*\s/) do |line|
        @f.while_match(/\A\s+[^\*\s]/) do |cont|
          # nop
        end
      end
    end

    def olist
      @f.while_match(/\A\s+\(\d+\)/) do |line|
        @f.while_match(/\A\s+(?!\(\d+\))\S/) do |cont|
          # nop
        end
      end
    end

    def dlist
      while @f.next? and /\A:/ =~ @f.peek
        @f.while_match(/\A:/) do |line|
          # nop
        end
        dd_with_p
      end
    end

    # empty lines separate paragraphs.
    def dd_with_p
      while /\A(?:\s|\z)/ =~ @f.peek or %r!\A//emlist\{! =~ @f.peek
        case @f.peek
        when /\A$/
          @f.gets
        when  /\A[ \t\z]/
          @f.while_match(/\A[ \t\z]/) do |line|
            # nop
          end
        when %r!\A//emlist\{!
            emlist
        else
          raise 'must not happen'
        end
      end
    end

    # empty lines do not separate paragraphs.
    def dd_without_p
      while /\A[ \t]/ =~ @f.peek or %r!\A//emlist\{! =~ @f.peek
        case @f.peek
        when  /\A[ \t\z]/
          @f.while_match(/\A[ \t\z]/) do |line|
            # nop
          end
        when %r!\A//emlist\{!
          emlist
        end
      end
    end

    def emlist
      @f.gets   # discard "//emlist{"
      @f.until_terminator(%r<\A//\}>) do |line|
        # nop
      end
    end

    def list
      @f.break(/\A\S/)
    end

    def see
      @f.gets
      @f.span(/\A\s+\S/)
    end

    def paragraph
      read_paragraph(@f).each do |line|
        # nop
      end
    end

    def read_paragraph(f)
      f.span(%r<\A(?!---|=|//emlist\{)\S>)
    end

    def method_info
      params = []
      while @f.next? and /\A\@(?!see)\w+|\A$/ =~ @f.peek
        header = @f.gets
        next if /\A$/ =~ header
        cmd = header.slice!(/\A\@\w+/)
        @f.ungets(header)
        case cmd
        when '@param', '@arg'
          name = header.slice!(/\A\s*\w+/n) || '?'
          params << name
        when '@raise'
          # nop
        when '@return'
          # nop
        else
          $stderr.puts "[UNKNOWN_META_INFO] #{cmd}"
        end
        dd_without_p
      end
      # check parameters
      params.map(&:strip).each{|param|
        unless @sig.params.split(',').map(&:strip).any?{|v|
            param == v.tr('*', '').gsub(/\s*=\s*.+/, '')
          }
          $stderr.puts "#{@f.lineno}: #{@sig.friendly_string}"
          $stderr.puts params.inspect
          $stderr.puts @sig.params.inspect
        end
      }
    rescue
      $stderr.puts "#{@f.lineno}: #{@sig.friendly_string}"
      $stderr.puts params.inspect
      $stderr.puts @sig.params.inspect
    end

    def method_entry_paragraph
      read_method_entry_paragraph(@f).each do |line|
        # nop
      end
    end

    def read_method_entry_paragraph(f)
      f.span(%r<\A(?!---|=|//emlist\{|@[a-z])\S>)
    end

    def method_signature(sig_line)
      @sig = MethodSignature.parse(sig_line)
    end
  end
end

main
