
module BitClust
  # Null-object version of ProgressBar.
  class SilentProgressBar

    attr_reader :title

    def initialize(title, total, out = $stderr)
      @title, @total, @out = title, total, out
    end

    def inc(step = 1)
    end

    def finish
    end
  end
end
