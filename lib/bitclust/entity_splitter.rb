# frozen_string_literal: true

require 'bitclust/include_graph'
require 'bitclust/whole_file_gate'

module BitClust
  # マルチエンティティ RRD のエンティティ単位分割（O3）。
  #
  # 「ヘッダ関係（include/extend/alias）を持つエンティティは自分のファイルを持ち、
  # 関係は front matter に一元化する」ため、関係を持つマルチエンティティファイルを
  # エンティティ単位のセグメントへ分割する。関係を持たない束ね（Errno 族等）は
  # 分割しない（判断はオーケストレータが行う。ここは純テキスト変換）。
  #
  # 分割の前処理として、スコープ定数（スコープ内で常に真/偽）の版ゲートのうち
  # エンティティ H1 を包むものを解決する。版で改名されたエンティティ
  # （thread/Mutex, Net::HTTPURITooLong 等の #@since/#@else H1 ペア）が
  # スコープ内の単一 H1 に収束する（旧名は活き枝の alias 行として残っている）。
  module EntitySplitter
    H1_RE = /\A=(?!=)\s*(?:class|module|object|reopen|redefine)\s+(\S+)/
    GATE_OPEN_RE = /\A\#@(since|until|if)\s*(.*)$/
    BLOCK_OPEN_RE = /\A\#@(?:since|until|if|samplecode)\b/
    BLANK_RE = /\A\s*\z/

    module_function

    # スコープ定数（スコープ内で常に真/偽）な版ゲートのうち、エンティティ H1 を
    # 含むブロックを解決する。活きている枝の内容（再帰的に解決）を残し、
    # ゲート行と死んだ枝を落とす。スコープ内で真偽が変わるゲートと、
    # H1 を含まないゲート（散文の版分岐・gated relations）は触らない。
    def resolve_header_gates(src, scope)
      lines = src.lines
      out = [] #: Array[String]
      i = 0
      while i < lines.length
        line = lines[i]
        truth = constant_truth(line, scope)
        if !truth.nil? && (block = parse_block(lines, i)) &&
           contains_entity_h1?(block[:body] + block[:else_body])
          active = truth ? block[:body] : block[:else_body]
          resolved = resolve_header_gates(active.join, scope).lines
          if resolved.empty? && out.last =~ BLANK_RE && lines[block[:next]] =~ BLANK_RE
            i = block[:next] + 1   # ブロックごと消えた場合は後続の空行を1つ畳む
          else
            i = block[:next]
          end
          out.concat(resolved)
        else
          out << line
          i += 1
        end
      end
      out.join
    end

    # ゲート行のスコープ定数評価: 常真なら true、常偽なら false、
    # 定数でない／ゲートでないなら nil。
    # #@if は「version >= "X"（X <= 下限）」形のみ常真と証明できる
    def constant_truth(line, scope)
      cond = gate_condition(line)
      return nil unless cond
      if cond.kind == :if
        WholeFileGate.provably_true_if?(cond.version, scope) ? true : nil
      elsif scope.always?(cond)
        true
      elsif scope.never?(cond)
        false
      end
    end

    # samplecode の内容を除いて、エンティティ H1 行を含むか
    def contains_entity_h1?(lines)
      code = 0
      lines.each do |l|
        case l
        when /\A\#@samplecode\b/ then code += 1
        when /\A\#@end\b/ then code -= 1 if code > 0
        when H1_RE then return true if code.zero?
        end
      end
      false
    end

    # エンティティ単位のセグメント列 [[エンティティ名, テキスト], ...] を返す。
    # 境界は深さ0の H1 行、または最初の内容行が H1 の版ゲートブロック
    # （スコープ内ゲート付きエンティティ。ブロック全体が1セグメント）。
    # 先頭に H1 以外の内容がある場合（ライブラリ概要部）は name=nil の
    # ベースセグメントとして返す。連結すると入力に一致する。
    def segments(src)
      lines = src.lines
      # [行index, エンティティ名, ゲート付きか]
      boundaries = [] #: Array[[Integer, String?, bool]]
      depth = 0
      lines.each_with_index do |line, i|
        case line
        when BLOCK_OPEN_RE
          if depth.zero? && line =~ /\A\#@(?:since|until|if)\b/ &&
             (name = first_h1_name(lines, i + 1))
            boundaries << [i, name, true]
          end
          depth += 1
        when /\A\#@end\b/
          depth -= 1
        when H1_RE
          boundaries << [i, $1, false] if depth.zero?
        end
      end
      # ゲート付き H1 境界は、ゲートがセグメント全体を包む場合のみ分割境界にする。
      # H1 と見出しだけがゲートされ内容がゲートの外にある形（syslog の旧構造）を
      # 単独ファイル化すると、ゲートが偽の版で自立パースできない
      # （旧世界では直前エンティティの内容として付く）ため、直前セグメントに残す
      boundaries = boundaries.each_with_index.select { |(start, _, gated), idx|
        next true unless gated
        stop = idx + 1 < boundaries.length ? boundaries[idx + 1][0] : lines.length
        gate_wraps_segment?(lines, start, stop)
      }.map { |(start, name, _), _| [start, name] } #: Array[[Integer, String?]]
      return nil if boundaries.empty?
      if (lines[0...(boundaries.first || raise)[0]] || raise).all? { |l| l =~ BLANK_RE }
        boundaries[0] = [0, boundaries[0][1]]   # 先頭の空行は最初のセグメントへ
      else
        boundaries.unshift([0, nil])            # ライブラリ概要部（ベースセグメント）
      end

      boundaries.each_with_index.map do |(start, name), idx|
        stop = idx + 1 < boundaries.length ? boundaries[idx + 1][0] : lines.length
        [name, (lines[start...stop] || raise).join]
      end
    end

    # start のゲート開き行に対応する #@end がセグメント終端（末尾の空行は許容）に
    # あるか。ゲートがセグメント全体を包むときのみ真
    def gate_wraps_segment?(lines, start, stop)
      depth = 0
      close = nil #: Integer?
      (start...stop).each do |i|
        case lines[i]
        when BLOCK_OPEN_RE then depth += 1
        when /\A\#@end\b/
          depth -= 1
          if depth.zero?
            close = i
            break
          end
        end
      end
      return false unless close
      (lines[(close + 1)...stop] || raise).all? { |l| l =~ BLANK_RE }
    end

    # エンティティ名 → 出力ファイル名（拡張子なし）。既存の命名規約に合わせ :: → __
    def entity_filename(name)
      name.gsub('::', '__')
    end

    # いずれかのエンティティの H1 直後のヘッダ領域（関係行・#@・空行が続く範囲）に
    # include/extend/alias があるか。本文中やコード例の同名行は数えない
    def header_relations?(src)
      in_header = false
      src.each_line do |line|
        if line =~ H1_RE
          in_header = true
        elsif in_header
          case line
          when /\A(?:include|extend|alias)\s+\S/ then return true
          when /\A\#@/, BLANK_RE then nil
          else in_header = false
          end
        end
      end
      false
    end

    def gate_condition(line)
      return nil unless line =~ GATE_OPEN_RE
      # Preprocessor は #@since "1.8.5" のクォート形式も受理する
      IncludeGraph::Condition.new(($1 || raise).to_sym, ($2 || raise).strip.delete_prefix('"').delete_suffix('"'))
    end

    # i のゲート開始行から対応を取り、{body:, else_body:, next:} を返す。
    # body/else_body は枝の行列、next は #@end の次の行 index。対応が取れなければ nil
    def parse_block(lines, i)
      depth = 0
      body = [] #: Array[String]
      else_body = [] #: Array[String]
      current = body
      j = i
      while j < lines.length
        line = lines[j]
        case line
        when BLOCK_OPEN_RE
          depth += 1
          current << line unless j == i
        when /\A\#@else\b/
          if depth == 1
            current = else_body
          else
            current << line
          end
        when /\A\#@end\b/
          depth -= 1
          return { body: body, else_body: else_body, next: j + 1 } if depth.zero?
          current << line
        else
          current << line
        end
        j += 1
      end
      nil
    end

    def first_content_is_h1?(branch_lines)
      first = branch_lines.find { |l| l !~ BLANK_RE }
      first =~ H1_RE ? true : false
    end

    # i 以降の最初の非空行が H1 ならその名前を返す
    def first_h1_name(lines, i)
      first = (lines[i..] || raise).find { |l| l !~ BLANK_RE }
      first =~ H1_RE ? $1 : nil
    end
  end
end
