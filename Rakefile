
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

desc "Re-generate sig/prototype"
task :sig do
  FileUtils.rm_rf 'sig/prototype'
  sh 'rbs prototype rb --out-dir=sig/prototype lib'
  FileUtils.rm 'sig/prototype/bitclust/compat.rbs'
  sh 'rbs subtract --write sig/prototype sig/hand-written'
  sh 'steep validate'
end

Bundler::GemHelper.install_tasks(:name => "bitclust-core")
Bundler::GemHelper.install_tasks(:name => "bitclust-dev")
Bundler::GemHelper.install_tasks(:name => "refe2")
