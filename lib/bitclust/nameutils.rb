require 'bitclust/compat'

module BitClust

  module NameUtils

    module_function

    def libname?(str)
      /\A\w+(\/\w+)*\z/ =~ str
    end

    def libname2id(name)
      name.split('/').map {|ent| fsencode(ent) }.join('.')
    end

    def libid2name(id)
      id.split('.').map {|ent| fsdecode(ent) }.join('/')
    end

    def classname?(str)
      /\A[A-Z]\w*(::[A-Z]\w*)*/ =~ str or str == 'fatal'
    end

    # A constant name must be composed by fs-safe characters.
    def classname2id(name)
      name.gsub(/::/, '__')
    end

    # A class name must not include '__'.
    def classid2name(id)
      id.gsub(/__/, '::')
    end

    def method_spec?(str)
      /\A([\w\:]+)(\.\#|[\.\#]|::)([^:\s]+)\z/ =~ str
    end

    def split_method_spec(spec)
      case spec
      when /\AKernel\$/
        return 'Kernel', '$', $'
      else
        m = /\A([\w\:]+)(\.\#|[\.\#]|::)([^:\s]+)\z/.match(spec) or
            raise ArgumentError, "wrong method spec: #{spec.inspect}"
        return *m.captures
      end
    end

    def methodid2spec(id)
      c, t, m, lib = *split_method_id(id)
      "#{classid2name(c)}#{typechar2mark(t)}#{fsdecode(m)}"
    end

    def methodid2libid(id)
      c, t, m, lib = *split_method_id(id)
      fsdecode(lib)
    end

    def methodid2classid(id)
      c, t, m, lib = *split_method_id(id)
      c
    end

    def methodid2typename(id)
      c, t, m, lib = *split_method_id(id)
      typechar2name(t)
    end

    def methodid2mname(id)
      c, t, m, lib = *split_method_id(id)
      fsdecode(m)
    end

    def methodname?(str)
      true   # FIXME
    end

    def build_method_id(libid, cid, t, name)
      "#{cid}/#{typename2char(t)}.#{fsencode(name)}.#{fsencode(libid)}"
    end

    def split_method_id(id)
      return *id.split(%r<[/\.]>)
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

    def typemark?(m)
      MARK_TO_NAME.key?(m)
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

    def typechar2mark(char)
      typename2mark(typechar2name(char))
    end

    def typemark2char(mark)
      typename2char(typemark2name(mark))
    end

    def fsencode(str)
      str.gsub(/[^A-Za-z0-9_]/n) {|ch| sprintf('=%02x', ch[0].ord) }
    end

    def fsdecode(str)
      str.gsub(/=[\da-h]{2}/i) {|s| s[1,2].hex.chr }
    end

=begin
    # ReFe version (supports case-insensitive filesystems)
    def fsencode(str)
      str.gsub(/[^a-z0-9_]/n) {|ch|
        (/[A-Z]/n === ch) ? "-#{ch}" : sprintf('%%%02x', ch[0])
      }.downcase
    end

    def fsdecode(str)
      str.gsub(/%[\da-h]{2}|-[a-z]/i) {|s|
        (s[0] == ?-) ? s[1,1].upcase : s[1,2].hex.chr
      }
    end
=end

  end

end
