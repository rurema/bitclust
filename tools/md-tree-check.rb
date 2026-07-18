#!/usr/bin/env ruby
# frozen_string_literal: true
#
# 変換後の Markdown ツリーの発見・検証（MARKUP_SPEC §1.1）。
# LIBRARIES を使わず glob + front matter + H1 だけで構成を組み立て、
# 孤児・関係リント等の警告を報告する。
#
# usage: ruby tools/md-tree-check.rb <md-tree-root> [--src <doctree-src-root>]
#   --src を与えると、ソース側 include グラフと突き合わせて
#   - 発見したライブラリ集合が in-scope ライブラリと一致するか
#   - 「library の無いエンティティ」がスコープ外（サルベージ待ち）由来だけか
#   - in-scope エンティティ名の重複が無いか
#   を確認する

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'bitclust/markdown_tree'
require 'bitclust/include_graph'

md_root = nil
src_root = nil
scope_arg = nil
args = ARGV.dup
until args.empty?
  a = args.shift
  if a == '--src'
    src_root = args.shift
  elsif a == '--scope'
    scope_arg = args.shift
  else
    md_root = a
  end
end
abort "usage: #{$0} <md-tree-root> [--src <doctree-src-root>] [--scope LO,HI]" unless md_root

tree = BitClust::MarkdownTree.scan(md_root)
entity_count = tree.entities.values.sum { |e| e[:names].size }
puts "libraries: #{tree.libraries.size}, entity files: #{tree.entities.size} " \
     "(#{entity_count} entities), fragments: #{tree.fragments.size}"

no_lib = tree.entities.select { |path, e| e[:library].nil? && !tree.libraries.key?(path.sub(/\.md\z/, '')) }
puts "entities without library: #{no_lib.size}"

if src_root
  graph = BitClust::IncludeGraph.analyze(src_root)
  scope = BitClust::IncludeGraph::Scope.new(*(scope_arg || '3.0,4.2').split(','))
  fm = graph.front_matter_map(scope)
  lib_fm = graph.library_front_matter_map(scope)

  md_path = ->(rel) { rel.end_with?('.rd') ? rel.sub(/\.rd\z/, '.md') : "#{rel}.md" }

  # ライブラリ集合のパリティ
  expected_libs = lib_fm.keys.map { |r| r.sub(/\.rd\z/, '') }.sort
  actual_libs = tree.libraries.keys.sort
  puts "library set parity: #{actual_libs == expected_libs ? 'OK' : 'MISMATCH'} " \
       "(expected #{expected_libs.size}, found #{actual_libs.size})"
  (expected_libs - actual_libs).each { |l| puts "  missing library: #{l}" }
  (actual_libs - expected_libs).each { |l| puts "  unexpected library: #{l}" }

  # library なしエンティティの期待バケット:
  # (1) スコープ外メンバー（グラフ到達だがスコープ外。サルベージ待ち）
  # (2) スコープ外ライブラリのルート（LIBRARIES ゲートで除外、インライン・エンティティ持ち）
  # (3) ソース孤児（グラフ到達不能の旧世代ファイル）
  out_members = (graph.groupings.keys - fm.keys).map { |r| md_path.call(r) }
  all_lib_roots = File.foreach(File.join(src_root, 'LIBRARIES'))
                      .map(&:chomp).reject { |l| l.empty? || l.start_with?('#@') }
                      .map { |n| "#{n}.rd" }.uniq
  out_lib_mds = (all_lib_roots - lib_fm.keys).map { |r| md_path.call(r) }
  reachable = graph.groupings.keys + graph.fragments + all_lib_roots
  src_files = Dir.glob('**/*', base: src_root)
                 .select { |f| File.file?(File.join(src_root, f)) } - ['LIBRARIES']
  orphan_mds = (src_files - reachable).map { |r| md_path.call(r) }

  buckets = { 'out-of-scope member' => out_members,
              'out-of-scope library' => out_lib_mds,
              'source orphan' => orphan_mds }
  rest = no_lib.keys
  buckets.each do |label, set|
    hit = rest & set
    rest -= hit
    puts "  #{label}: #{hit.size}"
  end
  puts "  UNEXPECTED: #{rest.size}"
  rest.each { |p| puts "    #{p}" }

  # in-scope エンティティ名の重複（reopen/redefine は各 lib からの寄与なので除外）
  names = Hash.new { |h, k| h[k] = [] }
  tree.entities.each do |path, e|
    next if e[:library].nil? && !tree.libraries.key?(path.sub(/\.md\z/, ''))
    e[:kinds].each { |kind, n| names[n] << path if %w[class module object].include?(kind) }
  end
  dups = names.select { |_, paths| paths.uniq.size > 1 }
  puts "in-scope entity definition duplicates (reopen/redefine 除外): #{dups.size}"
  dups.each { |n, paths| puts "  #{n}: #{paths.uniq.join(', ')}" }

  # 警告をスコープ外・ソース孤児（期待=サルベージ待ち）とそれ以外に分類
  expected_paths = (out_members + out_lib_mds + orphan_mds).to_h { |p| [p, true] }
  expected, real = tree.warnings.partition do |w|
    path = w[/\S+\.md\z/]
    path && expected_paths[path]
  end
  puts "warnings: #{tree.warnings.size} " \
       "(expected out-of-scope/salvage: #{expected.size}, needs attention: #{real.size})"
  real.each { |w| puts "  W: #{w}" }
else
  puts "warnings: #{tree.warnings.size}"
  tree.warnings.each { |w| puts "  W: #{w}" }
end
