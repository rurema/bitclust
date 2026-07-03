#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Markdown 変換のラウンドトリップ検証。
# refm/api/src の全ファイルについて rd → md → rd がバイト一致するかを確認する。
#
# usage: ruby tools/md-roundtrip-check.rb [options] <doctree-root>
#   --with-doc   refm/doc/**/*.rd も検証する（既知の失敗あり: 行頭 `# ` リテラル本文等）
#   --inject     MarkdownOrchestrator の変換（prune・全体ゲート解除・front matter 注入）で
#                検証する: md → rd が reduce 後の rd を復元すること、および
#                md に grouping include が残っていないことを確認する
#   --diff       差分のあったファイルの先頭差分行を表示する
#   -v           全ファイルの結果を表示する

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'bitclust/rrd_to_markdown'
require 'bitclust/markdown_to_rrd'
require 'bitclust/markdown_orchestrator'

with_doc = ARGV.delete('--with-doc')
inject = ARGV.delete('--inject')
show_diff = ARGV.delete('--diff')
verbose = ARGV.delete('-v')
doctree = ARGV.shift or abort "usage: #{$0} [--with-doc] [--inject] [--diff] [-v] <doctree-root>"

src_root = File.join(doctree, 'refm/api/src')
files = Dir.glob('**/*', base: src_root).select { |f| File.file?(File.join(src_root, f)) }
files -= ['LIBRARIES']

orchestrator = nil
prune_sites = {}
if inject
  orchestrator = BitClust::MarkdownOrchestrator.new(src_root)
  orchestrator.warnings.each { |w| warn "W: #{w}" }
  prune_sites = orchestrator.graph.grouping_include_sites
  puts "prune: #{prune_sites.size} files"
end

targets = files.map { |f| [File.join(src_root, f), f] }
if with_doc
  doc_root = File.join(doctree, 'refm/doc')
  targets += Dir.glob('**/*.rd', base: doc_root).map { |f| [File.join(doc_root, f), "doc:#{f}"] }
end

ok = 0
failed = []
leftover = []
targets.sort_by(&:last).each do |full, label|
  rrd = File.read(full)
  if orchestrator
    rrd, front_matter = orchestrator.reduce(label, rrd)
    md = BitClust::RRDToMarkdown.convert(rrd, extra_front_matter: front_matter)
  else
    md = BitClust::RRDToMarkdown.convert(rrd)
  end
  back = BitClust::MarkdownToRRD.convert(md)
  if (sites = prune_sites[label])
    remaining = md.lines.filter_map { |l| $1 if l =~ /\A\#@include\s*\((.*?)\)/ }
    leftover << label unless (remaining & sites).empty?
  end
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

puts "#{ok}/#{targets.size} byte-exact roundtrip#{inject ? ' (reduced base)' : ''}"
unless failed.empty?
  puts "failed: #{failed.size}"
  failed.each { |f| puts "  #{f}" } unless verbose || show_diff
end
unless leftover.empty?
  puts "grouping includes left unpruned: #{leftover.size}"
  leftover.each { |f| puts "  #{f}" }
end
