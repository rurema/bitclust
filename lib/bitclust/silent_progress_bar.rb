# frozen_string_literal: true

module BitClust
  # Null-object version of ProgressBar.
  class SilentProgressBar

    attr_accessor :title

    def self.create(output: $stderr, title:, total:)
      self.new(output: output, title: title, total: total)
    end

    def initialize(output:, title:, total:)
      @title, @total, @output = title, total, output
    end

    def increment
    end

    def finish
    end
  end
end
