unless Object.method_defined?(:__send)
  class Object
    alias __send __send__
  end
end

unless Object.method_defined?(:funcall)
  class Object
    alias funcall __send
  end
end

unless Fixnum.method_defined?(:ord)
  class Fixnum
    def ord
      self
    end
  end
end

unless String.method_defined?(:lines)
  class String
    alias lines to_a
  end
end

unless String.method_defined?(:bytesize)
  class String
    alias bytesize size
  end
end

def fopen(*args, &block)
  option = args[1]
  if option and !Object.const_defined?(:Encoding)
    args[1] = option.sub(/:.*\z/, '')
  end
  File.open(*args, &block)
end
