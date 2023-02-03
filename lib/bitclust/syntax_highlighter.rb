# frozen_string_literal: true
require "ripper"
require "bitclust/htmlutils"

module BitClust
  class SyntaxHighlighter < Ripper::Filter
    include BitClust::HTMLUtils

    class Error < StandardError
      def initialize(name, lineno, column, error_message)
        @name = name
        @lineno = lineno
        @column = column
        @error_message = error_message
      end

      def message
        "#{@name}:#{@lineno}:#{@column} #{@error_message} (#{self.class})"
      end
    end

    class ParseError < Error
    end

    class CompileError < Error
    end

    COLORS = {
      CHAR: "sc",                      # ?a
      __end__: "k",                    # __END__
      backref: "vg",                   # $` $& $' $1 ...
      backtick: "sb",                  # `
      comma: nil,                      # ,
      comment: "c1",                   # #...
      const: "no",                     # Const
      cvar: "vc",                      # @@var
      embdoc: nil,                     # (=begin) document (=end)
      embdoc_beg: "cm",                # =begin
      embdoc_end: nil,                 # =end
      embexpr_beg: "si",               # #{
      embexpr_end: "si",               # (#{) }
      embvar: "n",                     # ("...) # (var")
      float: "mf",                     # 1.23 (float)
      gvar: "vg",                      # $var
      heredoc_beg: "no",               # <<EOS
      heredoc_end: "no",               # EOS
      ident: nil,                      # identifier
      ignored_nl: nil,                 # ignored \n
      int: "mi",                       # 1 (integer)
      ivar: "vi",                      # @var
      kw: "k",                         # keyword
      label: "ss",                     # label:
      lbrace: "p",                     # {
      lbracket: "p",                   # [
      lparen: "p",                     # (
      nl: nil,                         # \n
      op: "o",                         # operator
      period: "p",                     # .
      qsymbols_beg: "ss",              # %i(
      qwords_beg: "sx",                # %w(
      rbrace: "p",                     # }
      rbracket: "p",                   # ]
      regexp_beg: "sr",                # / (regexp/)
      regexp_end: nil,                 # (/regexp) /
      rparen: "p",                     # )
      semicolon: nil,                  # ;
      sp: nil,                         # space
      symbeg: "ss",                    # :
      symbols_beg: "ss",               # %I(
      tlambda: "o",                    # ->
      tlambeg: "p",                    # (->) {
      tstring_beg: nil,                # " (string")
      tstring_content: nil,            # (") string (")
      tstring_end: nil,                # ("string) "
      words_beg: "sx",                 # %W(
      words_sep: nil                   # (%W() )
    }
    LABELS = {
    }

    KEYWORDS = %w[
      BEGIN END alias begin break case defined\? do else elsif end
      ensure for if in next redo rescue raise retry return super then
      undef unless until when while yield
    ]

    KEYWORDS_PSEUDO = %w[
      loop include extend raise
      alias_method attr catch throw private module_function
      public protected true false nil __FILE__ __LINE__
    ]

    BUILTINS_G = %w[
      attr_reader attr_writer attr_accessor

      __id__ __send__ abort ancestors at_exit autoload binding callcc
      caller catch chomp chop class_eval class_variables clone
      const_defined\? const_get const_missing const_set constants
      display dup eval exec exit extend fail fork format freeze
      getc gets global_variables gsub hash id included_modules
      inspect instance_eval instance_method instance_methods
      instance_variable_get instance_variable_set instance_variables
      lambda load local_variables loop method method_missing
      methods module_eval name object_id open p print printf
      private_class_method private_instance_methods private_methods proc
      protected_instance_methods protected_methods public_class_method
      public_instance_methods public_methods putc puts raise rand
      readline readlines require require_relative scan select self send set_trace_func
      singleton_methods sleep split sprintf srand sub syscall system
      taint test throw to_a to_s trace_var trap untaint untrace_var warn
    ]

    BUILTINS_Q = %w[
      autoload block_given const_defined eql equal frozen
      include instance_of is_a iterator kind_of method_defined
      nil private_method_defined protected_method_defined
      public_method_defined respond_to tainted
    ]

    BUILTINS_B = %w[chomp chop exit gsub sub]

    def initialize(src, filename = "-", lineno = 1)
      super
      @src = src
      @stack = []
      @name_buffer = []
      @__lexer.define_singleton_method(:on_parse_error) do |message|
        raise ParseError.new(filename, self.lineno, self.column, "#{message}\n#{src}")
      end
      @__lexer.define_singleton_method(:compile_error) do |message|
        raise CompileError.new(filename, self.lineno, self.column, "#{message}\n#{src}")
      end
    end

    def on_default(event, token, data)
      event_name = event.to_s.sub(/\Aon_/, "")   # :on_event --> "event"
      style = COLORS[event_name.to_sym]
      escaped_token = escape_html(token)
      data << (style ? "<span class=\"#{style}\">#{escaped_token}</span>" : escaped_token)
      data
    end

    def on_embdoc_beg(token, data)
      style = COLORS[:embdoc_beg]
      data << "<span class=\"#{style}\">#{token}"
      data
    end

    def on_embdoc_end(token, data)
      data << "#{token}</span>"
      data
    end

    def on_ident(token, data)
      case
      when @stack.last == :symbol
        data << "#{token}</span>"
        @stack.pop
      when @stack.last == :def
        @stack.pop
        data << "<span class=\"nf\">#{token}</span>"
      when @stack.last == :embexpr
        data << "<span class=\"n\">#{token}</span>"
      when @stack.last == :heredoc
        style = COLORS[:heredoc_beg]
        data << "<span class=\"#{style}\">#{token}"
      when @stack.last == :method_call
        data << "<span class=\"nf\">#{token}</span>"
        @stack.pop
      when @stack.last == :class
        @name_buffer << token
      when BUILTINS_G.include?(token)
        data << "<span class=\"nb\">#{token}</span>"
      else
        data << token
      end
      data
    end

    def on_const(token, data)
      case
      when @stack.last == :class
        @name_buffer << token
      when @stack.last == :module
        @name_buffer << token
      when @stack.last == :symbol
        data << "#{token}</span>"
        @stack.pop
      else
        on_default(:on_const, token, data)
      end
      data
    end

    def on_kw(token, data)
      case
      when @stack.last == :symbol
        data << "#{token}</span>"
        @stack.pop
      when token == "module"
        @stack.push(:module)
        on_default(:on_kw, token, data)
      when token == "class"
        @stack.push(:class)
        on_default(:on_kw, token, data)
      when token == "def"
        @stack.push(:def)
        on_default(:on_kw, token, data)
      when token == "self"
        data << "<span class=\"nc\">#{token}</span>"
      else
        on_default(:on_kw, token, data)
      end
      data
    end

    def on_period(token, data)
      @stack.push(:method_call)
      on_default(:on_period, token, data)
    end

    def on_op(token, data)
      case
      when token == "::" && [:class, :module].include?(@stack.last)
        @name_buffer << token
      when token == "<<" && @stack.last == :class
        @stack.pop
        on_default(:on_op, token, data)
      else
        @stack.pop if @stack.last == :method_call
        on_default(:on_op, token, data)
      end
      data
    end

    def on_sp(token, data)
      case
      when @name_buffer.empty?
        return on_default(:on_sp, token, data)
      when @stack.last == :module
        name = @name_buffer.join
        data << "<span class=\"nn\">#{name}</span>"
        @stack.pop
        @name_buffer.clear
      when @stack.last == :class
        namespace = @name_buffer.values_at(0..-3).join
        operator = @name_buffer[-2]
        name = @name_buffer.last
        data << "<span class=\"nn\">#{namespace}</span>"
        data << "<span class=\"o\">#{operator}</span>"
        data << "<span class=\"nc\">#{name}</span>"
        @stack.pop
        @name_buffer.clear
      end
      on_default(:on_sp, token, data)
    end

    def on_nl(token, data)
      case
      when @name_buffer.empty?
        return on_default(:on_nl, token, data)
      when @stack.last == :module
        name = @name_buffer.join
        data << "<span class=\"nn\">#{name}</span>"
        @stack.pop
        @name_buffer.clear
      when @stack.last == :class
        namespace = @name_buffer.values_at(0..-3).join
        operator = @name_buffer[-2]
        name = @name_buffer.last
        data << "<span class=\"nn\">#{namespace}</span>"
        data << "<span class=\"o\">#{operator}</span>"
        data << "<span class=\"nc\">#{name}</span>"
        @stack.pop
        @name_buffer.clear
      end
      on_default(:on_nl, token, data)
    end

    def on_semicolon(token, data)
      case
      when @name_buffer.empty?
        return on_default(:on_semicolon, token, data)
      when @stack.last == :module
        name = @name_buffer.join
        data << "<span class=\"nn\">#{name}</span>"
        @stack.pop
        @name_buffer.clear
      when @stack.last == :class
        namespace = @name_buffer.values_at(0..-3).join
        operator = @name_buffer[-2]
        name = @name_buffer.last
        data << "<span class=\"nn\">#{namespace}</span>"
        data << "<span class=\"o\">#{operator}</span>"
        data << "<span class=\"nc\">#{name}</span>"
        @stack.pop
        @name_buffer.clear
      end
      on_default(:on_semicolon, token, data)
    end

    def on_regexp_beg(token, data)
      style = COLORS[:regexp_beg]
      data << "<span class=\"#{style}\">#{token}"
      data
    end

    def on_regexp_end(token, data)
      data << "#{token}</span>"
      data
    end

    def on_symbeg(token, data)
      style = COLORS[:symbeg]
      data << "<span class=\"#{style}\">#{token}"
      @stack << :symbol
      data
    end

    def on_tstring_beg(token, data)
      if token == "'"
        data << "<span class=\"s1\">#{token}"
        @stack << :string1
      else
        data << "<span class=\"s2\">#{token}</span>"
        @stack << :string2
      end
      data
    end

    def on_tstring_content(token, data)
      case
      when @stack.last == :heredoc
        data << "<span class=\"sh\">#{escape_html(token)}</span>"
      when @stack.last == :string1
        data << escape_html(token)
      when @stack.last == :string2
        data << "<span class=\"s2\">#{escape_html(token)}</span>"
      else
        on_default(:on_tstring_content, token, data)
      end
      data
    end

    def on_tstring_end(token, data)
      case
      when token == "'"
        data << "#{token}</span>"
      when %i[qwords words qsymbols symbols].include?(@stack.last)
        @stack.pop
        data << "#{token}</span>"
      else
        data << "<span class=\"s2\">#{token}</span>"
      end
      @stack.pop
      data
    end

    def on_qwords_beg(token, data)
      @stack.push(:qwords)
      style = COLORS[:qwords_beg]
      data << "<span class=\"#{style}\">#{token}"
      data
    end

    def on_words_beg(token, data)
      @stack.push(:words)
      style = COLORS[:words_beg]
      data << "<span class=\"#{style}\">#{token}"
      data
    end

    def on_qsymbols_beg(token, data)
      @stack.push(:qsymbols)
      style = COLORS[:qsymbols_beg]
      data << "<span class=\"#{style}\">#{token}"
      data
    end

    def on_symbols_beg(token, data)
      @stack.push(:symbols)
      style = COLORS[:symbols_beg]
      data << "<span class=\"#{style}\">#{token}"
      data
    end

    def on_heredoc_beg(token, data)
      @stack.push(:heredoc)
      on_default(:on_heredoc_beg, token, data)
    end

    def on_heredoc_end(token, data)
      @stack.pop
      on_default(:on_heredoc_end, token, data)
    end

    def on_embexpr_beg(token, data)
      @stack.push(:embexpr)
      on_default(:on_embexpr_beg, token, data)
    end

    def on_embexpr_end(token, data)
      @stack.pop
      on_default(:on_embexpr_end, token, data)
    end

    def on___end__(token, data)
      on_default(:on___end__, token, data)
      style = COLORS[:comment]
      data << "<span class=\"#{style}\">#{escape_html(@src.lines[lineno..-1].join)}</span>"
      data
    end

    def highlight
      parse(+"")
    end
  end
end
