require 'bitclust/compat'

module BitClust

  module NameUtils

    NAME_TO_MARK = {
      :singleton_method => '.',
      :instance_method  => '#',
      :module_function  => '.#',
      :constant         => '::',
      :special_variable => '$'
    }

    MARK_TO_NAME = NAME_TO_MARK.invert

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

    def build_method_id(libid, cid, t, name)
      # FIXME: class-ID is filesystem-safe??
      "#{cid}/#{typename2char(t)}.#{fsencode(name)}.#{fsencode(libid)}"
    end

    def fsencode(str)
      str.gsub(/[^A-Za-z0-9_]/n) {|ch| sprintf('%%%02x', ch[0].ord) }
    end

    def fsdecode(str)
      str.gsub(/%[\da-h]{2}/i) {|s| s[1,2].hex.chr }
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
