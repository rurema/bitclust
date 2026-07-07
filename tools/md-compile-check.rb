#!/usr/bin/env ruby
# frozen_string_literal: true
#
# MDCompiler の HTML 等価検証（ネイティブ MD 描画 M1）。
# データベースの全エントリについて、
#   rd source → RDCompiler → HTML（リファレンス）
#   rd source → RRDToMarkdown → md source → MDCompiler → HTML
# が一致することを確認する。fragment の md→rd ラウンドトリップも同時に検証。
#
# usage: ruby tools/md-compile-check.rb <db-path> [--limit N] [-v]
#          [--only methods|docs|libs|functions] [--shard K/N] [--gfm]
#
# メモリの少ないマシンでは 1 プロセスで全件を回さず、--only/--shard で
# 分割して直列に実行する（例: --only methods --shard 0/4 ... 3/4）。
#
# --gfm: M2 GFM モードの整合も検証する。GFM 出力と M1 出力の差が
# <code>/<strong>/GNU 引用（`x'）の正規化で消えることを確認する
# （= GFM モードが追加するのは表現マークアップだけで内容は同一）。

$stdout.sync = true
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'bitclust'
require 'bitclust/rdcompiler'
require 'bitclust/mdcompiler'
require 'bitclust/rrd_to_markdown'
require 'bitclust/markdown_to_rrd'
require 'bitclust/capi_converter'

limit = nil
verbose = false
only = nil
shard_k = nil
shard_n = nil
gfm_mode = false
paths = []
args = ARGV.dup
until args.empty?
  case (a = args.shift)
  when '--limit' then limit = args.shift.to_i
  when '--only' then only = args.shift
  when '--shard'
    shard_k, shard_n = (args.shift || '').split('/').map(&:to_i)
  when '--gfm' then gfm_mode = true
  when '-v' then verbose = true
  else paths << a
  end
end
db_path = paths.shift or abort "usage: #{$0} <db-path> [--limit N]"

run = ->(kind) { only.nil? || only == kind }
in_shard = ->(i) { shard_n.nil? || i % shard_n == shard_k }

db = BitClust::MethodDatabase.new(db_path)
urlmapper = BitClust::URLMapper.new(Hash.new { 'dummy' })
rd = BitClust::RDCompiler.new(urlmapper, 1, { database: db })
md = BitClust::MDCompiler.new(urlmapper, 1, { database: db })
mdg = BitClust::MDCompiler.new(urlmapper, 1, { database: db, gfm: true })

stats = Hash.new(0)
diffs = []

# GFM が追加する表現マークアップを落として M1 と比較するための正規化
normalize_gfm = lambda do |html|
  html.gsub(%r{</?code>|</?strong>|<(th|td) align="[a-z]+">}, '')
      .gsub(%r{</?(?:table|thead|tbody|tr|th|td)>}, '')
      .gsub(/`([^`'\s]+)'/) { $1 }
end

check = lambda do |label, kind, rd_src, ref_html|
  md_src = kind == :function ? BitClust::CapiConverter.convert(rd_src)
                             : BitClust::RRDToMarkdown.convert(rd_src)
  back = BitClust::MarkdownToRRD.convert(md_src, capi: kind == :function)
  stats[:rt_diff] += 1 if back != rd_src

  html =
    case kind
    when :method
      # 実エントリの source を一時差し替え（save しないので永続化されない）
      entry = stats[:current_entry]
      original = entry.source
      begin
        entry.source = md_src
        md.compile_method(entry, nil)
      ensure
        entry.source = original
      end
    when :function
      entry = stats[:current_entry]
      original = entry.source
      begin
        entry.source = md_src
        md.compile_function(entry, nil)
      ensure
        entry.source = original
      end
    else
      md.compile(md_src)
    end
  if gfm_mode
    gfm_html =
      case kind
      when :method, :function
        entry = stats[:current_entry]
        original = entry.source
        begin
          entry.source = md_src
          kind == :method ? mdg.compile_method(entry, nil) : mdg.compile_function(entry, nil)
        ensure
          entry.source = original
        end
      else
        mdg.compile(md_src)
      end
    if normalize_gfm.call(gfm_html) == normalize_gfm.call(html)
      stats[:gfm_ok] += 1
    else
      stats[:gfm_diff] += 1
      if stats[:gfm_diff] <= 10
        puts "GFM-DIFF #{label}"
        normalize_gfm.call(html).lines.zip(normalize_gfm.call(gfm_html).lines).each_with_index do |(a, b), i|
          next if a == b
          puts "  line #{i + 1}: M1 =#{a.inspect}"
          puts "            GFM=#{b.inspect}"
          break
        end
      end
    end
  end

  if html == ref_html
    stats[:ok] += 1
    puts "OK   #{label}" if verbose
  else
    stats[:diff] += 1
    diffs << label
    if diffs.size <= 10
      puts "DIFF #{label}"
      ref_html.lines.zip(html.lines).each_with_index do |(a, b), i|
        next if a == b
        puts "  line #{i + 1}: RD=#{a.inspect}"
        puts "           MD=#{b.inspect}"
        break
      end
    end
  end
rescue StandardError => e
  stats[:error] += 1
  diffs << label
  puts "ERROR #{label}: #{e.class}: #{e.message}" if stats[:error] <= 10
end

count = 0
db.classes.sort_by(&:name).each_with_index do |c, ci|
  break unless run.call('methods')
  next unless in_shard.call(ci)
  c.entries.sort_by { |e| e.names.join }.each do |m|
    break if limit && count >= limit
    count += 1
    ref = begin
      rd.compile_method(m, nil)
    rescue StandardError => e
      stats[:ref_error] += 1
      puts "REF-ERROR #{c.name}##{m.names.first}: #{e.class}: #{e.message}" if stats[:ref_error] <= 5
      next
    end
    stats[:current_entry] = m
    check.call("#{c.name}##{m.names.first}", :method, m.source, ref)
  end
end

db.docs.sort_by(&:name).each do |d|
  break unless run.call('docs')
  ref = begin
    rd.compile(d.source)
  rescue StandardError
    stats[:ref_error] += 1
    next
  end
  check.call("doc:#{d.name}", :doc, d.source, ref)
end

db.libraries.sort_by(&:name).each do |l|
  break unless run.call('libs')
  next if l.source.strip.empty?
  ref = begin
    rd.compile(l.source)
  rescue StandardError
    stats[:ref_error] += 1
    next
  end
  check.call("lib:#{l.name}", :doc, l.source, ref)
end

begin
  fdb = BitClust::FunctionDatabase.new(db_path) if run.call('functions')
  fdb ||= nil
  (fdb ? fdb.functions.sort_by(&:name) : []).each do |f|
    ref = begin
      rd.compile_function(f, nil)
    rescue StandardError
      stats[:ref_error] += 1
      next
    end
    stats[:current_entry] = f
    check.call("capi:#{f.name}", :function, f.source, ref)
  end
rescue StandardError
  puts '(no function database)'
end

puts "compared: #{stats[:ok] + stats[:diff]}, identical: #{stats[:ok]}, " \
     "diffs: #{stats[:diff]}, errors: #{stats[:error]}, " \
     "ref-errors(skipped): #{stats[:ref_error]}, fragment-roundtrip diffs: #{stats[:rt_diff]}"
puts "gfm: consistent: #{stats[:gfm_ok]}, diffs: #{stats[:gfm_diff]}" if gfm_mode
diffs.first(30).each { |d| puts "  DIFF #{d}" } if stats[:diff] > 10
ok = stats[:diff].zero? && stats[:error].zero? && stats[:gfm_diff].zero?
puts ok ? 'HTML EQUIVALENT' : 'NOT EQUIVALENT'
