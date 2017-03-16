$:.push File.expand_path("../lib", __FILE__)
require "bitclust/version"

Gem::Specification.new do |s|
  s.name        = "bitclust-dev"
  s.version     = BitClust::VERSION
  s.authors     = ["https://github.com/rurema"]
  s.email       = [""]
  s.homepage    = "http://docs.ruby-lang.org/ja/"
  s.summary     = %Q!BitClust is a rurema document processor.!
  s.description =<<EOD
Rurema is a Japanese ruby documentation project, and
bitclust is a rurema document processor.
This is tools for Rurema developpers.
EOD

  s.rubyforge_project = ""

  s.files         = Dir["tools/*", "lib/bitclust.rb"]
  s.executables   = Dir["tools/*"].
    map {|v| File.basename(v) }.
    reject {|f| %w(ToDoHistory check-signature.rb).include?(f) }
  s.require_paths = ["lib"]
  s.bindir        = "tools"

  s.add_runtime_dependency "bitclust-core", "= #{BitClust::VERSION}"
end
