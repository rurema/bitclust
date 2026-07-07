#!/usr/bin/env ruby
# frozen_string_literal: true
#
# 2つの BitClust データベースを比較する（md 移行の DB レベル等価検証）。
# ライブラリ・クラス・メソッドの集合と、全エントリの本文（source）まで突き合わせる。
#
# usage: ruby tools/md-db-check.rb <db-old> <db-new>

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'bitclust'

old_path, new_path = ARGV
abort "usage: #{$0} <db-old> <db-new>" unless old_path && new_path

old_db = BitClust::MethodDatabase.new(old_path)
new_db = BitClust::MethodDatabase.new(new_path)

diffs = 0
report = lambda do |msg|
  diffs += 1
  puts "  DIFF #{msg}"
end

compare_sets = lambda do |label, old_set, new_set|
  only_old = old_set - new_set
  only_new = new_set - old_set
  only_old.each { |x| report.call("#{label} only in old: #{x}") }
  only_new.each { |x| report.call("#{label} only in new: #{x}") }
  old_set & new_set
end

# ライブラリ
old_libs = old_db.libraries.to_h { |l| [l.name, l] }
new_libs = new_db.libraries.to_h { |l| [l.name, l] }
common_libs = compare_sets.call('library', old_libs.keys.sort, new_libs.keys.sort)
puts "libraries: #{common_libs.size} common"

lib_field_diffs = 0
common_libs.each do |name|
  o, n = old_libs[name], new_libs[name]
  lib_field_diffs += 1 if o.requires.map(&:name).sort != n.requires.map(&:name).sort
  lib_field_diffs += 1 if o.sublibraries.map(&:name).sort != n.sublibraries.map(&:name).sort
  report.call("library #{name}: source differs") if o.source.strip != n.source.strip
end
puts "library require/sublibrary diffs: #{lib_field_diffs}"

# クラスとエントリ
old_classes = old_db.classes.to_h { |c| [c.name, c] }
new_classes = new_db.classes.to_h { |c| [c.name, c] }
common = compare_sets.call('class', old_classes.keys.sort, new_classes.keys.sort)
puts "classes: #{common.size} common"

entry_count = 0
ws_only = 0
sig_spacing_only = 0
source_diffs = []
# 「---name」（スペース無しシグネチャ）は正規形「--- name」へ寄せる
# （RRDParser/RDCompiler はどちらも受理。openssl の8箇所）
normalize_sig = ->(src) { src.gsub(/^---(?=[^\s-])/, '--- ') }
common.each do |name|
  o, n = old_classes[name], new_classes[name]
  report.call("class #{name}: type #{o.type} vs #{n.type}") if o.type != n.type
  report.call("class #{name}: superclass differs") if o.superclass&.name != n.superclass&.name
  report.call("class #{name}: source differs") if o.source.strip != n.source.strip

  o_entries = o.entries.to_h { |e| [e.names.sort.join(','), e] }
  n_entries = n.entries.to_h { |e| [e.names.sort.join(','), e] }
  common_entries = compare_sets.call("#{name} entry", o_entries.keys.sort, n_entries.keys.sort)
  common_entries.each do |key|
    entry_count += 1
    next if o_entries[key].source == n_entries[key].source
    if o_entries[key].source.rstrip == n_entries[key].source.rstrip
      ws_only += 1   # 末尾空白のみ（描画に影響しない）
    elsif normalize_sig.call(o_entries[key].source) == n_entries[key].source
      sig_spacing_only += 1
    else
      source_diffs << "#{name}##{key}"
    end
  end
end
puts "entries compared: #{entry_count}, real source diffs: #{source_diffs.size}, " \
     "trailing-whitespace-only: #{ws_only}, signature-spacing-only: #{sig_spacing_only}"
source_diffs.first(10).each { |s| puts "  SOURCE DIFF #{s}" }

# doc（散文ページ）。md 経路は DocConverter.reduce の正規化（末尾スペース・
# タブ・定義リスト空白等、意味を変えない表記ゆれ）を通るため、
# 旧側も reduce に通した上での一致を「正規化後一致」として別集計する
require 'bitclust/doc_converter'
old_docs = old_db.docs.to_h { |d| [d.name, d] }
new_docs = new_db.docs.to_h { |d| [d.name, d] }
common_docs = compare_sets.call('doc', old_docs.keys.sort, new_docs.keys.sort)
doc_normalized = 0
doc_diffs = common_docs.count do |k|
  next false if old_docs[k].source == new_docs[k].source
  if BitClust::DocConverter.reduce(old_docs[k].source) == new_docs[k].source
    doc_normalized += 1
    false
  else
    true
  end
end
puts "docs: #{common_docs.size} common, real source diffs: #{doc_diffs}, " \
     "normalized-only: #{doc_normalized}"

if diffs.zero? && source_diffs.empty? && doc_diffs.zero?
  notes = []
  notes << "#{ws_only} trailing-whitespace-only" if ws_only.positive?
  notes << "#{sig_spacing_only} signature-spacing-only" if sig_spacing_only.positive?
  puts "DATABASES EQUIVALENT#{notes.empty? ? '' : " (#{notes.join(', ')} diffs)"}"
else
  puts "TOTAL STRUCTURAL DIFFS: #{diffs + source_diffs.size + doc_diffs}"
end
