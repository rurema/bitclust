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

# md 内のエンティティ H1 直後のヘッダ領域に関係行が残っていないか
# （O3 の不変条件: 関係は front matter のみ）
def body_relations?(md)
  in_header = false
  md.each_line do |line|
    if line =~ /\A#(?!#)\s*(?:class|module|object|reopen|redefine)\b/
      in_header = true
    elsif in_header
      case line
      when /\A(?:include|extend|alias)\s+\S/ then return true
      when /\A\#@/, /\A\s*\z/ then nil
      else in_header = false
      end
    end
  end
  false
end

ok = 0
units = 0
failed = []
leftover = []
body_rels = []
targets.sort_by(&:last).each do |full, label|
  rrd = File.read(full)
  outs =
    if orchestrator
      orchestrator.units(label, rrd).map { |u| [u.path, u.rrd, orchestrator.convert_unit(u)] }
    else
      [[label, rrd, BitClust::RRDToMarkdown.convert(rrd)]]
    end
  outs.each do |path, reduced, md|
    units += 1
    ulabel = outs.size > 1 ? "#{label} -> #{path}" : label
    if (sites = prune_sites[label])
      remaining = md.lines.filter_map { |l| $1 if l =~ /\A\#@include\s*\((.*?)\)/ }
      leftover << ulabel unless (remaining & sites).empty?
    end
    body_rels << ulabel if orchestrator && body_relations?(md)
    back = BitClust::MarkdownToRRD.convert(md)
    if back == reduced
      ok += 1
      puts "OK   #{ulabel}" if verbose
    else
      failed << ulabel
      puts "DIFF #{ulabel}" if verbose || show_diff
      if show_diff
        reduced.lines.zip(back.lines).each_with_index do |(a, b), i|
          next if a == b
          puts "  line #{i + 1}: #{a.inspect} -> #{b.inspect}"
          break
        end
      end
    end
  end
end

puts "#{ok}/#{units} byte-exact roundtrip#{inject ? " (reduced base, #{targets.size} sources)" : ''}"
unless failed.empty?
  puts "failed: #{failed.size}"
  failed.each { |f| puts "  #{f}" } unless verbose || show_diff
end
unless leftover.empty?
  puts "grouping includes left unpruned: #{leftover.size}"
  leftover.each { |f| puts "  #{f}" }
end
unless body_rels.empty?
  puts "header relations left in body: #{body_rels.size}"
  body_rels.each { |f| puts "  #{f}" }
end
