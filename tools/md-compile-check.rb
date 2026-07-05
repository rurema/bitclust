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

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'bitclust'
require 'bitclust/rdcompiler'
require 'bitclust/mdcompiler'
require 'bitclust/rrd_to_markdown'
require 'bitclust/markdown_to_rrd'
require 'bitclust/capi_converter'

limit = nil
verbose = false
paths = []
args = ARGV.dup
until args.empty?
  case (a = args.shift)
  when '--limit' then limit = args.shift.to_i
  when '-v' then verbose = true
  else paths << a
  end
end
db_path = paths.shift or abort "usage: #{$0} <db-path> [--limit N]"

db = BitClust::MethodDatabase.new(db_path)
urlmapper = BitClust::URLMapper.new(Hash.new { 'dummy' })
rd = BitClust::RDCompiler.new(urlmapper, 1, { database: db })
md = BitClust::MDCompiler.new(urlmapper, 1, { database: db })

stats = Hash.new(0)
diffs = []

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
db.classes.sort_by(&:name).each do |c|
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
  ref = begin
    rd.compile(d.source)
  rescue StandardError
    stats[:ref_error] += 1
    next
  end
  check.call("doc:#{d.name}", :doc, d.source, ref)
end

db.libraries.sort_by(&:name).each do |l|
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
  fdb = BitClust::FunctionDatabase.new(db_path)
  fdb.functions.sort_by(&:name).each do |f|
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
diffs.first(30).each { |d| puts "  DIFF #{d}" } if stats[:diff] > 10
puts stats[:diff].zero? && stats[:error].zero? ? 'HTML EQUIVALENT' : 'NOT EQUIVALENT'
