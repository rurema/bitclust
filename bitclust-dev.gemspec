# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require 'rake'
require "bitclust/version"

Gem::Specification.new do |s|
  s.name        = "bitclust-dev"
  s.version     = BitClust::VERSION
  s.authors     = ["http://bugs.ruby-lang.org/projects/rurema"]
  s.email       = [""]
  s.homepage    = "http://doc.ruby-lang.org/ja/"
  s.summary     = %Q!BitClust is a rurema document processor.!
  s.description =<<EOD
Rurema is a Japanese ruby documentation project, and
bitclust is a rurema document processor.
This is tools for Rurema developpers.
EOD

  s.rubyforge_project = ""

  s.files         = FileList["tools/*", "lib/bitclust.rb"]
  s.executables   = FileList["tools/*"].
    exclude("ToDoHistory", "check-signature.rb").
    map{|v| File.basename(v) }
  s.require_paths = ["lib"]
  s.bindir        = "tools"

  # specify any dependencies here; for example:
  # s.add_development_dependency "rspec"
  # s.add_runtime_dependency "rest-client"
  s.add_runtime_dependency "bitclust-core", "= #{BitClust::VERSION}"
  s.add_development_dependency "test-unit", ">= 2.3.0"
  s.add_development_dependency "test-unit-notify"
  s.add_development_dependency "test-unit-rr"
end
