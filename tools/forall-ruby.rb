#!/usr/bin/env ruby

require 'pathname'

bindir = Pathname.new(__FILE__).realpath.dirname
$LOAD_PATH.unshift((bindir + '../lib').realpath)

require 'bitclust/crossrubyutils'

include BitClust::CrossRubyUtils

def main
  forall_ruby(ENV['PATH']) do |ruby, ver|
    puts ver
    system ruby, *ARGV
  end
end

main
