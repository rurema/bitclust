# frozen_string_literal: true

require 'yaml'

module BitClust
  class MarkdownToRRD
    def self.convert(markdown)
      new(markdown).convert
    end

    def initialize(markdown)
      @src = markdown
    end

    def convert
      @lines = @src.lines
      @out = []
      @index = 0
      @front_matter = {}

      parse_front_matter
      process_body
      @out.join
    end

    private

    def parse_front_matter
      return unless @index < @lines.length && @lines[@index] =~ /\A---\s*$/
      advance  # skip opening ---
      yaml_lines = []
      while @index < @lines.length
        line = current_line
        if line =~ /\A---\s*$/
          advance  # skip closing ---
          break
        end
        yaml_lines << line
        advance
      end
      parsed = YAML.safe_load(yaml_lines.join)
      @front_matter = parsed.is_a?(Hash) ? parsed : {}
      emit_library_metadata
      prepare_class_metadata
      # Skip blank lines after front matter
      advance while @index < @lines.length && current_line =~ /\A\s*\n?\z/
    end

    def emit_library_metadata
      if cat = @front_matter['category']
        @out << "category #{cat}\n\n"
      end
      if reqs = @front_matter['require']
        Array(reqs).each { |r| @out << "require #{r}\n" }
        @out << "\n"
      end
      if subs = @front_matter['sublibrary']
        Array(subs).each { |s| @out << "sublibrary #{s}\n" }
        @out << "\n"
      end
    end

    def prepare_class_metadata
      # include/extend/alias はパススルー（front matter にしない）
    end

    def process_body
      while @index < @lines.length
        line = current_line
        case line
        when /\A```/
          convert_code_block(line)
        when /\A### module_function def /
          convert_module_function_signature(line)
        when /\A### def /
          convert_method_signature(line)
        when /\A### const /
          convert_const_signature(line)
        when /\A### gvar /
          convert_gvar_signature(line)
        when /\A### /
          convert_h3_heading(line)
        when /\A#### /
          convert_h4_heading(line)
        when /\A- \*\*(param|return|raise)\*\*/
          convert_metadata(line, $1)
        when /\A- \*\*SEE\*\*/
          convert_see_list_upper(line)
        when /\A- \*\*see\*\*/
          convert_see_list(line)
        when /\A\*\*SEE\*\*/
          convert_see(line)
        when /\A@see /
          convert_see_passthrough(line)
        when /\A## /
          convert_h2(line)
        when /\A- \*\*(?!param\b|return\b|raise\b|see\b)(.+?)\*\*:/
          convert_dlist_colon_item(line)
        when /\A- \*\*(?!param\b|return\b|raise\b|see\b)(\w+)\*\* -- /
          convert_dlist_item(line)
        when /\A\*\*(\d+)\.\*\*\s/
          convert_bold_number(line)
        when /\A(\s*)- /
          convert_list_item(line, $1)
        when /\A(\s{0,3})(\d+)\.\s/
          convert_ordered_list_item(line, $2.to_i, $1)
        when /\A:\s/
          convert_dlist_passthrough(line)
        when /\A {4,}/
          convert_indented_code(line)
        when /\A\#@/
          raw_passthrough(line)
        when /\A# /
          convert_h1(line)
        else
          passthrough(line)
        end
      end
    end

    def convert_code_block(line)
      # バッククォートの個数を取得
      line =~ /\A(`{3,})/
      fence = $1
      fence_len = fence.length

      # 4個以上のバッククォート（言語指定なし）→ インデントコードに復元
      if fence_len > 3 && line =~ /\A`{4,}\s*$/
        indent = ' ' * (fence_len - 3)
        advance
        while @index < @lines.length
          l = current_line
          if l =~ /\A`{#{fence_len}}\s*$/
            advance
            return
          end
          if l =~ /\A\s*$/
            @out << l
          else
            @out << indent + l
          end
          advance
        end
        return
      end

      title = nil
      lang = nil
      fence_len = 3
      if line =~ /\A(`{3,})(\w*)/
        fence_len = $1.length
        lang = $2.empty? ? nil : $2
      end
      if line =~ /title="((?:[^"\\]|\\.)*)"/
        title = $1.gsub(/\\(["\\])/, '\1')
      end

      if lang == 'ruby'
        # Ruby → #@samplecode
        samplecode = '#@samplecode'
        samplecode_end = '#@end'
        @out << (title && !title.empty? ? "#{samplecode} #{title}\n" : "#{samplecode}\n")
      else
        # Other language or unspecified → //emlist
        parts = ['//emlist']
        if title && !title.empty?
          parts << "[#{title}]"
          parts << "[#{lang}]" if lang
        elsif lang
          parts << '[]'
          parts << "[#{lang}]"
        end
        parts << "{"
        @out << parts.join + "\n"
      end
      advance
      while @index < @lines.length
        line = current_line
        if line =~ /\A`{#{fence_len}}\s*\n?\z/
          if lang == 'ruby'
            @out << "#{samplecode_end}\n"
          else
            @out << "//}\n"
          end
          advance
          return
        end
        # No cross-reference conversion inside code blocks
        @out << line
        advance
      end
    end

    def convert_method_signature(line)
      @out << line.sub(/\A### def /, '--- ')
      advance
    end

    def convert_module_function_signature(line)
      @out << line.sub(/\A### module_function def /, '--- ')
      advance
    end

    def convert_const_signature(line)
      @out << line.sub(/\A### const /, '--- ')
      advance
    end

    def convert_gvar_signature(line)
      @out << line.sub(/\A### gvar /, '--- ')
      advance
    end

    def convert_metadata(line, kind)
      case kind
      when 'param'
        if (m = /\A- \*\*param\*\*(\s+)`([^`]+)` --(.*)$/.match(line))
          @out << convert_inline_refs("@param#{m[1]}#{m[2]}#{m[3]}\n")
        end
      when 'raise'
        if (m = /\A- \*\*raise\*\*(\s+)`([^`]+)` --(.*)$/.match(line))
          @out << convert_inline_refs("@raise#{m[1]}#{m[2]}#{m[3]}\n")
        end
      when 'return'
        if (m = /\A- \*\*return\*\*(?: `[^`]+`)? --(.*)$/.match(line))
          @out << convert_inline_refs("@return#{m[1]}\n")
        end
      end
      advance
      collect_md_continuation_lines
    end

    def collect_md_continuation_lines
      nest = 0
      while @index < @lines.length
        line = current_line
        if line =~ /\A\#@(?:since|until|if)\b/
          nest += 1
          raw_passthrough(line)
        elsif line =~ /\A\#@else/
          raw_passthrough(line)
        elsif line =~ /\A\#@end/ && nest > 0
          nest -= 1
          raw_passthrough(line)
        elsif line =~ /\A\s+\S/ && line !~ /\A- / && line !~ /\A\*\*/ && line !~ /\A```/
          @out << strip_code_spans(convert_inline_refs(line))
          advance
        else
          break
        end
      end
    end

    def convert_see(line)
      # **SEE** → @see、[→[[ 置換、区切りは保持
      rest = line.sub(/\A\*\*SEE\*\*(\s*)/, '').chomp
      space = $1
      @out << "@see#{space}#{convert_inline_refs(rest)}\n"
      advance
    end

    def convert_see_list_upper(line)
      # - **SEE** [ref] → @see [[ref]]、区切り保持
      rest = line.sub(/\A- \*\*SEE\*\*(\s*)/, '').chomp
      space = $1
      @out << "@see#{space}#{convert_inline_refs(rest)}\n"
      advance
      collect_md_continuation_lines
    end

    def convert_see_list(line)
      # - **see** [display][type:ref] → @see [[type:ref]]
      rest = line.sub(/\A- \*\*see\*\*\s*/, '').chomp
      @out << "@see #{convert_inline_refs(rest)}\n"
      advance
    end

    def convert_see_passthrough(line)
      # @see [m:A], [m:B] → @see [[m:A]], [[m:B]] (区切り保持)
      rest = line.sub(/\A@see\s+/, '').chomp
      @out << "@see #{convert_inline_refs(rest)}\n"
      advance
    end

    def convert_heading_with_anchor(line, prefix)
      if line =~ /\{#([^}]+)\}\s*$/
        anchor = $1
        text = line.sub(/\A#+\s+/, '').sub(/\s*\{#[^}]+\}\s*$/, '')
        @out << "#{prefix}[a:#{anchor}] #{text}\n"
      else
        text = line.sub(/\A#+\s+/, '').chomp
        @out << "#{prefix} #{text}\n"
      end
      advance
    end

    def convert_h3_heading(line)
      convert_heading_with_anchor(line, '===')
    end

    def convert_h4_heading(line)
      convert_heading_with_anchor(line, '====')
    end

    def strip_code_span(text)
      text.sub(/\A`(.+)`\z/, '\\1')
    end

    def convert_dlist_colon_item(line)
      # - **`term`**: description → : term\n  description
      # - **term**:\n  line1\n  line2 → : term\n  line1\n  line2
      if line =~ /\A- \*\*(.+?)\*\*: (.+)$/
        @out << ": #{strip_code_span(convert_inline_refs($1))}\n  #{convert_inline_refs($2)}\n"
        advance
      elsif line =~ /\A- \*\*(.+?)\*\*:\s*$/
        @out << ": #{strip_code_span(convert_inline_refs($1))}\n"
        advance
        # 継続行を収集（空行を挟む場合も含む）
        while @index < @lines.length
          l = current_line
          if l =~ /\A\s+\S/
            @out << convert_inline_refs(l)
            advance
          elsif l =~ /\A\s*$/ && @index + 1 < @lines.length && @lines[@index + 1] =~ /\A\s+\S/ && @lines[@index + 1] !~ /\A- \*\*/
            @out << l
            advance
          else
            break
          end
        end
      else
        advance
      end
    end

    def convert_dlist_item(line)
      if line =~ /\A- \*\*(.+?)\*\* -- (.*)$/
        @out << ": #{$1}\n  #{convert_inline_refs($2)}\n"
      end
      advance
    end

    def convert_bold_number(line)
      # **N.** text → N. text (太字番号テキスト → RRD のテキスト)
      @out << convert_inline_refs(line.sub(/\A\*\*(\d+\.)\*\*\s/, '\\1 '))
      advance
    end

    def convert_ordered_list_item(line, num, indent)
      rrd_indent = indent.empty? ? ' ' : indent
      @out << convert_inline_refs(line.sub(/\A\s*\d+\. /, "#{rrd_indent}(#{num}) "))
      advance
    end

    def convert_list_item(line, indent)
      rrd_indent = indent.empty? ? ' ' : indent
      line =~ /\A\s*-(\s+)/
      content_indent = (indent.empty? ? 1 : indent.length) + 1 + $1.length
      @out << convert_inline_refs(line.sub(/\A\s*-(\s+)/, "#{rrd_indent}*\\1"))
      advance
      # 継続行を収集（content_indent 以上、空行・リスト項目・#@ で停止）
      while @index < @lines.length
        l = current_line
        if l =~ /\A\#@/
          raw_passthrough(l)
        elsif l =~ /\A\s*$/
          break
        elsif l =~ /\A(\s+)\S/ && $1.length >= content_indent && l !~ /\A\s*-\s/ && l !~ /\A\s*\d+\.\s/
          @out << convert_inline_refs(l)
          advance
        else
          break
        end
      end
    end

    def convert_dlist_passthrough(line)
      # `: term` + 説明行をそのままパススルー
      passthrough(line)
      while @index < @lines.length
        l = current_line
        if l =~ /\A\s+\S/
          passthrough(l)
        else
          break
        end
      end
    end

    def convert_indented_code(line)
      # C1: インデント -3 して出力
      # 最初の行が実際にコードでなければパススルー
      unless current_line =~ /\A( {4,})\S/
        passthrough(current_line)
        return
      end
      while @index < @lines.length
        line = current_line
        if line =~ /\A( {4,})\S/
          n = $1.length
          deindent = [n - 3, 1].max
          @out << (' ' * deindent) + line[n..]
          advance
        elsif line =~ /\A\s*$/
          if @index + 1 < @lines.length && @lines[@index + 1] =~ /\A {4,}\S/
            @out << line
            advance
          else
            break
          end
        else
          break
        end
      end
    end

    def convert_h2(line)
      @out << line.sub(/\A## /, '== ')
      advance
    end

    def convert_h1(line)
      @out << line.sub(/\A# /, '= ')
      advance
    end

    def raw_passthrough(line)
      @out << line
      advance
    end

    def passthrough(line)
      @out << strip_code_spans(convert_inline_refs(line))
      advance
    end

    # テキスト行の `__WORD__` をコードスパンから解除
    def strip_code_spans(text)
      text.gsub(/`(__\w+__)`/, '\\1')
    end

    # Markdown のブラケットリンク: エスケープされた \[ \] を含むパターン
    def convert_inline_refs(line)
      # bare [type:target] → [[type:target]] (手動パースで \[\] 対応)
      convert_bare_refs(line)
    end

    def convert_bare_refs(line)
      result = +""
      i = 0
      while i < line.length
        if line[i] == '[' && (i == 0 || line[i-1] != '[') && (i + 1 >= line.length || line[i+1] != '[')
          # [ の開始を検出（[[ は除外）— エスケープを考慮して ] を探す
          j = find_closing_bracket(line, i + 1)
          if j
            inner = line[i+1...j]
            if inner =~ /\A[a-zA-Z][a-zA-Z-]*:/
              result << convert_md_ref_to_rrd(inner)
              i = j + 1
              next
            end
          end
        end
        result << line[i]
        i += 1
      end
      result
    end

    def find_closing_bracket(line, start)
      j = start
      while j < line.length
        if line[j] == '\\' && j + 1 < line.length && (line[j+1] == '[' || line[j+1] == ']' || line[j+1] == '\\')
          j += 2
        elsif line[j] == ']'
          return j
        else
          j += 1
        end
      end
      nil
    end

    def convert_md_ref_to_rrd(ref)
      # Markdown の \[ \] \\ → RD の [ ] \
      unescaped = ref.gsub('\\[', '[').gsub('\\]', ']').gsub('\\\\', '\\')
      # ? → .# (モジュール関数参照)
      unescaped = unescaped.sub(/\?\./, '.#')
      # RD で [] で終わるメソッド名のみ末尾スペースが必要 ([[m:Hash#[] ]])
      # []= のように [] の後に文字がある場合はスペース不要 ([[m:String#[]=]])
      if unescaped.end_with?('[]')
        "[[#{unescaped} ]]"
      else
        "[[#{unescaped}]]"
      end
    end

    def current_line
      @lines[@index]
    end

    def advance
      @index += 1
    end
  end
end
