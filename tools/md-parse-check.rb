#!/usr/bin/env ruby
# frozen_string_literal: true
#
# MDParser のネイティブ md パース検証（M3）。
# manual/api をネイティブパースした DB と、ブリッジ経由で構築した DB を比較する:
#   (1) library/class/entry の集合と属性が一致
#   (2) native の entry.source（md）を md→rd 変換するとブリッジの source（rd）に一致
#
# usage: ruby tools/md-parse-check.rb <manual/api> <bridge-db> [--keep DIR]

$stdout.sync = true
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'bitclust'
require 'bitclust/markdown_to_rrd'
require 'tmpdir'

md_root = ARGV[0] or abort "usage: #{$0} <manual/api> <bridge-db>"
bridge_path = ARGV[1] or abort "usage: #{$0} <manual/api> <bridge-db>"
keep_dir = (i = ARGV.index('--keep')) ? ARGV[i + 1] : nil

bridge = BitClust::MethodDatabase.new(bridge_path)
version = bridge.properties['version']

native_dir = keep_dir || Dir.mktmpdir('md-parse-check')
native = BitClust::MethodDatabase.new(native_dir)
unless File.exist?(File.join(native_dir, 'properties'))
  native.init
  native.transaction do
    native.propset 'version', version
    native.propset 'encoding', bridge.properties['encoding']
  end
end
puts "native parse (version #{version})..."
native.transaction do
  native.update_by_markdowntree(md_root)
end
# ブリッジ側（ディスクから読む）と条件を揃える。require が作る未保存の
# スタブライブラリ等、メモリ上にしか無いものを比較に混ぜない
native = BitClust::MethodDatabase.new(native_dir)

diffs = 0
report = ->(msg) { diffs += 1; puts "DIFF #{msg}" if diffs <= 30 }

# ブリッジ DB の source は Preprocessor 通過後（#@samplecode → //emlist 済み）。
# native md → rd 変換の生形式を同じ形へ正規化して比較する
to_rd = lambda do |md_src|
  BitClust::MarkdownToRRD.convert(md_src)
    .gsub(/^\#@samplecode(?: (.*))?$/) { "//emlist[#{$1&.strip}][ruby]{" }
    .gsub(/^\#@end[ \t]*$/, '//}')
    .rstrip
end

# (1) ライブラリ
bl = bridge.libraries.to_h { |l| [l.name, l] }
nl = native.libraries.to_h { |l| [l.name, l] }
report.call("library set: missing=#{(bl.keys - nl.keys).size} extra=#{(nl.keys - bl.keys).size}: #{((bl.keys - nl.keys) + (nl.keys - bl.keys)).first(5)}") if bl.keys.sort != nl.keys.sort
common_libs = bl.keys & nl.keys
common_libs.each do |name|
  b, n = bl[name], nl[name]
  report.call("lib #{name}: category #{b.category.inspect} vs #{n.category.inspect}") if b.category != n.category
  report.call("lib #{name}: requires #{b.requires.map(&:name)} vs #{n.requires.map(&:name)}") if b.requires.map(&:name).sort != n.requires.map(&:name).sort
  report.call("lib #{name}: sublibraries") if b.sublibraries.map(&:name).sort != n.sublibraries.map(&:name).sort
  report.call("lib #{name}: classes #{(b.classes.map(&:name) - n.classes.map(&:name)).first(3)} / #{(n.classes.map(&:name) - b.classes.map(&:name)).first(3)}") if b.classes.map(&:name).sort != n.classes.map(&:name).sort
  if to_rd.call(n.source.to_s + "\n") != b.source.to_s.rstrip
    report.call("lib #{name}: source differs")
  end
end

# (2) クラスとエントリ
bc = bridge.classes.to_h { |c| [c.name, c] }
nc = native.classes.to_h { |c| [c.name, c] }
report.call("class set: missing=#{(bc.keys - nc.keys).first(5)} extra=#{(nc.keys - bc.keys).first(5)}") if bc.keys.sort != nc.keys.sort
entry_count = 0
src_diffs = 0
(bc.keys & nc.keys).each do |name|
  b, n = bc[name], nc[name]
  report.call("class #{name}: type #{b.type} vs #{n.type}") if b.type != n.type
  report.call("class #{name}: superclass") if b.superclass&.name != n.superclass&.name
  report.call("class #{name}: included #{b.included.map(&:name)} vs #{n.included.map(&:name)}") if b.included.map(&:name) != n.included.map(&:name)
  report.call("class #{name}: extended") if b.extended.map(&:name) != n.extended.map(&:name)
  report.call("class #{name}: dyn-included") if b.dynamically_included.map(&:name).sort != n.dynamically_included.map(&:name).sort
  if to_rd.call(n.source.to_s + "\n") != b.source.to_s.rstrip
    report.call("class #{name}: source differs")
  end

  be = b.entries.to_h { |e| [e.names.sort.join(','), e] }
  ne = n.entries.to_h { |e| [e.names.sort.join(','), e] }
  report.call("#{name} entries: missing=#{(be.keys - ne.keys).first(3)} extra=#{(ne.keys - be.keys).first(3)}") if be.keys.sort != ne.keys.sort
  (be.keys & ne.keys).each do |key|
    entry_count += 1
    x, y = be[key], ne[key]
    report.call("#{name}##{key}: type #{x.type} vs #{y.type}") if x.type != y.type
    report.call("#{name}##{key}: visibility") if x.visibility != y.visibility
    if to_rd.call(y.source.to_s) != x.source.to_s.rstrip
      src_diffs += 1
      if src_diffs <= 5
        puts "SRC-DIFF #{name}##{key}:"
        a = x.source.to_s.rstrip.lines
        c = to_rd.call(y.source.to_s).lines
        a.zip(c).each_with_index do |(p, q), i|
          next if p == q
          puts "  line #{i + 1}: BRIDGE #{p.inspect}"
          puts "            NATIVE #{q.inspect}"
          break
        end
      end
    end
  end
end

puts "libraries: #{common_libs.size}, classes: #{(bc.keys & nc.keys).size}, entries: #{entry_count}"
puts "attribute diffs: #{diffs}, source diffs (md→rd 変換後): #{src_diffs}"
puts diffs.zero? && src_diffs.zero? ? 'NATIVE PARSE EQUIVALENT' : 'NOT EQUIVALENT'
FileUtils.remove_entry(native_dir) unless keep_dir
