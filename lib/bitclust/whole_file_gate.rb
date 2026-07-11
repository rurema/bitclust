# frozen_string_literal: true

require 'bitclust/include_graph'

module BitClust
  # ファイル全体を包む単一の版ゲート（#@else 無し）の検出と解除（O4）。
  #
  # 旧 RRD ではライブラリ/エンティティ自体の版ゲートをファイル全体の
  # #@since/#@until/#@if ラップで表現していた。新パイプラインでは
  # front matter の since/until（構造ゲート）で表現するため、
  # スコープの下で「常に真」または「since/until で表現できる」ラップは外す。
  #
  # 据え置き（nil を返す）:
  # - #@else 付き（fiddle.rd。枝の選択は本文の版分岐として温存）
  # - スコープ外のゲート（profile.rd 等。旧版サルベージは別スコープで再実行）
  # - 常に真と証明できない #@if 条件
  module WholeFileGate
    GATE_OPEN_RE = /\A\#@(since|until|if)\s*(.*)$/
    BLOCK_OPEN_RE = /\A\#@(?:since|until|if|samplecode)\b/
    BLANK_RE = /\A\s*\z/

    # 常に真と証明できる #@if 条件の形（rss.rd の (version >= "1.8.2")）
    VERSION_GE_RE = /\A\(?\s*version\s*>=\s*"([\d.]+)"\s*\)?\z/

    module_function

    # ファイル全体を包むゲートの Condition を返す。該当しなければ nil
    def detect(src)
      open_idx, close_idx, cond, has_else = parse(src.lines)
      return nil if open_idx.nil? || has_else
      cond if close_idx
    end

    # 据え置きゲート（unwrap できない library ルート等）のメタデータ領域
    # （require/sublibrary/category）を、本文と分けてそれぞれ同じゲートで包んだ
    # 意味等価な正規形に書き換える。native パースはメタデータを front matter から
    # しか読まないため、ゲート内に埋もれた rd 形式のメタ行を、既存のゲート対応
    # メタデータ収集器が front matter 化できる位置（ファイル先頭のブロック）へ出す。
    # 全体ゲートでない・メタデータが無い・本文が無い場合は nil
    def regate_metadata(src)
      lines = src.lines
      open_idx, close_idx, cond, has_else = parse(lines)
      return nil if open_idx.nil? || close_idx.nil? || has_else || cond.nil?
      content = lines[(open_idx + 1)...close_idx] || raise
      i = 0
      i += 1 while content[i] && content[i] =~ BLANK_RE
      meta_start = i
      meta_end = nil
      j = meta_start
      while content[j]
        case content[j]
        when /\A(?:require|sublibrary|category)\s+\S/ then meta_end = j + 1
        when BLANK_RE then nil
        else break
        end
        j += 1
      end
      return nil unless meta_end
      rest = content[meta_end..] || raise
      rest.shift while rest.first && rest.first =~ BLANK_RE
      return nil if rest.empty?
      gate_line = lines[open_idx]
      # 種別（category/require/sublibrary）ごとに独立ブロックへ分ける
      # （メタデータ収集器の「#@ ブロックは単一種のみ」の制約に合わせる）
      runs = [] #: Array[[String?, Array[String]]]
      (content[meta_start...meta_end] || raise).each do |l|
        next if l =~ BLANK_RE
        kind = l[/\A(category|require|sublibrary)/, 1]
        if runs.last && runs.last[0] == kind
          runs.last[1] << l
        else
          runs << [kind, [l]]
        end
      end
      meta_blocks = runs.flat_map { |_, ls| [gate_line] + ls + ["\#@end\n", "\n"] }
      ((lines[0...open_idx] || raise) +
        meta_blocks +
        [gate_line] + rest + ["\#@end\n"] +
        (lines[(close_idx + 1)..] || raise)).join
    end

    # スコープの下で解除できる全体ゲートなら [解除後の src, front matter に
    # 書く gate（{} は不要の意）] を返す。据え置きなら nil
    def unwrap_for_scope(src, scope)
      lines = src.lines
      open_idx, close_idx, cond, has_else = parse(lines)
      return nil if open_idx.nil? || close_idx.nil? || has_else || cond.nil?

      gate =
        case cond.kind
        when :if
          return nil unless provably_true_if?(cond.version, scope)
          {} #: IncludeGraph::gate
        else
          scoped = scope.gate([cond])
          return nil unless scoped   # スコープ外 → 据え置き
          scoped
        end

      body = (lines[0...open_idx] || raise) + (lines[(open_idx + 1)...close_idx] || raise) + (lines[(close_idx + 1)..] || raise)
      body.shift while body.first && body.first =~ BLANK_RE
      [body.join, gate]
    end

    # [開き行 idx, 閉じ行 idx, Condition, トップレベル #@else の有無] を返す。
    # 全体ゲートでなければ open_idx が nil
    def parse(lines)
      open_idx = lines.index { |l| l !~ BLANK_RE }
      return [nil] unless open_idx && lines[open_idx] =~ GATE_OPEN_RE
      cond = IncludeGraph::Condition.new(($1 || raise).to_sym, ($2 || raise).strip)

      nest = 0
      has_else = false
      close_idx = nil #: Integer?
      (open_idx...lines.length).each do |i|
        case lines[i]
        when BLOCK_OPEN_RE then nest += 1
        when /\A\#@else\b/ then has_else = true if nest == 1
        when /\A\#@end\b/
          nest -= 1
          if nest.zero?
            close_idx = i
            break
          end
        end
      end
      return [nil] if close_idx.nil?
      # 閉じ行の後に非空行があれば全体ゲートではない
      return [nil] if (lines[(close_idx + 1)..] || raise).any? { |l| l !~ BLANK_RE }
      [open_idx, close_idx, cond, has_else]
    end

    def provably_true_if?(condition, scope)
      condition =~ VERSION_GE_RE && Gem::Version.new($1) <= scope.lo
    end
  end
end
