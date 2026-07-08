#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Markdown 変換のラウンドトリップ検証。
# refm/api/src の全ファイルについて rd → md → rd がバイト一致するかを確認する。
#
# usage: ruby tools/md-roundtrip-check.rb [options] <doctree-root>
#   --with-doc   refm/doc/**/*.rd も検証する（DocConverter の reduce 基準）
#   --with-capi  refm/capi/src/*.rd も検証する（CapiConverter）
#   --inject     MarkdownOrchestrator の変換（prune・全体ゲート解除・front matter 注入）で
#                検証する: md → rd が reduce 後の rd を復元すること、および
#                md に grouping include が残っていないことを確認する
#   --diff       差分のあったファイルの先頭差分行を表示する
#   -v           全ファイルの結果を表示する

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'bitclust/rrd_to_markdown'
require 'bitclust/markdown_to_rrd'
require 'bitclust/markdown_orchestrator'
require 'bitclust/doc_converter'
require 'bitclust/capi_converter'

with_doc = ARGV.delete('--with-doc')
with_capi = ARGV.delete('--with-capi')
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
  # *.rd と拡張子なし（spec/regexp18 等）。news/1.8.0.rd-2 系の
  # 旧分割ファイルは未参照のため対象外
  doc_files = Dir.glob('**/*', base: doc_root).select { |f|
    File.file?(File.join(doc_root, f)) &&
      (f.end_with?('.rd') || !File.basename(f).include?('.'))
  }
  targets += doc_files.map { |f| [File.join(doc_root, f), "doc:#{f}"] }
end
if with_capi
  capi_root = File.join(doctree, 'refm/capi/src')
  targets += Dir.glob('*.rd', base: capi_root).map { |f| [File.join(capi_root, f), "capi:#{f}"] }
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
      orchestrator.units(label, rrd)
                  .map { |u| [u.path, u.rrd, orchestrator.convert_unit(u), u.front_matter] }
    elsif label.start_with?('doc:')
      reduced = BitClust::DocConverter.reduce(rrd)
      [[label, reduced, BitClust::DocConverter.convert(rrd), nil]]
    elsif label.start_with?('capi:')
      [[label, rrd, BitClust::CapiConverter.convert(rrd), nil]]
    else
      [[label, rrd, BitClust::RRDToMarkdown.convert(rrd), nil]]
    end
  outs.each do |path, reduced, md, front_matter|
    units += 1
    ulabel = outs.size > 1 ? "#{label} -> #{path}" : label
    if (sites = prune_sites[label])
      remaining = md.lines.filter_map { |l| $1 if l =~ /\A\#@include\s*\((.*?)\)/ }
      leftover << ulabel unless (remaining & sites).empty?
    end
    # body 関係の不変条件は in-scope（front matter 注入あり）のみ。
    # スコープ外ファイルは凍結形のままなので対象外（サルベージで扱う）
    body_rels << ulabel if front_matter && !front_matter.empty? && body_relations?(md)
    back = BitClust::MarkdownToRRD.convert(md, capi: label.start_with?('capi:'))
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
