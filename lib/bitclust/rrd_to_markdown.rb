# frozen_string_literal: true

module BitClust
  class RRDToMarkdown
    def self.convert(rrd, extra_front_matter: {}, capi: false)
      rrd = normalize_dlist_colon_spacing(rrd)
      new(rrd, extra_front_matter: extra_front_matter, capi: capi).convert
    end

    # RDCompiler の dlist 継続は /\A:/（スペース不要）で dt になる
    # （spec/operator の「:再定義できない演算子」）。dlist 文脈にある
    # 「:term」だけを正規形「: term」に直す。段落継続の「:SYMBOL」行
    # （openssl/ASN1 等）は RDCompiler では段落テキストなので触らない。
    # 文脈判定は RDCompiler のディスパッチを行単位で再現する
    def self.normalize_dlist_colon_spacing(rrd)
      state = :none      # :none | :para | :dlist
      in_code = nil      # コードブロックの終端パターン
      rrd.lines.map { |l|
        if in_code
          in_code = nil if l =~ in_code
          next l
        end
        case l
        when /\A\#@samplecode/
          in_code = /\A\#@end/
          l
        when /\A\/\/emlist.*\{/
          in_code = %r<\A//\}>
          state = :none unless state == :dlist   # dd 内の emlist は dlist 継続
          l
        when /\A\#@/
          l                                      # ディレクティブは文脈に透明
        when /\A:\s/
          state = :dlist unless state == :para   # 段落継続中の「: 」行は段落
          l
        when /\A:(?=\S)/
          if state == :dlist
            ": #{l[1..]}"
          else
            state = :para                        # 段落（開始または継続）
            l
          end
        when /\A[ \t]*\n?\z/
          state = :none unless state == :dlist   # 空行: dd は空行を跨ぐ
          l
        when /\A[ \t]/
          state = :none unless state == :dlist   # dd 説明は継続、段落は終了
          l
        when /\A(?:---|=)/
          state = :none
          l
        else
          state = :para
          l
        end
      }.join
    end

    # ファイル単体からは決められない front matter（library 所属・構造 since/until）を
    # 注入するための口。include グラフを解析したオーケストレータが値を計算して渡す。
    EXTRA_FRONT_MATTER_KEYS = %w[type library since until].freeze

    # capi: C API リファレンス（refm/capi）モード。シグネチャは C の
    # 「--- <型付きシグネチャ>」で、def 等のキーワードを付けずに ### へ変換する
    def initialize(rrd, extra_front_matter: {}, capi: false)
      @src = rrd
      @capi = capi
      @extra_front_matter = extra_front_matter.transform_keys(&:to_s)
      unknown = @extra_front_matter.keys - EXTRA_FRONT_MATTER_KEYS
      unless unknown.empty?
        raise ArgumentError, "unknown extra front matter keys: #{unknown.join(', ')}"
      end
    end

    def convert
      @lines = @src.lines
      @out = []
      @index = 0
      @front_matter = {}
      @current_section = nil
      # front matter はファイル単位。複数エンティティを含むファイルでは
      # include/extend/alias の帰属が曖昧になるため、単一エンティティ時のみ front matter 化する
      # （分割前の安全策。分割後は全ファイルが単一エンティティになる）。
      @single_entity = @lines.count { |l| l =~ /\A= / } == 1

      collect_library_metadata
      process_body
      @front_matter.merge!(@extra_front_matter)
      emit_front_matter + @out.join
    end

    private

    SAMPLECODE_RE = /\A\#@samplecode/

    def collect_library_metadata
      # capi には require/category 等の library メタデータは存在しない。
      # 本文が「require の C 版です。」のように require で始まる場合の誤認を防ぐ
      return if @capi
      scan = @index
      tokens = []       # [:cat, val] | [:req, val] | [:sub, val] | [:dir, line] | [:cmt, line] | [:blank]
      nest = 0
      checkpoint = nil  # 直近の「nest==0 の空行直後」= [scan, tokens.size]。
                        # メタ確定をここまでで打ち切れる安全な切れ目
                        # （md→rd の再生成がメタ群の後に空行を出すため、空行が必須）
      while scan < @lines.length
        l = @lines[scan]
        case l
        when /\Acategory\s+(.*)$/
          return if nest > 0            # 版条件つき scalar category → 据え置き（データ上0件）
          tokens << [:cat, $1.strip]; scan += 1
        when /\Arequire\s+(.*)$/
          tokens << [:req, $1.strip]; scan += 1
        when /\Asublibrary\s+(.*)$/
          tokens << [:sub, $1.strip]; scan += 1
        when /\A\#@(?:since|until|if)\b/
          tokens << [:dir, l]; nest += 1; scan += 1
        when /\A\#@else\b/
          tokens << [:dir, l]; scan += 1
        when /\A\#@end\b/
          break if nest == 0
          tokens << [:dir, l]; nest -= 1; scan += 1
        when /\A\s*$/
          tokens << [:blank]; scan += 1
          checkpoint = [scan, tokens.size] if nest == 0
        when /\A\#@\#/
          # #@# コメント（irb.rd の Author 行・require 群中の注記）→
          # メタトークンとして保持。本文の前置き（rss.rd 型）だった場合は
          # 確定時に末尾トリムで body へ戻す
          tokens << [:cmt, l]; scan += 1
        when /\A\#@/
          # #@todo 等 → チェックポイントまでで確定
          return unless checkpoint
          scan, tokens = checkpoint[0], tokens[0, checkpoint[1]]
          nest = 0
          break
        else
          break if nest == 0            # body
          # 版分岐の途中で body に到達（set.rd/thread.rd の版分岐つき散文）
          # → チェックポイントまでで確定し、版分岐ごと body に渡す
          return unless checkpoint
          scan, tokens = checkpoint[0], tokens[0, checkpoint[1]]
          nest = 0
          break
        end
      end
      # 末尾の cmt/blank 連鎖に #@# が含まれる場合、それはメタでなく本文の
      # 前置きコメント（rss.rd の「#@# = rss」）→ 最初の cmt 以降を body へ戻す
      # （連鎖先頭の空行はメタ領域の終端空行として残す）
      chain_start = (tokens.rindex { |t| !%i[cmt blank].include?(t[0]) } || -1) + 1
      if (first_cmt = tokens[chain_start..].index { |t| t[0] == :cmt })
        drop = tokens.length - (chain_start + first_cmt)
        scan -= drop
        tokens = tokens[0...-drop]
      end
      return unless tokens.any? { |t| %i[cat req sub].include?(t[0]) }
      return if nest != 0               # ファイル全体の版ゲート内で EOF → 据え置き
      return unless build_metadata_front_matter(tokens)
      @index = scan                     # メタ領域（末尾空行含む）を消費
    end

    # 先頭メタデータ領域の tokens を front matter へ組み立てる。
    # category は scalar、require/sublibrary は組み立て済みブロック行
    # （#@ ディレクティブや #@# コメントを挟める）。
    # #@ ブロックは単一種のみ対応（データ上、混在・category 包みは存在しない）。
    # 最初のメタ行より前の #@#（irb.rd の Author 行）は leading スロットへ。
    def build_metadata_front_matter(tokens)
      # 先頭の #@# コメント群: 直後に空行が続くもの（irb.rd の Author 行）は
      # leading スロットへ。メタ行が直続するもの（irb/workspace.rd の
      # require 注記）はそのメタブロックの先頭行として list 側に流す
      first_non_cmt = tokens.index { |t| t[0] != :cmt } || tokens.length
      if first_non_cmt > 0 && tokens[first_non_cmt]&.first == :blank
        @front_matter['leading'] = tokens[0...first_non_cmt].map { |t| t[1] }
        tokens = tokens[first_non_cmt..]
      end
      toks = tokens.reject { |t| t[0] == :blank }

      cats = toks.select { |t| t[0] == :cat }
      return false if cats.size > 1
      @front_matter['category'] = cats.first[1] if cats.first
      list_toks = toks.reject { |t| t[0] == :cat }
      if list_toks.none? { |t| %i[dir cmt].include?(t[0]) }
        { req: 'require', sub: 'sublibrary' }.each do |sym, key|
          items = list_toks.select { |t| t[0] == sym }
          @front_matter[key] = items.map { |t| "  - #{t[1]}\n" } unless items.empty?
        end
        return true
      end
      kinds = list_toks.select { |t| %i[req sub].include?(t[0]) }.map { |t| t[0] }.uniq
      return false if kinds.size != 1
      key = kinds.first == :req ? 'require' : 'sublibrary'
      @front_matter[key] = list_toks.map { |t| %i[dir cmt].include?(t[0]) ? t[1] : "  - #{t[1]}\n" }
      true
    end

    def emit_front_matter
      return '' if @front_matter.empty?
      lines = ["---\n"]
      # 順序: type, library, include, extend, alias, since, until, category, require, sublibrary（MARKUP_SPEC §1.7）
      %w[type library].each do |key|
        if v = @front_matter[key]
          lines << "#{key}: #{v}\n"
        end
      end
      %w[include extend alias].each do |key|
        if block = @front_matter[key]
          lines << "#{key}:\n"
          block.each { |bl| lines << bl }  # block は組み立て済みの行（`  - item\n` / `#@...\n`）
        end
      end
      %w[since until].each do |key|
        if v = @front_matter[key]
          lines << "#{key}: \"#{v}\"\n"   # "3.10" が float 3.1 に化けないよう常にクォート（§1.2）
        end
      end
      if block = @front_matter['leading']
        block.each { |bl| lines << bl }  # メタ領域先頭の #@# コメント行
      end
      if v = @front_matter['category']
        lines << "category: #{v}\n"
      end
      %w[require sublibrary].each do |key|
        if block = @front_matter[key]
          lines << "#{key}:\n"
          block.each { |bl| lines << bl }  # 組み立て済み行（`  - item\n` / `#@...\n`）
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
        when /\A---(?=[^\s-])/, /\A--- /
          # RDCompiler は /\A---/ で受理するため「---name」（スペース無し）も
          # シグネチャ（正規形「--- name」に直して変換する）
          convert_signature(line)
        when /\A={1,4}\[a:([^\]]+)\]\s+(.*)/
          convert_anchored_heading(line, $1, $2)
        when /\A===== /
          convert_h5(line)
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
          term = $1
          # RDCompiler は段落中（テキスト行直後）の「: 」行を段落の継続とする。
          # 直前の出力が段落テキストなら dlist 化せずそのまま流す（news/1.8.5 型）
          if @out.last =~ /\A(?!- |#|`|@)\S/
            @out << convert_inline_refs(line)
            advance
          else
            convert_dlist_item(line, term)
          end
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
      # 「--- 」または「---name」（スペース無し形）のプレフィックスだけ除去。
      # 2つ目以降の空白はシグネチャの一部として保持する（B1）
      sig = line.sub(/\A---(?: |(?=[^\s-]))/, '').chomp
      # B1: 空白を保持（正規化しない）

      if @capi
        # C API: シグネチャは型から始まり自己記述的。キーワードは付けない
        @out << "### #{sig}\n"
        advance
        return
      end

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
      collect_continuation_lines(greedy: true)
    end

    def convert_raise(line)
      l = line.chomp
      if l =~ /\A@raise(\s+)(\S+)(\s+)(.*)\z/
        @out << "- **raise**#{$1}`#{$2}` --#{$3}#{convert_inline_refs($4)}\n"
      elsif l =~ /\A@raise(\s+)(\S+)\z/
        @out << "- **raise**#{$1}`#{$2}` --\n"
      end
      advance
      collect_continuation_lines(greedy: true)
    end

    def convert_return(line)
      # B2: @return 後のスペースを保持
      rest = line.sub(/\A@return/, '').chomp
      @out << "- **return** --#{convert_inline_refs(rest)}\n"
      advance
      collect_continuation_lines(greedy: true)
    end

    def convert_see(line)
      # @see → - **SEE**、[[→[ 置換、区切りは保持
      rest = line.sub(/\A@see(\s+)/, '').chomp
      space = $1
      converted = convert_inline_refs(rest)
      @out << "- **SEE**#{space}#{converted}\n"
      advance
      collect_continuation_lines   # RDCompiler の see は空白のみ行で停止する（greedy 不可）
    end

    # greedy: RDCompiler の dd_without_p と同じ貪欲さ（@param 等のメタデータ用）。
    # 空白を含む行（"   \n" や空白行を挟んだ例示ブロック）も継続し、
    # 完全な空行（"\n"）でのみ停止する。@see は従来規則（空白のみ行で停止）
    def collect_continuation_lines(greedy: false)
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
        elsif greedy && line =~ /\A[ \t]+$/
          @out << line
          advance
        elsif greedy && line =~ SAMPLECODE_RE
          convert_samplecode(line)   # RDCompiler の dd はコードブロックも説明の一部
        elsif greedy && line =~ /\A\/\/emlist/
          convert_emlist(line)
        else
          break
        end
      end
    end

    def convert_anchored_heading(line, anchor, text)
      prefix = '#' * line[/\A=+/].length
      @out << "#{prefix} #{escape_backticks(text)} {##{anchor}}\n"
      advance
    end

    def convert_h3(line, text)
      @out << "### #{text}\n"
      advance
    end

    def convert_h4(line, text)
      @out << "#### #{text}\n"
      advance
    end

    def convert_h5(line)
      # プレフィックス置換のみ（余分な空白・末尾空白を保持。psych.rd）
      @out << line.sub(/\A===== /, '##### ')
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
      # 継続行を収集（空行・リスト項目で停止）。
      # RDCompiler の項目継続はインデント深さ不問（項目より浅い折り返しも継続）
      while @index < @lines.length
        l = current_line
        if l =~ /\A\#@/
          raw_passthrough(l)
        elsif l =~ /\A\s*$/
          break  # 空行でリスト継続終了
        elsif l =~ /\A(\s+)\S/ && l !~ /\A\s+\*\s/ && l !~ /\A\s+\(\d+\)\s/
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
      # 継続行を収集（ulist と同じ。RDCompiler の項目継続はインデント深さ不問）
      while @index < @lines.length
        l = current_line
        if l =~ /\A\#@/
          raw_passthrough(l)
        elsif l =~ /\A\s*$/
          break
        elsif l =~ /\A(\s+)\S/ && l !~ /\A\s+\*\s/ && l !~ /\A\s+\(\d+\)\s/
          @out << convert_inline_refs(l)
          advance
        else
          break
        end
      end
    end

    def code_like_term?(term)
      # バッククォート/バックスラッシュを含む term はスパン化しない
      # （`term` の境界が \` エスケープと曖昧になるため。symref 等）
      term.length < 40 && term !~ /\p{Hiragana}|\p{Katakana}|\p{Han}|[`\\]/
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
      @out << "- #{formatted}:\n"
      # 説明を収集。RDCompiler の dd_with_p と同じ貪欲さ:
      # 空行（何行でも）を跨いでインデント行か emlist が続く限り説明の一部
      # （インデント段落と emlist を交互に何個でも受ける。String#% 型）
      while @index < @lines.length
        l = current_line
        if l =~ /\A(\s+)\S/
          @out << convert_inline_refs(l)
          advance
        elsif l =~ SAMPLECODE_RE
          convert_samplecode(l)
        elsif l =~ /\A\/\/emlist/
          convert_emlist(l)
        elsif l =~ /\A\#@/
          # #@ 指令行は dd の文脈に透明（版解決後は消えて説明が連続する。
          # ここで打ち切ると後続インデント行がコード扱いになる。pack-template）
          raw_passthrough(l)
        elsif l =~ /\A\s*$/
          scan = @index + 1
          scan += 1 while scan < @lines.length &&
                          (@lines[scan] =~ /\A\s*$/ || @lines[scan] =~ /\A\#@/)
          nxt = scan < @lines.length ? @lines[scan] : nil
          if nxt && (nxt =~ /\A\s+\S/ || nxt =~ SAMPLECODE_RE || nxt =~ /\A\/\/emlist/)
            @out << l
            advance
          else
            break
          end
        else
          break
        end
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
          # RDCompiler の list は /\A\S/ まで継続する（空行は何行でも跨ぐ）。
          # 空行列の先に再びインデント行が来るなら同じブロックの一部
          scan = @index + 1
          scan += 1 while scan < @lines.length && @lines[scan] =~ /\A\s*$/
          if scan < @lines.length && @lines[scan] =~ /\A\s+\S/
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
      collect_header_relations
    end

    # H1 直後の include/extend/alias を front matter へ集約する。
    # #@ で囲まれた版条件つきのヘッダ関係は当面 body 据え置き（スライス2で対応）。
    def collect_header_relations
      return unless @single_entity
      scan = @index
      tokens = []       # [:blank] | [:rel, kind, val] | [:dir, line]
      nest = 0
      saw_rel = false
      region_end = @index
      while scan < @lines.length
        l = @lines[scan]
        case l
        when /\A(include|extend|alias)\s+(.+)$/
          tokens << [:rel, $1, $2.strip]; scan += 1; saw_rel = true; region_end = scan
        when /\A\#@(?:since|until|if)\b/
          tokens << [:dir, l]; nest += 1; scan += 1
        when /\A\#@else\b/
          tokens << [:dir, l]; scan += 1
        when /\A\#@end\b/
          break if nest == 0
          tokens << [:dir, l]; nest -= 1; scan += 1; region_end = scan
        when /\A\s*$/
          tokens << [:blank]; scan += 1
        when /\A\#@/
          break if nest == 0            # level-0 の #@ コメント等は body 境界
          tokens << [:dir, l]; scan += 1
        else
          return if nest > 0            # #@ ブロック内の本文 → ヘッダ関係でない → 据え置き
          break                         # level-0 の本文 → ヘッダ領域終端
        end
      end
      return unless saw_rel
      return if nest != 0               # 不均衡 → 据え置き
      return unless build_header_front_matter(tokens)
      @index = region_end
    end

    # tokens を front matter のブロック行（`  - item\n` / `#@...\n`）へ組み立てる。
    # 素の関係行と、#@ ブロック（内部は単一種のみ）の並びを種別ごとに集約する。
    # 1ブロック内の種別混在（データ上存在しない）は据え置き。
    def build_header_front_matter(tokens)
      toks = tokens.reject { |t| t[0] == :blank }
      chunks = []   # [kind, 組み立て済み行の配列]
      i = 0
      while i < toks.length
        t = toks[i]
        if t[0] == :rel
          chunks << [t[1], ["  - #{t[2]}\n"]]
          i += 1
          next
        end
        # #@ ブロック: 対応する #@end までを1チャンクに
        depth = 0
        lines = []
        kinds = []
        while i < toks.length
          tt = toks[i]
          if tt[0] == :dir
            lines << tt[1]
            depth += 1 if tt[1] =~ /\A\#@(?:since|until|if)\b/
            depth -= 1 if tt[1] =~ /\A\#@end\b/
          else
            lines << "  - #{tt[2]}\n"
            kinds << tt[1]
          end
          i += 1
          break if depth.zero?
        end
        return false if depth != 0 || kinds.uniq.size != 1
        chunks << [kinds.first, lines]
      end
      chunks.group_by(&:first).each do |kind, group|
        @front_matter[kind] = group.flat_map(&:last)
      end
      true
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
      # 行頭 # のリテラル本文（旧 news 等）は MD 見出しと誤認されるためエスケープ
      line = "\\#{line}" if line.start_with?('#')
      @out << add_code_spans(convert_inline_refs(line))
      advance
    end

    # テキスト行の __WORD__ パターンをコードスパンに変換。
    # ブラケットリンク内は除外（convert_inline_refs 後に呼ばれるため、
    # 保護対象は md の一重括弧 [type:...]。[m:Delegator#__getobj__] 等）
    def add_code_spans(text)
      # クロスリファレンス部分を保護して変換
      parts = text.split(/(\[[a-zA-Z][\w-]*:[^\]]*\])/)
      parts.map { |part|
        if part.start_with?('[') && part.end_with?(']')
          part
        else
          part.gsub(/(__\w+__)/, '`\\1`')
        end
      }.join
    end

    # BitClust::RDCompiler::BracketLink と同等の正規表現
    BRACKET_LINK = /\[\[[\w-]+?:[!-~]+?(?:\[\] )?\]\]/n

    def convert_inline_refs(text)
      remain = text.b
      result = +''.b
      while (m = BRACKET_LINK.match(remain))
        result << escape_ref_lookalikes(m.pre_match) << convert_one_ref(m[0])
        remain = m.post_match
      end
      result << escape_ref_lookalikes(remain)
      result.force_encoding(text.encoding)
    end

    def convert_one_ref(match)
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
    end

    # 参照に見えるリテラル本文 [ruby-talk:198440] 等（旧 news）をエスケープする。
    # エスケープしないと md→rd の bare-ref 復元で [[...]] に誤変換される
    # 本文バッククォートの GFM 忠実化（M2）:
    # - GNU 風引用 `token'（rd に code マークアップがなかった代替記法。
    #   getoptlong の `--version' 等）→ インラインコードスパン `token`
    # - それ以外の生バッククォート → \` エスケープ（偶発スパン防止）
    # md→rd が両方とも復元する。__WORD__ の自動スパンはこの後の
    # add_code_spans が付けるため対象外
    def escape_ref_lookalikes(bin)
      escape_backticks(
        bin.gsub(/(?<!\[)\[([a-zA-Z][a-zA-Z-]*:[^\[\]]*)\](?!\])/n) { "\\[#{$1}]" }
      )
    end

    # GNU 風引用 `token' → コードスパン、残りの生バッククォート → \` 。
    # 除外（エスケープで温存）:
    # - 開き ` の直前が \（rd の正規表現特殊変数 \` 等）
    # - 中身にバックスラッシュ（DOSISH の `\' 等。閉じ ` が \` と曖昧になる）
    # - TeX 風二重引用 ``text''（rdoc.rd。開き直前の ` と閉じ直後の ' で判定）
    # 見出しなど参照変換を通さないパスからも使う
    def escape_backticks(bin)
      bin.gsub(/(?<![\\`])`([^`'\s\\]+)'(?!')/) { "\x00#{$1}\x00" }
         .gsub('`', '\\\\`')
         .gsub("\x00", '`')
    end

    def current_line
      @lines[@index]
    end

    def advance
      @index += 1
    end
  end
end
