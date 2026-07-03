#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Markdown 変換のラウンドトリップ検証。
# refm/api/src の全ファイルについて rd → md → rd がバイト一致するかを確認する。
#
# usage: ruby tools/md-roundtrip-check.rb [options] <doctree-root>
#   --with-doc   refm/doc/**/*.rd も検証する（既知の失敗あり: 行頭 `# ` リテラル本文等）
#   --inject     IncludeGraph で library / 構造 since/until を front matter 注入した上で
#                md → rd が元バイト列を復元することを検証する（オーケストレータ相当）
#   --diff       差分のあったファイルの先頭差分行を表示する
#   -v           全ファイルの結果を表示する

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'bitclust/rrd_to_markdown'
require 'bitclust/markdown_to_rrd'
require 'bitclust/include_graph'

with_doc = ARGV.delete('--with-doc')
inject = ARGV.delete('--inject')
show_diff = ARGV.delete('--diff')
verbose = ARGV.delete('-v')
doctree = ARGV.shift or abort "usage: #{$0} [--with-doc] [--inject] [--diff] [-v] <doctree-root>"

src_root = File.join(doctree, 'refm/api/src')
files = Dir.glob('**/*', base: src_root).select { |f| File.file?(File.join(src_root, f)) }
files -= ['LIBRARIES']

extra = {}
if inject
  graph = BitClust::IncludeGraph.analyze(src_root)
  extra = graph.front_matter_map(BitClust::IncludeGraph::Scope.new('3.0', '4.2'))
  graph.warnings.each { |w| warn "W: #{w}" }
  puts "inject: #{extra.size} files (#{extra.count { |_, fm| fm.size > 1 }} with structural gates)"
end

targets = files.map { |f| [File.join(src_root, f), f] }
if with_doc
  doc_root = File.join(doctree, 'refm/doc')
  targets += Dir.glob('**/*.rd', base: doc_root).map { |f| [File.join(doc_root, f), "doc:#{f}"] }
end

ok = 0
failed = []
targets.sort_by(&:last).each do |full, label|
  rrd = File.read(full)
  md = BitClust::RRDToMarkdown.convert(rrd, extra_front_matter: extra[label] || {})
  back = BitClust::MarkdownToRRD.convert(md)
  if back == rrd
    ok += 1
    puts "OK   #{label}" if verbose
  else
    failed << label
    puts "DIFF #{label}" if verbose || show_diff
    if show_diff
      rrd.lines.zip(back.lines).each_with_index do |(a, b), i|
        next if a == b
        puts "  line #{i + 1}: #{a.inspect} -> #{b.inspect}"
        break
      end
    end
  end
end

puts "#{ok}/#{targets.size} byte-exact roundtrip"
unless failed.empty?
  puts "failed: #{failed.size}"
  failed.each { |f| puts "  #{f}" } unless verbose || show_diff
end
