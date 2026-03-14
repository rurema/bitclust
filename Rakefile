
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
  out_dir = 'sig-prototype'
  FileUtils.rm_rf out_dir
  sh "rbs prototype rb --out-dir=#{out_dir} lib"
  FileUtils.rm "#{out_dir}/bitclust/compat.rbs"
  sh "rbs subtract --write #{out_dir} sig"
  FileUtils.rmdir ["#{out_dir}/bitclust/generators", "#{out_dir}/bitclust/subcommands", "#{out_dir}/bitclust", "#{out_dir}"]
  sh 'rbs validate'
end

namespace :rbs do
  desc 'rbs collection install'
  task :install do
    sh 'rbs collection install'
  end

  desc 'rbs collection update'
  task :update do
    sh 'rbs collection update'
  end
end

Bundler::GemHelper.install_tasks(:name => "bitclust-core")
Bundler::GemHelper.install_tasks(:name => "bitclust-dev")
Bundler::GemHelper.install_tasks(:name => "refe2")
