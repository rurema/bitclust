
task :release do
  puts "do not use this task. use gem push."
  exit
end

$:.push File.expand_path("../lib", __FILE__)
require "bundler/gem_helper"
require 'bitclust/version'

task :default => [:test]

desc "run test"
task :test do
  sh 'ruby test/run_test.rb'
end

Bundler::GemHelper.install_tasks(:name => "bitclust")
Bundler::GemHelper.install_tasks(:name => "bitclust-dev")
Bundler::GemHelper.install_tasks(:name => "refe2")
