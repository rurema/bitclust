#!/usr/bin/env ruby
require 'pathname'

gem 'test-unit'
require 'test/unit'
require 'test/unit/notify'
require 'test/unit/rr'

base_dir = Pathname.new(__FILE__).dirname.expand_path
top_dir = (base_dir + '..').expand_path
lib_dir = top_dir + 'lib'

$LOAD_PATH.unshift(lib_dir.to_s)

exit Test::Unit::AutoRunner.run(true, base_dir)
