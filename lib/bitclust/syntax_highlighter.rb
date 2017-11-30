require "ripper"
require "bitclust/htmlutils"

module BitClust
  class SyntaxHighlighter < Ripper::Filter
    include BitClust::HTMLUtils

    COLORS = {
      CHAR: "sc",                      # ?a
      __end__: "k",                    # __END__
      backref: "vg",                   # $` $& $' $1 ...
      backtick: "sb",                  # `
      comma: nil,                      # ,
      comment: "c1",                   # #...
      const: "nc",                     # Const
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
      heredoc_end: "no",                # EOS
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
      qwords_beg: "sx",                # %w(
      rbrace: "p",                     # }
      rbracket: "p",                   # ]
      regexp_beg: "sr",                # / (regexp/)
      regexp_end: nil,                 # (/regexp) /
      rparen: "p",                     # )
      semicolon: nil,                  # ;
      sp: nil,                         # space
      symbeg: "ss",                    # :
      tlambda: "o",                    # ->
      tlambeg: "p",                    # (->) {
      tstring_beg: "s2",               # " (string")
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

    def initialize(*args)
      super
      @buffer = ""
      @stack = []
    end

    def on_default(event, token, *rest)
      event_name = event.to_s.sub(/\Aon_/, "")   # :on_event --> "event"
      p [__LINE__, event_name, token, rest] if ENV["RUBY_DEBUG"] == "1"
      style = COLORS[event_name.to_sym]
      @buffer << (style ? "<span class=\"#{style}\">#{token}</span>" : token)
    end

    def on_embdoc_beg(token, *rest)
      p [__LINE__, token, rest] if ENV["RUBY_DEBUG"] == "1"
      style = COLORS[:embdoc_beg]
      @buffer << "<span class=\"#{style}\">#{token}"
    end

    def on_embdoc_end(token, *rest)
      p [__LINE__, token, rest] if ENV["RUBY_DEBUG"] == "1"
      @buffer << "#{token}</span>"
    end

    def on_ident(token, *rest)
      p [__LINE__, :ident, token, rest] if ENV["RUBY_DEBUG"] == "1"
      case
      when @stack.last == :symbol
        @buffer << "#{token}</span>"
        @stack.pop
      when @stack.last == :def
        @stack.pop
        @buffer << "<span class=\"nf\">#{token}</span>"
      when @stack.last == :embexpr
        @buffer << "<span class=\"n\">#{token}</span>"
      when @stack.last == :heredoc
        style = COLORS[:heredoc_beg]
        @buffer << "<span class=\"#{style}\">#{token}"
      when BUILTINS_G.include?(token)
        @buffer << "<span class=\"nb\">#{token}</span>"
      else
        @buffer << token
      end
    end

    def on_kw(token, *rest)
      p [__LINE__, token, rest] if ENV["RUBY_DEBUG"] == "1"
      case
      when @stack.last == :symbol
        @buffer << "#{token}</span>"
        @stack.pop
      when token == "class"
        # @stack.push(:class)
        on_default(:on_kw, token, *rest)
      when token == "def"
        @stack.push(:def)
        on_default(:on_kw, token, *rest)
      else
        on_default(:on_kw, token, *rest)
      end
    end

    def on_regexp_beg(token, *rest)
      style = COLORS[:regexp_beg]
      @buffer << "<span class=\"#{style}\">#{token}"
    end

    def on_regexp_end(token, *rest)
      @buffer << "#{token}</span>"
    end

    def on_symbeg(token, *rest)
      style = COLORS[:symbeg]
      @buffer << "<span class=\"#{style}\">#{token}"
      @stack << :symbol
    end

    def on_tstring_beg(token, *rest)
      style = COLORS[:tstring_beg]
      @buffer << "<span class=\"#{style}\">#{token}"
    end

    def on_tstring_content(token, *rest)
      p [__LINE__, token, rest] if ENV["RUBY_DEBUG"] == "1"
      if @stack.last == :heredoc
        @buffer << "<span class=\"sh\">#{escape_html(token)}</span>"
      else
        on_default(:on_tstring_content, token, *rest)
      end
    end

    def on_tstring_end(token, *rest)
      @buffer << "#{token}</span>"
    end

    def on_heredoc_beg(token, *rest)
      p [__LINE__, token, rest] if ENV["RUBY_DEBUG"] == "1"
      @stack.push(:heredoc)
      on_default(:on_heredoc_beg, token, *rest)
    end

    def on_heredoc_end(token, *rest)
      @stack.pop
      on_default(:on_heredoc_end, token, *rest)
    end

    def on_embexpr_beg(token, *rest)
      @stack.push(:embexpr)
      on_default(:on_embexpr_beg, token, *rest)
    end

    def on_embexpr_end(token, *rest)
      @stack.pop
      on_default(:on_embexpr_end, token, *rest)
    end

    def highlight
      parse
      @buffer
    end
  end
end
