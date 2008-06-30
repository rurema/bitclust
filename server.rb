#!/usr/bin/ruby -Ke
Dir.chdir File.dirname(__FILE__)
standalone = "bitclust/standalone.rb"
src = File.read(standalone).sub(/\$0/) { standalone.dump }
ARGV.unshift "--bind-address=127.0.0.1"
ARGV.unshift "--baseurl="
ARGV.unshift "--debug"
ARGV.unshift "--auto"
eval src, binding, standalone, 1
