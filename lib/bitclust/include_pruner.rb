# frozen_string_literal: true

module BitClust
  # RRD テキストから指定 target の #@include 行を除去する純変換（rd→rd）。
  #
  # 新パイプラインでは grouping include（エンティティの取り込み）は
  # glob + front matter による発見に置き換わるため、ライブラリ概要ファイル等から
  # 除去する（二重取り込み防止）。fragment include（共有断片の transclusion）は
  # target に含めなければそのまま残る。
  #
  # 除去に伴う後始末:
  # - 除去で空になった版ゲートブロック（#@since/#@until/#@if ... #@end、
  #   #@else の両枝が空の場合を含む）はブロックごと除去する
  # - 除去痕の前後が空行同士なら1つに畳む。ファイル先頭に残る空行は削る
  #   （末尾の空行は保持する: メタデータ領域再生成の空行仕様と整合させるため）
  # - もともと空だったブロックや、target を含まない入力はバイト単位で変更しない
  module IncludePruner
    INCLUDE_RE = /\A\#@include\s*\((.*?)\)/
    GATE_OPEN_RE = /\A\#@(?:since|until|if)\b/
    CODE_OPEN_RE = /\A\#@samplecode\b/
    ELSE_RE = /\A\#@else\b/
    END_RE = /\A\#@end\b/
    BLANK_RE = /\A\s*\z/

    # ブロック除去・空行畳み込みの位置を示す番兵
    REMOVED = Object.new.freeze
    private_constant :REMOVED

    Block = Struct.new(:open, :body, :else_line, :else_body, :end_line, :gate)
    private_constant :Block

    module_function

    def prune(src, targets)
      return src if targets.empty?
      lookup = {} #: Hash[String?, bool]
      targets.each { |t| lookup[t] = true }

      lines = src.lines
      nodes = catch(:unbalanced) { parse(lines) }
      return src if nodes.nil?

      stream = [] #: stream
      changed = emit(nodes, lookup, stream)
      return src unless changed
      tidy(stream).join
    end

    # lines をブロック構造にパースする。対応の取れないファイルは throw で nil を返す
    def parse(lines)
      nodes, i = parse_nodes(lines, 0)
      throw :unbalanced, nil if i < lines.length   # トップレベルに #@else / #@end
      nodes
    end

    def parse_nodes(lines, i)
      nodes = [] #: Array[node]
      while i < lines.length
        line = lines[i]
        if line =~ ELSE_RE || line =~ END_RE
          return [nodes, i]
        elsif line =~ GATE_OPEN_RE || line =~ CODE_OPEN_RE
          gate = line !~ CODE_OPEN_RE
          body, j = parse_nodes(lines, i + 1)
          else_line = nil
          else_body = [] #: Array[node]
          if j < lines.length && lines[j] =~ ELSE_RE
            else_line = lines[j]
            else_body, j = parse_nodes(lines, j + 1)
          end
          throw :unbalanced, nil unless j < lines.length && lines[j] =~ END_RE
          nodes << Block.new(line, body, else_line, else_body, lines[j], gate)
          i = j + 1
        else
          nodes << line
          i += 1
        end
      end
      [nodes, i]
    end

    # nodes を stream（行と REMOVED 番兵の列）へ展開し、変更の有無を返す
    def emit(nodes, lookup, stream)
      changed = false
      nodes.each do |node|
        if node.is_a?(Block)
          changed |= emit_block(node, lookup, stream)
        elsif node =~ INCLUDE_RE && lookup[$1]
          stream << REMOVED
          changed = true
        else
          stream << node
        end
      end
      changed
    end

    def emit_block(block, lookup, stream)
      body = [] #: stream
      body_changed = emit(block.body, lookup, body)
      else_body = [] #: stream
      else_changed = block.else_line ? emit(block.else_body, lookup, else_body) : false
      changed = body_changed || else_changed

      if block.gate && changed && blank_only?(body) && blank_only?(else_body)
        stream << REMOVED
        return true
      end

      stream << block.open
      stream.concat(body)
      if block.else_line
        stream << block.else_line
        stream.concat(else_body)
      end
      stream << block.end_line
      changed
    end

    def blank_only?(stream)
      stream.all? { |item| item.equal?(REMOVED) || item =~ BLANK_RE }
    end

    # REMOVED 番兵を取り除きつつ、除去痕の前後が空行同士なら1つに畳み、
    # 先頭に残った空行を削る
    def tidy(stream)
      result = [] #: Array[String]
      pending = false
      stream.each do |item|
        if item.equal?(REMOVED)
          pending = true
          next
        end
        if pending && item =~ BLANK_RE && (result.empty? || result.last =~ BLANK_RE)
          pending = false
          next
        end
        pending = false
        result << item
      end
      result
    end
  end
end
