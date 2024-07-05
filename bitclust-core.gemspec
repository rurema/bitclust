$:.push File.expand_path("../lib", __FILE__)
require "bitclust/version"

Gem::Specification.new do |s|
  s.name        = "bitclust-core"
  s.version     = BitClust::VERSION
  s.authors     = ["https://github.com/rurema"]
  s.email       = [""]
  s.homepage    = "https://docs.ruby-lang.org/ja/"
  s.summary     = %Q!BitClust is a rurema document processor.!
  s.description =<<EOD
Rurema is a Japanese ruby documentation project, and
bitclust is a rurema document processor.
EOD

  s.metadata = {
    "bug_tracker_uri"   => "https://github.com/rurema/bitclust/issues",
    "documentation_uri" => "https://github.com/rurema/doctree/wiki",
    "homepage_uri"      => s.homepage,
    "source_code_uri"   => "https://github.com/rurema/bitclust",
    "github_repo"       => "https://github.com/rurema/bitclust",
    "wiki_uri"          => "https://github.com/rurema/doctree/wiki",
  }

  s.files         = Dir["ChangeLog", "Gemfile", "README", "Rakefile", "bitclust.gemspec",
                        "data/**/*", "lib/**/*.rb", "theme/**/*"].reject {|f| f =~ /.*~/ }
  s.test_files    = Dir["test/**/*.rb"].reject {|f| f =~ /.*~/ }
  s.executables   = ["bitclust"]
  s.require_paths = ["lib"]

  s.add_development_dependency "test-unit", ">= 2.3.0"
  s.add_development_dependency "test-unit-notify"
  s.add_development_dependency "test-unit-rr"
  s.add_runtime_dependency "rack"
  s.add_runtime_dependency "progressbar", ">= 1.9.0", "< 2.0"
  s.add_runtime_dependency "webrick"
  s.add_runtime_dependency "drb"
  s.add_runtime_dependency "nkf"
end
