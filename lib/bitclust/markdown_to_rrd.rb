# frozen_string_literal: true

require 'yaml'

module BitClust
  class MarkdownToRRD
    def self.convert(markdown, capi: false)
      new(markdown, capi: capi).convert
    end

    # md テキスト断片のインライン記法を rd 形式へ復元する
    # （[type:target] → [[type:target]]、\[ エスケープ解除）。
    # MDCompiler がテキストノードの処理を共有するための公開 API
    def self.restore_inline(text)
      new('').send(:convert_bare_refs, text)
    end

    # md テキストを旧経路と同じ表示形（rd のインライン形式）へ戻す:
    # `__X__` 自動スパン解除、`token` → `token'（GNU 風引用）、
    # 行頭 **N.** → N.、\`/\[ の解除と [x:y] → [[x:y]]。
    # MDCompiler の M1 等価描画と、entry#description（meta description 等の
    # コンパイラ非経由テキスト）が共用する
    def self.restore_text(text)
      restore_inline(
        text.gsub(/`(__\w+__)`/, '\1')
            .gsub(/(?<!\\)`([^`'\s]+)`/) { "`#{$1}'" }
            .gsub(/^\*\*(\d+\.)\*\* /, '\1 ')
      )
    end

    # capi: C API リファレンスモード。### は見出しではなくシグネチャ
    # 「--- <C sig>」へ復元する（capi に本文見出しは無い）
    def initialize(markdown, capi: false)
      @src = markdown
      @capi = capi
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
      parse_front_matter_raw(yaml_lines)
      emit_library_metadata
      # Skip blank lines after front matter
      advance while @index < @lines.length && current_line =~ /\A\s*\n?\z/
    end

    def emit_library_metadata
      @out.concat(@library_metadata_body) if @library_metadata_body
    end

    # front matter を生行で走査し、#@ ディレクティブを保持したまま
    # ライブラリメタ（category/require/sublibrary; H1 前）と
    # クラス関係（include/extend/alias; H1 直後）の body 行を組み立てる。
    # YAML.safe_load は #@ をコメントとして落とすため生行を使う。
    def parse_front_matter_raw(yaml_lines)
      blocks = {}   # list key => [[:item, val] | [:dir, line]]
      category = nil
      leading = []  # メタ領域先頭の #@# コメント行（irb.rd の Author 行）
      key = nil
      yaml_lines.each do |l|
        case l
        when /\A(include|extend|alias|require|sublibrary):\s*$/
          key = $1; blocks[key] = []
        when /\Acategory:\s*(.*)$/
          category = $1.strip; key = nil
        when /\A\s+- (.+?)\s*$/
          blocks[key] << [:item, $1] if key
        when /\A\#@/
          key ? blocks[key] << [:dir, l] : leading << l
        when /\A\S/
          key = nil   # その他のトップレベルキー（type/since/until 等）
        end
      end
      # クラス関係（H1 直後、RRD 文法順 alias → extend → include）
      @class_relations = []
      %w[alias extend include].each do |k|
        next unless blocks[k]
        blocks[k].each { |type, v| @class_relations << (type == :dir ? v : "#{k} #{v}\n") }
      end
      # ライブラリメタ（H1 前）
      @library_metadata_body = []
      unless leading.empty?
        @library_metadata_body.concat(leading) << "\n"
      end
      if category
        @library_metadata_body << "category #{category}\n" << "\n"
      end
      %w[require sublibrary].each do |k|
        next unless blocks[k]
        blocks[k].each { |type, v| @library_metadata_body << (type == :dir ? v : "#{k} #{v}\n") }
        @library_metadata_body << "\n"
      end
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
          @capi ? convert_capi_signature(line) : convert_h3_heading(line)
        when /\A##### /
          convert_h5_heading(line)
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
        when /\A\\#/
          convert_escaped_hash_line(line)
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
      collect_md_continuation_lines(greedy: true)
    end

    # greedy: rd 側の @param 系継続（RDCompiler の dd_without_p 相当）と対称。
    # 空白のみの行も継続として保持し、完全な空行でのみ停止する
    def collect_md_continuation_lines(greedy: false)
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
          @out << convert_inline_refs(line)
          advance
        elsif greedy && line =~ /\A[ \t]+$/
          @out << line
          advance
        elsif greedy && line =~ /\A`{3,}/
          convert_code_block(line)   # rd 側と対称: 直結するコードブロックは説明の一部
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
        @out << "#{prefix}[a:#{anchor}] #{restore_heading_backticks(text)}\n"
      else
        text = line.sub(/\A#+\s+/, '').chomp
        @out << "#{prefix} #{restore_heading_backticks(text)}\n"
      end
      advance
    end

    # 見出しテキストのバッククォート復元。参照変換（convert_bare_refs）は
    # 通さない（rd→md も見出しでは参照エスケープをしないため対称に）
    def restore_heading_backticks(text)
      strip_code_spans(text).gsub(/\\`/, '`')
    end

    def convert_h3_heading(line)
      convert_heading_with_anchor(line, '===')
    end

    def convert_h4_heading(line)
      convert_heading_with_anchor(line, '====')
    end

    def convert_h5_heading(line)
      # プレフィックス置換のみ（rd 側と対称、空白を保持）
      @out << line.sub(/\A##### /, '===== ')
      advance
    end

    def strip_code_span(text)
      text.sub(/\A`(.+)`\z/, '\\1')
    end

    def convert_dlist_colon_item(line)
      # - **`term`**: description → : term\n  description
      # - **term**:\n  line1\n  line2 → : term\n  line1\n  line2
      if line =~ /\A- \*\*(.+?)\*\*: (.+)$/
        # 構造の `term` は GNU 引用復元より先に unwrap する
        @out << ": #{convert_inline_refs(strip_code_span($1))}\n  #{convert_inline_refs($2)}\n"
        advance
      elsif line =~ /\A- \*\*(.+?)\*\*:\s*$/
        @out << ": #{convert_inline_refs(strip_code_span($1))}\n"
        advance
        # 継続行を収集（空行を挟む場合も含む）。rd 側と対称:
        # RDCompiler の dd_with_p はインデント段落とコードブロックを
        # 交互に何個でも説明として受ける（String#% 型）
        while @index < @lines.length
          l = current_line
          if l =~ /\A\s+\S/
            @out << convert_inline_refs(l)
            advance
          elsif l =~ /\A`{3,}/
            convert_code_block(l)
          elsif l =~ /\A\#@/
            # rd 側と対称: #@ 指令行は dd の文脈に透明
            raw_passthrough(l)
          elsif l =~ /\A\s*$/
            scan = @index + 1
            scan += 1 while scan < @lines.length &&
                            (@lines[scan] =~ /\A\s*$/ || @lines[scan] =~ /\A\#@/)
            nxt = scan < @lines.length ? @lines[scan] : nil
            if nxt && nxt !~ /\A- \*\*/ && (nxt =~ /\A\s+\S/ || nxt =~ /\A`{3,}/)
              @out << l
              advance
            else
              break
            end
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
      # 継続行を収集（convert_list_item と同じ、rd 側と対称）
      while @index < @lines.length
        l = current_line
        if l =~ /\A\#@/
          raw_passthrough(l)
        elsif l =~ /\A\s*$/
          break
        elsif l =~ /\A(\s+)\S/ && l !~ /\A\s*-\s/ && l !~ /\A\s*\d+\.\s/
          @out << convert_inline_refs(l)
          advance
        else
          break
        end
      end
    end

    def convert_list_item(line, indent)
      rrd_indent = indent.empty? ? ' ' : indent
      line =~ /\A\s*-(\s+)/
      content_indent = (indent.empty? ? 1 : indent.length) + 1 + $1.length
      @out << convert_inline_refs(line.sub(/\A\s*-(\s+)/, "#{rrd_indent}*\\1"))
      advance
      # 継続行を収集（空行・リスト項目・#@ で停止）。
      # rd 側と対称: 継続はインデント深さ不問（RDCompiler の項目継続規則）
      while @index < @lines.length
        l = current_line
        if l =~ /\A\#@/
          raw_passthrough(l)
        elsif l =~ /\A\s*$/
          break
        elsif l =~ /\A(\s+)\S/ && l !~ /\A\s*-\s/ && l !~ /\A\s*\d+\.\s/
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

    # capi の C シグネチャ（キーワード無し ###）を復元する
    def convert_capi_signature(line)
      @out << line.sub(/\A### /, '--- ')
      advance
    end

    # rd→md がエスケープした行頭 # のリテラル本文を復元する
    def convert_escaped_hash_line(line)
      @out << convert_inline_refs(line.sub(/\A\\/, ''))
      advance
    end

    def convert_h1(line)
      return convert_heading_with_anchor(line, '=') if line =~ /\{#[^}]+\}\s*$/
      @out << line.sub(/\A# /, '= ')
      advance
      if @class_relations && !@class_relations.empty?
        @out.concat(@class_relations)
        @class_relations = []
      end
    end

    def raw_passthrough(line)
      @out << line
      advance
    end

    def passthrough(line)
      @out << convert_inline_refs(line)
      advance
    end

    # テキスト行のコードスパンを rd の元表記へ復元する:
    # - `__WORD__`（自動スパン）→ __WORD__
    # - `token`（GNU 風引用由来）→ `token'
    # エスケープ済み \` はスパン開始とみなさない（convert_bare_refs が後で復元）
    def strip_code_spans(text)
      text.gsub(/`(__\w+__)`/, '\\1')
          .gsub(/(?<!\\)`([^`'\s]+)`/) { "`#{$1}'" }
    end

    # Markdown のブラケットリンク: エスケープされた \[ \] を含むパターン
    def convert_inline_refs(line)
      # コードスパンの復元（`__X__`・GNU 風引用）は \` の解除より先。
      # 続けて bare [type:target] → [[type:target]] (手動パースで \[\] 対応)
      convert_bare_refs(strip_code_spans(line))
    end

    def convert_bare_refs(line)
      result = +""
      i = 0
      while i < line.length
        if line[i] == '\\' && line[i + 1] == '['
          # rd→md がエスケープしたリテラル [x:y]（参照ではない）→ そのまま復元
          result << '['
          i += 2
          next
        end
        if line[i] == '\\' && line[i + 1] == '`'
          # rd→md がエスケープした生バッククォート → そのまま復元
          result << '`'
          i += 2
          next
        end
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
