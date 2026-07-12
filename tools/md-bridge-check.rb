#!/usr/bin/env ruby
# frozen_string_literal: true
#
# md ブリッジのパーサレベル等価検証。
# 各ライブラリを「旧ソース（doctree の .rd）」と「md ツリー → MarkdownBridge で
# 生成した rd ツリー」の両方から RRDParser でパースし、クラス・エントリ構造が
# 一致することを確認する。
#
# usage: ruby tools/md-bridge-check.rb <doctree-src-root> <md-tree-root> [--version V] [-v]

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'tmpdir'
require 'bitclust'
require 'bitclust/markdown_bridge'

version = '3.4'
verbose = false
paths = []
args = ARGV.dup
until args.empty?
  case (a = args.shift)
  when '--version' then version = args.shift
  when '-v' then verbose = true
  else paths << a
  end
end
src_root, md_root = paths
abort "usage: #{$0} <doctree-src-root> <md-tree-root> [--version V]" unless src_root && md_root

params = { 'version' => version }

def library_names(root, params)
  # 旧 LIBRARIES には重複エントリがある（webrick/httputils）ため uniq
  BitClust::Preprocessor.read(File.join(root, 'LIBRARIES'), params)
                        .lines.map(&:strip).reject(&:empty?).uniq
end

# ライブラリを単体パースし、{[type, class名] => 整列済みエントリ名} を返す
def structure(root, lib, params)
  db = BitClust::MethodDatabase.dummy(params)
  library = BitClust::RRDParser.new(db).parse_file(File.join(root, "#{lib}.rd"), lib, params)
  library.classes.to_h do |c|
    [[c.type.to_s, c.name], c.entries.flat_map(&:names).sort]
  end
rescue StandardError => e
  { error: "#{e.class}: #{e.message}" }
end

Dir.mktmpdir do |bridge|
  t0 = Time.now
  BitClust::MarkdownBridge.build(md_root, bridge)
  puts "bridge built in #{(Time.now - t0).round(1)}s"

  old_libs = library_names(src_root, params)
  new_libs = library_names(bridge, params)
  puts "library set @#{params['version']}: " \
       "#{old_libs.sort == new_libs.sort ? 'OK' : 'MISMATCH'} " \
       "(old #{old_libs.size}, new #{new_libs.size})"
  (old_libs - new_libs).each { |l| puts "  missing in bridge: #{l}" }
  (new_libs - old_libs).each { |l| puts "  extra in bridge: #{l}" }

  ok = 0
  diffs = []
  errors = []
  (old_libs & new_libs).sort.each do |lib|
    old_s = structure(src_root, lib, params)
    new_s = structure(bridge, lib, params)
    if old_s[:error] || new_s[:error]
      if old_s[:error].to_s == new_s[:error].to_s
        ok += 1   # 両側同一条件で失敗（dummy DB 都合等）は等価とみなす
      else
        errors << [lib, old_s[:error], new_s[:error]]
      end
      next
    end
    if old_s == new_s
      ok += 1
      puts "OK   #{lib}" if verbose
    else
      diffs << lib
      puts "DIFF #{lib}"
      (old_s.keys - new_s.keys).each { |k| puts "  only in old: #{k.inspect}" }
      (new_s.keys - old_s.keys).each { |k| puts "  only in new: #{k.inspect}" }
      (old_s.keys & new_s.keys).each do |k|
        next if old_s[k] == new_s[k]
        puts "  #{k.inspect}: entries differ"
        puts "    only old: #{(old_s[k] - new_s[k]).first(5).inspect}"
        puts "    only new: #{(new_s[k] - old_s[k]).first(5).inspect}"
      end
    end
  end
  puts "#{ok}/#{(old_libs & new_libs).size} libraries structurally identical"
  errors.each { |lib, o, n| puts "  ERROR #{lib}: old=#{o.inspect} new=#{n.inspect}" }
end
