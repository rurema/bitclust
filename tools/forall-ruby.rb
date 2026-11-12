#!/usr/bin/env ruby

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'bitclust/crossrubyutils'

include BitClust::CrossRubyUtils

def main
  ENV.delete('GEM_HOME')
  forall_ruby(ENV['PATH']) do |ruby, ver|
    puts ver
    system ruby, *ARGV
  end
end

main
