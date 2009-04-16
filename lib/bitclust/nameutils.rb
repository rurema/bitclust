#
# bitclust/nameutils.rb
#
# Copyright (c) 2006-2007 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the Ruby License.
#

require 'bitclust/compat'

module BitClust

  module NameUtils

    module_function

    LIBNAME_RE     = %r<[\w\-]+(/[\w\-]+)*>
    CONST_RE       = /[A-Z]\w*/
    CONST_PATH_RE  = /#{CONST_RE}(?:::#{CONST_RE})*/
    CLASS_NAME_RE  = /(?:#{CONST_RE}|fatal)/
    CLASS_PATH_RE  = /(?:#{CONST_PATH_RE}|fatal)/
    METHOD_NAME_RE = /\w+[?!=]?|===|==|=~|<=>|<=|>=|!=|!|!@|\[\]=|\[\]|\*\*|>>|<<|\+@|\-@|[~+\-*\/%&|^<>`]/
    TYPEMARK_RE    = /(?:\.|\#|\.\#|::|\$)/
    METHOD_SPEC_RE = /#{CLASS_PATH_RE}#{TYPEMARK_RE}#{METHOD_NAME_RE}/
    GVAR_RE        = /\$(?:\w+|-.|\S)/

    def libname?(str)
      (/\A#{LIBNAME_RE}\z/o =~ str) ? true : false
    end

    def libname2id(name)
      name.split('/').map {|ent| encodename_url(ent) }.join('.')
    end

    def libid2name(id)
      id.split('.').map {|ent| decodename_url(ent) }.join('/')
    end

    def classname?(str)
      (/\A#{CLASS_PATH_RE}\z/o =~ str) ? true : false
    end

    def classname2id(name)
      name.gsub(/::/, '=')
    end

    def classid2name(id)
      id.gsub(/=/, '::')
    end

    def method_spec?(str)
      (/\A#{METHOD_SPEC_RE}\z/o =~ str) ? true : false
    end

    def split_method_spec(spec)
      case spec
      when /\AKernel\$/
        return 'Kernel', '$', $'
      else
        m = /\A(#{CLASS_PATH_RE})(#{TYPEMARK_RE})(#{METHOD_NAME_RE})\z/o.match(spec) or
            raise ArgumentError, "wrong method spec: #{spec.inspect}"
        return *m.captures
      end
    end

    def methodid2specstring(id)
      c, t, m, lib = *split_method_id(id)
      classid2name(c) + typechar2mark(t) + decodename_url(m)
    end

    def methodid2specparts(id)
      c, t, m, lib = *split_method_id(id)
      return classid2name(c), typechar2mark(t), decodename_url(m), libid2name(lib)
    end

    def methodid2libid(id)
      c, t, m, lib = *split_method_id(id)
      lib
    end

    def methodid2classid(id)
      c, t, m, lib = *split_method_id(id)
      c
    end

    def methodid2typechar(id)
      c, t, m, lib = *split_method_id(id)
      t
    end

    def methodid2typename(id)
      c, t, m, lib = *split_method_id(id)
      typechar2name(t)
    end

    def methodid2typemark(id)
      c, t, m, lib = *split_method_id(id)
      typechar2mark(t)
    end

    def methodid2mname(id)
      c, t, m, lib = *split_method_id(id)
      decodename_url(m)
    end

    def gvarname?(str)
      GVAR_RE =~ str ? true : false
    end

    MID = /\A#{METHOD_NAME_RE}\z/

    def methodname?(str)
      (MID =~ str) ? true : false
    end

    def build_method_id(libid, cid, t, name)
      "#{cid}/#{typename2char(t)}.#{encodename_url(name)}.#{libid}"
    end

    # private module function
    def split_method_id(id)
      return *id.split(%r<[/\.]>, 4)
    end

    NAME_TO_MARK = {
      :singleton_method => '.',
      :instance_method  => '#',
      :module_function  => '.#',
      :constant         => '::',
      :special_variable => '$'
    }

    MARK_TO_NAME = NAME_TO_MARK.invert

    def typename?(n)
      NAME_TO_MARK.key?(n)
    end

    def typename2mark(name)
      NAME_TO_MARK[name] or
          raise "must not happen: #{name.inspect}"
    end

    def typemark2name(mark)
      MARK_TO_NAME[mark] or
          raise "must not happen: #{mark.inspect}"
    end

    NAME_TO_CHAR = {
      :singleton_method => 's',
      :instance_method  => 'i',
      :module_function  => 'm',
      :constant         => 'c',
      :special_variable => 'v'
    }

    CHAR_TO_NAME = NAME_TO_CHAR.invert

    def typechar?(c)
      CHAR_TO_NAME.key?(c)
    end

    def typename2char(name)
      NAME_TO_CHAR[name] or
          raise "must not happen: #{name.inspect}"
    end

    def typechar2name(char)
      CHAR_TO_NAME[char] or
          raise "must not happen: #{char.inspect}"
    end

    MARK_TO_CHAR = {
      '.'  => 's',
      '#'  => 'i',
      '.#' => 'm',
      '::' => 'c',
      '$'  => 'v'
    }

    CHAR_TO_MARK = MARK_TO_CHAR.invert

    def typemark?(m)
      MARK_TO_CHAR.key?(m)
    end

    def typechar2mark(char)
      CHAR_TO_MARK[char] or
          raise "must not happen: #{char.inspect}"
    end

    def typemark2char(mark)
      MARK_TO_CHAR[mark] or
          raise "must not happen: #{mark.inspect}"
    end

    def functionname?(n)
      /\A\w+\z/ =~ n ? true : false
    end

    # string -> case-sensitive ID
    def encodename_url(str)
      str.gsub(/[^A-Za-z0-9_]/n) {|ch| sprintf('=%02x', ch[0].ord) }
    end

    # case-sensitive ID -> string
    def decodename_url(str)
      str.gsub(/=[\da-h]{2}/ni) {|s| s[1,2].hex.chr }
    end

    # case-sensitive ID -> encoded string (encode only [A-Z])
    def encodeid(str)
      str.gsub(/[A-Z]/n) {|ch| "-#{ch}" }.downcase
    end

    # encoded string -> case-sensitive ID (decode only [A-Z])
    def decodeid(str)
      str.gsub(/-[a-z]/ni) {|s| s[1,1].upcase }
    end

    def encodename_fs(str)
      str.gsub(/[^a-z0-9_]/n) {|ch|
        (/[A-Z]/n =~ ch) ? "-#{ch}" : sprintf('=%02x', ch[0].ord)
      }.downcase
    end

    def decodename_fs(str)
      str.gsub(/=[\da-h]{2}|-[a-z]/ni) {|s|
        (/\A-/ =~ s) ? s[1,1].upcase : s[1,2].hex.chr
      }
    end

  end

end
