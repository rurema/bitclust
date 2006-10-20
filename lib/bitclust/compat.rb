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
