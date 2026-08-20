$:.push File.expand_path("../lib", __FILE__)
require "bitclust/version"

Gem::Specification.new do |s|
  s.name        = "bitclust-irb"
  s.version     = BitClust::VERSION
  s.authors     = ["https://github.com/rurema"]
  s.email       = [""]
  s.homepage    = "https://docs.ruby-lang.org/ja/"
  s.summary     = %Q!irb command to look up Rurema (Japanese Ruby reference manual).!
  s.description =<<EOD
Rurema is a Japanese ruby documentation project, and
bitclust is a rurema document processor.
This gem adds a `refe` command to irb (>= 1.13) that looks up
the Rurema reference database from your irb session:
put `require "bitclust/irb"` in your ~/.irbrc.
EOD

  s.metadata = {
    "bug_tracker_uri"   => "https://github.com/rurema/bitclust/issues",
    "documentation_uri" => "https://github.com/rurema/bitclust/blob/master/doc/usage.md",
    "homepage_uri"      => s.homepage,
    "source_code_uri"   => "https://github.com/rurema/bitclust",
    "github_repo"       => "https://github.com/rurema/bitclust",
  }

  # 実体(lib/bitclust/irb.rb)は bitclust-core 側に含まれる。この gem は
  # irb への依存宣言と `require "bitclust-irb"` 用のスタブだけを持つ
  s.files         = ["lib/bitclust-irb.rb"]
  s.require_paths = ["lib"]

  s.add_runtime_dependency "bitclust-core", "= #{BitClust::VERSION}"
  s.add_runtime_dependency "irb", ">= 1.13"
end
