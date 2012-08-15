#!/usr/bin/ruby -Ku
require 'pathname'
lib_dir = Pathname(File.dirname(__FILE__)) + "lib"
$LOAD_PATH.unshift(lib_dir.expand_path.to_s)
require "bitclust"
require "bitclust/runner"
argv = [
        "server",
        "--bind-address=127.0.0.1",
        "--baseurl=",
        "--debug",
        "--auto",
        "--capi"
       ]
BitClust::Runner.new.run(argv)
