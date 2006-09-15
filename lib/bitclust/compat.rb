unless Fixnum.method_defined?(:ord)
  class Fixnum
    def ord
      self
    end
  end
end
