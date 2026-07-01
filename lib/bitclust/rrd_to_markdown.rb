# frozen_string_literal: true

module BitClust
  class RRDToMarkdown
    def self.convert(rrd)
      new(rrd).convert
    end

    def initialize(rrd)
      @src = rrd
    end

    def convert
      @lines = @src.lines
      @out = []
      @index = 0
      @front_matter = {}
      @current_section = nil

      collect_library_metadata
      process_body
      emit_front_matter + @out.join
    end

    private

    SAMPLECODE_RE = /\A\#@samplecode/

    def collect_library_metadata
      # 先読みで #@ がメタデータ行の間に存在するか確認
      has_directive_in_metadata = false
      @lines[@index..].each do |l|
        case l
        when /\A(category|require|sublibrary)\s/, /\A\s*$/
          next
        when /\A\#@/
          has_directive_in_metadata = true
          break
        else
          break
        end
      end
      # #@ が混在する場合は front matter 移動をスキップ
      return if has_directive_in_metadata

      while @index < @lines.length
        line = current_line
        case line
        when /\Acategory\s+(.*)/
          @front_matter['category'] = $1.strip
          advance
        when /\Arequire\s+(.*)/
          (@front_matter['require'] ||= []) << $1.strip
          advance
        when /\Asublibrary\s+(.*)/
          (@front_matter['sublibrary'] ||= []) << $1.strip
          advance
        when /\A\s*$/
          advance
        else
          break
        end
      end
    end

    def emit_front_matter
      return '' if @front_matter.empty?
      lines = ["---\n"]
      if v = @front_matter['category']
        lines << "category: #{v}\n"
      end
      %w[require sublibrary].each do |key|
        if arr = @front_matter[key]
          lines << "#{key}:\n"
          arr.each { |item| lines << "  - #{item}\n" }
        end
      end
      lines << "---\n"
      lines.join
    end

    def process_body
      while @index < @lines.length
        line = current_line
        case line
        when SAMPLECODE_RE
          convert_samplecode(line)
        when /\A\/\/emlist/
          convert_emlist(line)
        when /\A--- /
          convert_signature(line)
        when /\A===+\[a:([^\]]+)\]\s+(.*)/
          convert_anchored_heading(line, $1, $2)
        when /\A====\s+(.*)/
          convert_h4(line, $1)
        when /\A===\s+(.*)/
          convert_h3(line, $1)
        when /\A@param\s/
          convert_param(line)
        when /\A@raise\s/
          convert_raise(line)
        when /\A@return\s/
          convert_return(line)
        when /\A@see\s/
          convert_see(line)
        when /\A(\s+)\*\s/
          convert_ulist_item(line)
        when /\A(\s+)\(\d+\)\s/
          convert_olist_item(line)
        when /\A:\s+(.*)/
          convert_dlist_item(line, $1)
        when /\A\#@/
          raw_passthrough(line)
        when /\A== /
          convert_h2(line)
        when /\A= /
          convert_h1(line)
        when /\A(\s+)\S/
          convert_indented_code(line)
        when /\A(\d+)\.\s/
          convert_text_number(line)
        else
          passthrough(line)
        end
      end
    end

    def convert_emlist(line)
      # //emlist[caption][lang]{...//}
      caption = nil
      lang = nil
      if line =~ /\A\/\/emlist\[([^\]]*)\]\[(\w+)\]\{/
        caption = $1
        lang = $2
      elsif line =~ /\A\/\/emlist\[([^\]]*)\]\{/
        caption = $1
      elsif line =~ /\A\/\/emlist\{/
        # no caption, no lang
      end
      parts = []
      parts << "```"
      parts << (lang || "")
      if caption && !caption.empty?
        escaped_caption = caption.gsub('\\', '\\\\\\\\').gsub('"', '\\"')
        parts << " title=\"#{escaped_caption}\""
      end
      @out << parts.join + "\n"
      advance
      while @index < @lines.length
        line = current_line
        if line =~ /\A\/\/\}\s*$/
          @out << "```\n"
          advance
          return
        end
        @out << line
        advance
      end
    end

    DIRECTIVE_NEST_RE = /\A\#@(?:since|until|if)\b/
    DIRECTIVE_END_RE = /\A\#@end\s*$/

    def convert_samplecode(line)
      label = line.sub(SAMPLECODE_RE, '').strip
      if label.empty?
        @out << "```ruby\n"
      else
        escaped_label = label.gsub('\\', '\\\\\\\\').gsub('"', '\\"')
        @out << "```ruby title=\"#{escaped_label}\"\n"
      end
      advance
      nest = 0
      while @index < @lines.length
        line = current_line
        if line =~ DIRECTIVE_NEST_RE
          nest += 1
          @out << line
          advance
        elsif line =~ DIRECTIVE_END_RE
          if nest > 0
            nest -= 1
            @out << line
            advance
          else
            @out << "```\n"
            advance
            return
          end
        else
          @out << line
          advance
        end
      end
    end

    def convert_signature(line)
      sig = line.sub(/\A--- /, '').chomp
      # B1: 空白を保持（正規化しない）

      if @current_section == :module_function
        @out << "### module_function def #{sig}\n"
      elsif sig =~ /\A\$/ && sig !~ /[({]/
        @out << "### gvar #{sig}\n"
      elsif sig =~ /\A[A-Z]/ && sig !~ /[({]/
        @out << "### const #{sig}\n"
      else
        @out << "### def #{sig}\n"
      end
      advance
    end

    def convert_param(line)
      l = line.chomp
      if l =~ /\A@param(\s+)(\S+)(\s+)(.*)\z/
        @out << "- **param**#{$1}`#{$2}` --#{$3}#{convert_inline_refs($4)}\n"
      elsif l =~ /\A@param(\s+)(\S+)\z/
        @out << "- **param**#{$1}`#{$2}` --\n"
      end
      advance
      collect_continuation_lines
    end

    def convert_raise(line)
      l = line.chomp
      if l =~ /\A@raise(\s+)(\S+)(\s+)(.*)\z/
        @out << "- **raise**#{$1}`#{$2}` --#{$3}#{convert_inline_refs($4)}\n"
      elsif l =~ /\A@raise(\s+)(\S+)\z/
        @out << "- **raise**#{$1}`#{$2}` --\n"
      end
      advance
      collect_continuation_lines
    end

    def convert_return(line)
      # B2: @return 後のスペースを保持
      rest = line.sub(/\A@return/, '').chomp
      @out << "- **return** --#{convert_inline_refs(rest)}\n"
      advance
      collect_continuation_lines
    end

    def convert_see(line)
      # @see → - **SEE**、[[→[ 置換、区切りは保持
      rest = line.sub(/\A@see(\s+)/, '').chomp
      space = $1
      converted = convert_inline_refs(rest)
      @out << "- **SEE**#{space}#{converted}\n"
      advance
      collect_continuation_lines
    end

    def collect_continuation_lines
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
        elsif line =~ /\A\s+\S/ && line !~ /\A@/ && line !~ /\A---/ && line !~ /\A=/ && line !~ SAMPLECODE_RE
          @out << convert_inline_refs(line)
          advance
        else
          break
        end
      end
    end

    def convert_anchored_heading(line, anchor, text)
      prefix = line.start_with?('====') ? '####' : '###'
      @out << "#{prefix} #{text.strip} {##{anchor}}\n"
      advance
    end

    def convert_h3(line, text)
      @out << "### #{text.strip}\n"
      advance
    end

    def convert_h4(line, text)
      @out << "#### #{text.strip}\n"
      advance
    end

    def convert_ulist_item(line)
      # B4: 元のインデント幅と * 後のスペースを保持
      line =~ /\A(\s+)\*(\s+)(.*)/
      indent = $1
      space = $2
      text = $3
      content_indent = indent.length + 1 + space.length
      @out << "#{indent}-#{space}#{convert_inline_refs(text.chomp)}\n"
      advance
      # 継続行を収集（content_indent 以上のインデント、空行・リスト項目で停止）
      while @index < @lines.length
        l = current_line
        if l =~ /\A\#@/
          raw_passthrough(l)
        elsif l =~ /\A\s*$/
          break  # 空行でリスト継続終了
        elsif l =~ /\A(\s+)\S/ && $1.length >= content_indent && l !~ /\A\s+\*\s/ && l !~ /\A\s+\(\d+\)\s/
          @out << convert_inline_refs(l)
          advance
        else
          break
        end
      end
    end

    def convert_olist_item(line)
      # B4: 元のインデント幅を保持
      line =~ /\A(\s+)\((\d+)\)\s+(.*)/
      indent = $1
      num = $2
      text = $3
      @out << "#{indent}#{num}. #{convert_inline_refs(text.chomp)}\n"
      advance
    end

    def code_like_term?(term)
      term.length < 40 && term !~ /\p{Hiragana}|\p{Katakana}|\p{Han}/
    end

    def format_dlist_term(term)
      t = convert_inline_refs(term.chomp)
      if code_like_term?(t)
        "**`#{t}`**"
      else
        "**#{t}**"
      end
    end

    def convert_dlist_item(line, term)
      advance
      formatted = format_dlist_term(term)
      # 説明行を収集（空行を挟む場合も含む）
      desc_lines = []
      while @index < @lines.length
        l = current_line
        if l =~ /\A(\s+)\S/
          desc_lines << l
          advance
        elsif l =~ /\A\s*$/ && @index + 1 < @lines.length && @lines[@index + 1] =~ /\A\s+\S/ && @lines[@index + 1] !~ /\A\s+\*\s/
          # 空行の後にインデント行が続く場合（別の定義リストやリストでない）
          desc_lines << l
          advance
        else
          break
        end
      end
      if desc_lines.empty?
        @out << "- #{formatted}:\n"
      else
        @out << "- #{formatted}:\n"
        desc_lines.each { |l| @out << convert_inline_refs(l) }
      end
    end

    def convert_indented_code(line)
      # 行を収集してベースインデントを取得
      code_lines = []
      while @index < @lines.length
        line = current_line
        if line =~ /\A(\s+)\S/
          code_lines << line
          advance
        elsif line =~ /\A\s*$/
          if @index + 1 < @lines.length && @lines[@index + 1] =~ /\A\s+\S/
            code_lines << line
            advance
          else
            break
          end
        else
          break
        end
      end

      # ベースインデント（空行以外の最小インデント）を検出
      base_indent = code_lines
        .reject { |l| l =~ /\A\s*$/ }
        .map { |l| l =~ /\A(\s+)/; $1.length }
        .min || 1

      fence = '`' * (3 + base_indent)
      @out << "#{fence}\n"
      code_lines.each do |l|
        if l =~ /\A\s*$/
          @out << l
        else
          @out << l[base_indent..]  # ベースインデントを除去
        end
      end
      @out << "#{fence}\n"
    end

    def convert_h1(line)
      @out << line.sub(/\A= /, '# ')
      advance
      # include/extend/alias はパススルー（front matter にしない）
    end

    def convert_h2(line)
      @out << line.sub(/\A== /, '## ')
      # セクション追跡
      if line =~ /Module\s+Functions?/i
        @current_section = :module_function
      else
        @current_section = nil
      end
      advance
    end

    def convert_text_number(line)
      # RRD の "N. text" → MD の "**N.** text" (太字番号テキスト)
      converted = line.sub(/\A(\d+\.)\s/, '**\\1** ')
      @out << convert_inline_refs(converted)
      advance
    end

    def raw_passthrough(line)
      @out << line
      advance
    end

    def passthrough(line)
      @out << add_code_spans(convert_inline_refs(line))
      advance
    end

    # テキスト行の __WORD__ パターンをコードスパンに変換
    # ブラケットリンク [[type:...]] 内は除外
    def add_code_spans(text)
      # クロスリファレンス部分を保護して変換
      parts = text.split(/(\[\[[a-zA-Z][\w-]*:[^\]]*\]\])/)
      parts.map { |part|
        if part.start_with?('[[') && part.end_with?(']]')
          part
        else
          part.gsub(/(__\w+__)/, '`\\1`')
        end
      }.join
    end

    # BitClust::RDCompiler::BracketLink と同等の正規表現
    BRACKET_LINK = /\[\[[\w-]+?:[!-~]+?(?:\[\] )?\]\]/n

    def convert_inline_refs(text)
      text.b.gsub(BRACKET_LINK) do |match|
        inner = match[2..-3] # strip [[ and ]]
        # RD の "[] " (末尾スペース) → メソッド名の [] として扱う
        inner = inner.sub(/\[\] \z/, '[]')
        # .# → ? (モジュール関数参照)
        inner = inner.sub(/\.#/, '?.')
        # メソッド名内の [ ] をバックスラッシュエスケープ
        if inner =~ /\A([\w-]+:)(.*)/n
          prefix = $1
          target = $2
          target = target.gsub('\\', '\\\\\\\\').gsub('[', '\\[').gsub(']', '\\]')
          inner = prefix + target
        end
        "[#{inner}]"
      end.force_encoding(text.encoding)
    end

    def current_line
      @lines[@index]
    end

    def advance
      @index += 1
    end
  end
end
