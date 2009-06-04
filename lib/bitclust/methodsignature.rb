#
# bitclust/methodsignature.rb
#
# Copyright (c) 2006-2008 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the Ruby License.
#

require 'bitclust/nameutils'
require 'bitclust/exception'

module BitClust

  class MethodSignature

    include NameUtils

    METHOD_SIGNATURE_RE = /\A
        --- \s*
          (?: (?:#{CLASS_PATH_RE} #{TYPEMARK_RE})? (#{METHOD_NAME_RE})
          | (#{GVAR_RE})
          )                 \s*         # method name ($1) or gvar name ($2)
        (?: \( (.*?) \)     \s* )?      # parameters (optional); $3=parameter_list
        (?: (\{ .* \})      \s* )?      # block (optional); $4=block
        (?: -> \s* (\S.*)   \s* )?      # type declaration (optional); $5=return_type
    \z/x

    def MethodSignature.parse(line)
      m = METHOD_SIGNATURE_RE.match(line) or
          raise ParseError, %Q(unknown signature format: "#{line.strip}")
      method, gvar, params, block, type = m.captures
      new(method || gvar, params && params.strip, block && block.strip, type && type.strip)
    end

    def initialize(name, params, block, type)
      @name = name
      @params = params
      @block = block
      @type = type
    end

    attr_reader :name
    attr_reader :params
    attr_reader :block
    attr_reader :type

    def to_s
      @name +
          (@params ? "(#{@params})" : "") +
          (@block ? " #{@block}" : "") +
          (@type ? " -> #{@type}" : "")
    end

    def friendly_string
      case @name
      when /\A\$/   # gvar
        @name + (@type ? " -> #{@type}" : "")
      when "+@", "-@", "~", "!", "!@"  # unary operator
        "#{@name.sub(/@/, '')}#{@params}" + (@type ? " -> #{@type}" : "")
      when "[]"     # aref
        "self[#{@params}]" + (@type ? " -> #{@type}" : "")
      when "[]="    # aset
        params = @params.split(',')
        val = params.pop
        "self[#{params.join(',').strip}] = #{val.strip}"
      when "`"  # `command`
        "`#{@params}`" + (@type ? " -> #{@type}" : "")
      when /\A\W/   # binary operator
        "self #{@name} #{@params}" + (@type ? " -> #{@type}" : "")
      else
        to_s()
      end
    end

    def inspect
      "\#<#{self.class} name=#{@name.inspect} params=#{@params.inspect} block=#{@block.inspect} type=#{@type.inspect}>"
    end

  end

end
