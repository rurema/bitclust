# frozen_string_literal: true
#
# bitclust/method_since_calculator.rb
#

require 'bitclust/exception'

module BitClust

  # 複数バージョンの DB(バージョンラダー)からメソッド名別の初出/削除
  # バージョンを算出し、対象 DB のメソッドエントリへ書き込む(bitclust#132 P2)。
  #
  # ライブラリは意図的に無視する: 同じメソッドが版によって別ライブラリの
  # 下でドキュメント化されていても、同一メソッドとして union で扱う。
  #
  # 算出値は「著者が明示した値(将来 P4 で {: since ...} 等から記録される
  # 想定)」より優先度が低い。#apply は MethodEntry#fill_since/fill_until を
  # 使うため、既に値がある名前は上書きしない。
  class MethodSinceCalculator

    def initialize(dbs)
      versions = dbs.map {|db| db.propget('version') }
      versions.each do |v|
        if v.nil? || v.empty?
          raise UserError, "database has no version property"
        end
      end
      dup = versions.tally.select {|_, n| n > 1 }.keys
      unless dup.empty?
        raise UserError, "duplicate version(s) in ladder: #{dup.join(', ')}"
      end
      sorted = dbs.sort_by {|db| Gem::Version.new(db.propget('version') || raise) }
      @versions = sorted.map {|db| db.propget('version') || raise }
      @ladder = sorted
      @first = {} #: Hash[key, String]
      @last  = {} #: Hash[key, String]
    end

    # ラダーの各 DB を1つずつ走査して [クラス名, typechar, 生名] ごとの
    # 初出/最終出現バージョンを記録する。走査済みの DB への参照は
    # メモリを膨らませないようその場で捨てる
    def scan
      ladder = @ladder or raise "scan was already called"
      @ladder = nil
      until ladder.empty?
        db = ladder.shift
        version = db.propget('version') || raise
        db.classes.each do |c|
          c.entries.each do |m|
            next if m.kind == :undefined
            m.names.each do |name|
              key = [c.name, m.typechar, name] #: key
              @first[key] ||= version
              @last[key] = version
            end
          end
        end
      end
      self
    end

    # key = [クラス名, typechar, 生名]。ラダー最古版から存在する(フロア)
    # 場合は「不明」を意味するので nil を返す
    def since_for(key)
      first = @first[key] or return nil
      first == (@versions.first || raise) ? nil : first
    end

    # ラダー最新版でも存在する場合は「まだ削除されていない」ので nil。
    # そうでなければ最終出現バージョンの次のラダーバージョン(削除された版)
    def until_for(key)
      last = @last[key] or return nil
      return nil if last == (@versions.last || raise)
      idx = @versions.index(last) or raise "must not happen: #{last.inspect}"
      @versions[idx + 1] || raise
    end

    # 対象 DB の各メソッドエントリへ算出済みの since/until を書き込む。
    # target_db のバージョンはラダーに含まれていなければならない。
    # 既に値がある名前は fill_since/fill_until の仕様により上書きされない
    # (著者による明示値が算出値より優先される)。冪等: 2回目の apply は
    # 何も変更しない(floor_skipped を除く)
    def apply(target_db)
      version = target_db.propget('version')
      unless @versions.include?(version)
        raise UserError, "#{version.inspect} is not one of the ladder versions: #{@versions.join(', ')}"
      end
      stats = {entries_updated: 0, since_filled: 0, until_filled: 0, floor_skipped: 0} #: stats
      target_db.classes.each do |c|
        c.entries.each do |m|
          next if m.kind == :undefined
          changed = false
          m.names.each do |name|
            key = [c.name, m.typechar, name] #: key
            if since_v = since_for(key)
              if m.fill_since(name, since_v)
                stats[:since_filled] += 1
                changed = true
              end
            else
              stats[:floor_skipped] += 1
            end
            if (until_v = until_for(key)) && m.fill_until(name, until_v)
              stats[:until_filled] += 1
              changed = true
            end
          end
          if changed
            m.save
            stats[:entries_updated] += 1
          end
        end
      end
      stats
    end
  end
end
