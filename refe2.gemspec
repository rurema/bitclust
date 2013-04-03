# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require 'rake'
require "bitclust/version"

Gem::Specification.new do |s|
  s.name        = "refe2"
  s.version     = BitClust::VERSION
  s.authors     = ["http://bugs.ruby-lang.org/projects/rurema"]
  s.email       = [""]
  s.homepage    = "http://doc.ruby-lang.org/ja/"
  s.summary     = %Q!BitClust is a rurema document processor.!
  s.description =<<EOD
Rurema is a Japanese ruby documentation project, and
bitclust is a rurema document processor.
This is tools for Rubyists.
EOD

  s.rubyforge_project = ""
  s.files         = FileList["bin/refe", "lib/bitclust.rb"]
  s.executables   = ["refe"]
  s.require_paths = ["lib"]

  # specify any dependencies here; for example:
  # s.add_development_dependency "rspec"
  # s.add_runtime_dependency "rest-client"
  s.add_runtime_dependency "bitclust-core", "= #{BitClust::VERSION}"
  s.add_development_dependency "test-unit", ">= 2.3.0"
  s.add_development_dependency "test-unit-notify"
  s.add_development_dependency "test-unit-rr"
end
