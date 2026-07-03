# frozen_string_literal: true

module BitClust
  # doctree の #@include グラフを版ゲート付きで解析する。
  #
  # LIBRARIES の各エントリ <name> をルートファイル <name>.rd として、
  # #@include(target) を include 元ディレクトリ相対で解決しながら再帰的に走査し、
  # 各ファイルの分類（grouping = エンティティ / fragment = 共有断片）と、
  # grouping ファイルの全所属（ライブラリ + 経路上の版条件）を生のまま収集する。
  #
  # 特定の版範囲（[3.0, 4.2) 等）への絞り込みは行わない faithful 層。
  # スコープ適用は IncludeGraph::Scope が担い、範囲はパラメータ化されている
  # （旧版サルベージ時に別範囲で再利用するため）。
  class IncludeGraph
    # 版条件。kind は :since / :until / :if。
    # version は :since/:until ではバージョン文字列、:if では条件式文字列。
    Condition = Struct.new(:kind, :version)

    # grouping ファイルの1所属。conditions は LIBRARIES のゲート＋include 経路上の
    # 条件スタックのスナップショット（faithful、スコープ未適用）。
    Membership = Struct.new(:library, :conditions)

    # RRDParser は /\A=[^=]/ で H1 行を認識し `=` 直後の空白は必須でない
    # （実データ: _builtin/Encoding は「=class Encoding」）
    ENTITY_H1_RE = /\A=(?!=)\s*(?:class|module|object|reopen|redefine)\b/

    def self.analyze(src_root)
      new(src_root).analyze
    end

    # conditions が表す版区間 [lo, hi)。lo/hi は Gem::Version、制約なしは nil。
    # :since は max、:until は min を取る。:if は版制約に寄与しない。
    def self.interval(conditions)
      lo = conditions.select { |c| c.kind == :since }.map { |c| Gem::Version.new(c.version) }.max
      hi = conditions.select { |c| c.kind == :until }.map { |c| Gem::Version.new(c.version) }.min
      [lo, hi]
    end

    # 対象版範囲 [lo, hi)。範囲はパラメータであり、[3.0, 4.2) 以外
    # （旧版サルベージ等）でも同じ解析結果に対して再利用できる。
    class Scope
      def initialize(lo, hi)
        @lo = Gem::Version.new(lo)
        @hi = Gem::Version.new(hi)
      end

      # conditions の版区間がスコープと交差するか
      def cover?(conditions)
        lo, hi = IncludeGraph.interval(conditions)
        return false if lo && hi && lo >= hi   # 空区間
        (lo.nil? || lo < @hi) && (hi.nil? || hi > @lo)
      end

      # front matter に書く構造ゲート。スコープ内で効く境界のみ残す
      # （下限以下の since・上限以上の until は省略）。スコープ外なら nil。
      # バージョン文字列は原文の表記を保持する。
      def gate(conditions)
        return nil unless cover?(conditions)
        lo, hi = IncludeGraph.interval(conditions)
        gate = {}
        if lo && lo > @lo
          gate[:since] = conditions.find { |c| c.kind == :since && Gem::Version.new(c.version) == lo }.version
        end
        if hi && hi < @hi
          gate[:until] = conditions.find { |c| c.kind == :until && Gem::Version.new(c.version) == hi }.version
        end
        gate
      end
    end

    attr_reader :warnings

    def initialize(src_root)
      @src_root = src_root
      @memberships = {}   # relpath => [Membership]
      @kinds = {}         # relpath => :grouping | :fragment
      @warnings = []
    end

    def analyze
      read_libraries.each do |name, gate|
        root = "#{name}.rd"
        unless File.file?(File.join(@src_root, root))
          @warnings << "library root not found: #{root}"
          next
        end
        walk(root, name, gate, [root])
      end
      self
    end

    # grouping ファイル relpath の全 membership（生・スコープ未適用）
    def memberships(relpath)
      @memberships.fetch(relpath, [])
    end

    def groupings
      @kinds.select { |_, kind| kind == :grouping }.keys.sort
             .to_h { |path| [path, @memberships.fetch(path, [])] }
    end

    def fragments
      @kinds.select { |_, kind| kind == :fragment }.keys.sort
    end

    # 各 grouping メンバーへ注入する front matter（スコープ適用済み）。
    # { relpath => { "library" => name, "since" => v, "until" => v } }
    # RRDToMarkdown の extra_front_matter: にそのまま渡せる形。
    #
    # - スコープ外のメンバーは含まない（旧版サルベージは別スコープで再実行）
    # - スコープ内で複数ライブラリに所属するメンバーは警告してスキップ
    #   （現データでは 0 件。発生したら front matter スキーマ側の対応が必要）
    # - 同一ライブラリ内の複数 include サイトは、いずれかが有効なら
    #   エンティティが存在するため、ゲートは区間の hull（弱い方）を取る
    def front_matter_map(scope)
      result = {}
      groupings.each do |path, ms|
        covered = ms.select { |m| scope.cover?(m.conditions) }
        next if covered.empty?
        libraries = covered.map(&:library).uniq
        if libraries.size > 1
          @warnings << "in-scope multi-membership: #{path} -> #{libraries.inspect}"
          next
        end
        fm = { 'library' => libraries.first }
        gate = hull(covered.map { |m| scope.gate(m.conditions) })
        fm['since'] = gate[:since] if gate[:since]
        fm['until'] = gate[:until] if gate[:until]
        result[path] = fm
      end
      result
    end

    private

    # 複数サイトのゲートの hull。片方でも無条件（{}）なら無条件。
    # since は最小、until は最大を取る（全サイトに揃っている境界のみ残る）。
    def hull(gates)
      return {} if gates.any?(&:empty?)
      sinces = gates.map { |g| g[:since] }
      untils = gates.map { |g| g[:until] }
      result = {}
      result[:since] = sinces.min_by { |v| Gem::Version.new(v) } if sinces.all?
      result[:until] = untils.max_by { |v| Gem::Version.new(v) } if untils.all?
      result
    end

    # LIBRARIES を版ゲート付きで読む。 [[name, [Condition]], ...]
    def read_libraries
      entries = {}
      stack = []
      File.foreach(File.join(@src_root, 'LIBRARIES')) do |line|
        line = line.chomp
        if line.start_with?('#@#') || apply_directive(stack, line)
          next
        elsif line !~ /\A\s*\z/
          entries[line] ||= stack.dup
        end
      end
      entries
    end

    # #@ ディレクティブなら条件スタックを更新して true を返す。
    # #@samplecode もブロック（#@end で閉じる）なので、pop の対応を
    # 取るために :samplecode を積む（版条件ではないので snapshot では除外する）。
    def apply_directive(stack, line)
      case line
      when /\A\#@since\s+(\S+)/  then stack.push(Condition.new(:since, $1))
      when /\A\#@until\s+(\S+)/  then stack.push(Condition.new(:until, $1))
      when /\A\#@if\s*(.*)/      then stack.push(Condition.new(:if, $1.strip))
      when /\A\#@samplecode\b/   then stack.push(Condition.new(:samplecode, nil))
      when /\A\#@else\b/         then (cond = stack.pop) && stack.push(invert(cond))
      when /\A\#@end\b/          then stack.pop
      else return false
      end
      true
    end

    def invert(cond)
      case cond.kind
      when :since then Condition.new(:until, cond.version)
      when :until then Condition.new(:since, cond.version)
      when :if    then Condition.new(:if, "!(#{cond.version})")
      else cond
      end
    end

    # relpath のファイル内の #@include を条件スタック付きで走査する。
    # base_conditions は LIBRARIES ゲート＋ここまでの include 経路の条件。
    def walk(relpath, library, base_conditions, path_stack)
      stack = []
      File.foreach(File.join(@src_root, relpath)) do |line|
        line = line.chomp
        if line =~ /\A\#@include\s*\((.*?)\)/
          conditions = (base_conditions + stack).reject { |c| c.kind == :samplecode }
          add_include(relpath, $1, library, conditions, path_stack)
        else
          apply_directive(stack, line)
        end
      end
    end

    def add_include(from, target, library, conditions, path_stack)
      relpath = resolve(from, target)
      unless relpath
        @warnings << "include target not found: #{target} (from #{from})"
        return
      end
      kind = classify(relpath)
      @kinds[relpath] ||= kind

      if kind == :grouping
        m = Membership.new(library, conditions)
        list = (@memberships[relpath] ||= [])
        list << m unless list.include?(m)
      end

      if path_stack.include?(relpath)
        @warnings << "include cycle: #{(path_stack + [relpath]).join(' -> ')}"
        return
      end
      # fragment も走査する: fragment を経由して grouping へ至る transclusion
      # チェーンがある（fiddle.rd → fiddle/2.0/fiddle.rd → Fiddle 等）
      walk(relpath, library, conditions, path_stack + [relpath])
    end

    # include 元ディレクトリ相対で target → target.rd の順に解決。
    # `../` を含む参照があるため正規化する（同一ファイルの二重登録防止）
    def resolve(from, target)
      base = File.dirname(from)
      [target, "#{target}.rd"].each do |cand|
        rel = base == '.' ? cand : File.join(base, cand)
        rel = File.expand_path(rel, '/').delete_prefix('/')
        return rel if File.file?(File.join(@src_root, rel))
      end
      nil
    end

    # 最初の非空・非 #@ 行がエンティティ H1 なら grouping、そうでなければ fragment
    def classify(relpath)
      File.foreach(File.join(@src_root, relpath)) do |line|
        next if line =~ /\A\s*\z/ || line.start_with?('#@')
        return line =~ ENTITY_H1_RE ? :grouping : :fragment
      end
      :fragment
    end
  end
end
