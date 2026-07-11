# frozen_string_literal: true
#
# bitclust/mdcompiler.rb
#
# Markdown ソース → HTML のネイティブコンパイラ（Markdown 移行フェーズ3）。
#
# RDCompiler のサブクラスとして、行レベルのディスパッチだけを Markdown 記法
# （MARKUP_SPEC）に差し替える。HTML の出力部品（見出し・リスト・dl・
# シンタックスハイライト・リンク解決）はすべて RDCompiler から継承する。
#
# M1（等価モード、既定）: 変換器が生成する md に対して、対応する rd を
# RDCompiler にかけた場合と同一の HTML を出力する（tools/md-compile-check.rb
# が全実データで検証する）。
#
# M2（GFM モード、option :gfm => true）: GFM の表現を描画する —
# インラインコードスパン `x` → <code>、行頭 **N.** → <strong>、
# GFM テーブル（ヘッダ + 区切り行必須）→ <table>。
# M1 との差は <code>/<strong>/<table> 系マークアップのみ
# （tools/md-compile-check.rb --gfm が全実データで検証する）。

require 'bitclust/rdcompiler'
require 'bitclust/markdown_to_rrd'

module BitClust

  class MDCompiler < RDCompiler

    private

    # RDCompiler のテキストコンパイル（エスケープ・参照解決）を
    # GFM モードのセグメント処理から呼ぶための別名
    alias rd_compile_text compile_text

    def gfm?
      @option[:gfm]
    end

    # メソッド系シグネチャ（キーワード付き h3）。capi（@type == :function）は
    # キーワード無しの ### 全部がシグネチャ（capi に本文見出しは無い）
    METHOD_SIGNATURE_RE = /\A### (?:module_function def |def |const |gvar )/

    def signature_re
      @type == :function ? /\A### / : METHOD_SIGNATURE_RE
    end

    MD_ITEM_RE = /\A(\s*)(?:- |\d+\. )/
    FENCE_RE = /\A`{3,}/
    DLIST_RE = /\A- \*\*(.+?)\*\*:(?:\s|$)/
    INFO_RE = /\A- \*\*(?:param|arg|return|raise)\*\*/
    SEE_RE = /\A- \*\*SEE\*\*/
    # @undef など変換器が生のまま渡す未知メタデータ
    # （RDCompiler の entry_info ループ条件 /\A@(?!see)\w+/ と同じ）
    RAW_META_RE = /\A@(?!see)\w+/
    # 生のまま残った #@samplecode が前処理で //emlist になったもの
    EMLIST_LEFTOVER_RE = %r<\A//emlist(?:\[(?:[^\[\]]+?)?\]\[\w+?\])?\{>

    def library_file
      while @f.next?
        case @f.peek
        when signature_re
          entry_chunk
        when /\A\\?#/
          if /\A\\#/ =~ @f.peek
            paragraph   # 行頭 # のリテラル本文（エスケープ済み）
          else
            headline @f.gets || raise
          end
        when SEE_RE
          # findings#1: doc/lib ページの @see も SEE_ALSO（rd 側と同期）
          see
        when DLIST_RE
          dlist
        when MD_ITEM_RE
          @item_stack = []
          item_list(($1 || raise).size)
          raise "@item_stack should be empty. #{@item_stack.inspect}" unless @item_stack.empty?
        when FENCE_RE
          code_fence
        when EMLIST_LEFTOVER_RE
          # リスト脈絡などで生のまま残った #@samplecode は前処理で
          # //emlist になる。RDCompiler と同じ独立ブロックとして描画する
          emlist
        when /\A\s*\|/
          paragraph unless try_table
        else
          if @f.peek&.strip&.empty?
            @f.gets
          else
            paragraph
          end
        end
      end
    end

    def entry_chunk
      @out.puts '<dl>' if @option[:force]
      first = true
      @f.while_match(signature_re) do |line|
        method_signature(line, first)
        first = false
      end
      @out.puts %Q(<dd class="#{@type.to_s}-description">)
      while @f.next?
        case @f.peek
        when signature_re
          break
        when /\A\#{3,}\s/
          headline @f.gets || raise
        when /\A\\#/
          entry_paragraph   # エスケープされた行頭 # リテラル
        when /\A\#{1,2}\s/
          if @option[:force]
            break
          else
            raise "#{@type.to_s} entry includes headline: #{@f.peek.inspect}"
          end
        when SEE_RE
          see
        when INFO_RE
          entry_info
        when DLIST_RE
          dlist
        when MD_ITEM_RE
          @item_stack = []
          item_list(($1 || raise).size)
          raise "@item_stack should be empty. #{@item_stack.inspect}" unless @item_stack.empty?
        when FENCE_RE
          code_fence
        when EMLIST_LEFTOVER_RE
          emlist
        when /\A@todo\b/
          # findings#3: rd 側と同じく行頭アンカー付きで
          todo
        when /\A@undef\b/
          undef_message
        when RAW_META_RE
          entry_info
        when /\A\s*\|/
          entry_paragraph unless try_table
        else
          if @f.peek&.strip&.empty?
            @f.gets
          else
            entry_paragraph
          end
        end
      end
      @out.puts '</dd>'
      @out.puts '</dl>' if @option[:force]
    end

    # md シグネチャ行を rd 形式（--- ...）へ落とし、既存のシグネチャ処理
    # （MethodSignature.parse・permalink・edit link）を継承する
    def method_signature(sig_line, first)
      super(sig_line.sub(signature_re, '--- '), first)
    end

    def headline(line)
      hashes = line[/\A#+/] || raise
      label = line.sub(/\A#+\s*/, '').strip
      frag = nil
      if label =~ /\{#([^}]+)\}\z/
        frag = $1
        label = label.sub(/\s*\{#[^}]+\}\z/, '')
      end
      level = @hlevel + (hashes.size - 3)
      line h(level, escape_html(restore_rd_text(label)), frag)
    end

    def read_paragraph(f)
      f.span(%r{\A(?!\#|`{3}|- |\d+\. |//emlist(?:\[(?:[^\[\]]+?)?\]\[\w+?\])?\{)\S|\A\\#})
    end

    def read_entry_paragraph(f)
      f.span(%r{\A(?!\#|`{3}|- |\d+\. |@[a-z]|//emlist(?:\[(?:[^\[\]]+?)?\]\[\w+?\])?\{)\S|\A\\#})
    end

    def paragraph
      line '<p>'
      line compile_text(text_node_from_lines(read_paragraph(@f).map { |l| unescape_hash(l) }))
      line '</p>'
    end

    def entry_paragraph
      line '<p>'
      line compile_text(text_node_from_lines(read_entry_paragraph(@f).map { |l| unescape_hash(l) }))
      line '</p>'
    end

    def unescape_hash(line)
      line.sub(/\A\\#/, '#')
    end

    # - **param** `name` -- desc / - **return** -- desc / - **raise** `Ex` -- desc
    # および生の @xxx（未知メタデータ、RDCompiler と同じく UNKNOWN_META_INFO）
    def entry_info
      line '<dl>'
      while @f.next? and INFO_RE =~ @f.peek || RAW_META_RE =~ @f.peek || /\A$/ =~ @f.peek
        header = @f.gets or raise
        next if /\A$/ =~ header
        if RAW_META_RE =~ header
          cmd = header.slice!(/\A@\w+/) or raise
          @f.ungets(header)
          line "<dt>[UNKNOWN_META_INFO] #{escape_html(cmd)}:</dt>"
          dd_without_p
          next
        end
        case header
        when /\A- \*\*(param|arg)\*\*\s+`([^`]+)`( --(?:.*))?$/m
          line "<dt class='#{@type.to_s}-param'>[PARAM] #{name_html($2)}:</dt>"
          rest = $3 ? ($3 || raise).sub(/\A --/, '') : +"\n"
        when /\A- \*\*raise\*\*\s+`([^`]+)`( --(?:.*))?$/m
          line "<dt>[EXCEPTION] #{name_html($1)}:</dt>"
          rest = $2 ? ($2 || raise).sub(/\A --/, '') : +"\n"
        when /\A- \*\*return\*\*( --(?:.*))?$/m
          line "<dt>[RETURN]</dt>"
          rest = $1 ? ($1 || raise).sub(/\A --/, '') : +"\n"
        else
          raise "must not happen: #{header.inspect}"
        end
        # 「@raise Ex 」（説明なし・末尾スペース）は rd では dd 内の空白テキスト行に
        # なるため、rest の空白は潰さずそのまま戻す（+"\n" は凍結回避）
        @f.ungets(rest)
        dd_without_p
      end
      line '</dl>'
    end

    # - **SEE** [m:X], [m:Y]（継続行あり）
    def see
      header = @f.gets or raise
      header = header.sub(SEE_RE, '')
      body = [header] + @f.span(/\A\s+\S/)
      line '<p>'
      line '[SEE_ALSO] ' + compile_text(text_node_from_lines(body))
      line '</p>'
    end

    # - **`term`**: / - **term**: の定義リスト（説明はインデント行）
    def dlist
      line '<dl>'
      while @f.next? and DLIST_RE =~ @f.peek
        @f.while_match(DLIST_RE) do |l|
          l =~ DLIST_RE or raise
          # rd の dt は term を strip する（term 末尾スペースは dt に含めない）。
          # GFM モード: `term` のコードスパンは <code> として描画し、
          # 中身の参照はその中で解決する（<code><a>...</a></code>。spec/eval）
          term = ($1 || raise)
          if gfm? && term =~ /\A`(.+)`\z/
            inner = ($1 || raise).strip
            line dt("<code>#{rd_compile_text(MarkdownToRRD.restore_inline(inner))}</code>")
          else
            term = strip_code_span(term).strip
            line dt(compile_text(term))
          end
          inline = l.sub(DLIST_RE, '').strip
          @f.ungets("  #{inline}\n") unless inline.empty?
        end
        dd_with_p
      end
      line '</dl>'
    end

    def strip_code_span(text)
      text.sub(/\A`(.+)`\z/, '\1')
    end

    # param 名・raise 例外名: GFM モードでは <code> で包む
    def name_html(name)
      gfm? ? "<code>#{escape_html(name)}</code>" : escape_html(name)
    end

    # GFM テーブルの区切り行（|---|:--:|... 。少なくとも1つの - が必要）
    TABLE_DELIM_RE = /\A\s*\|?\s*:?-+:?\s*(?:\|\s*:?-+:?\s*)*\|?\s*$/

    # GFM テーブル。厳格判定: ヘッダ行の直後に区切り行がある場合のみ
    # テーブルとして描画する（本文が | で始まる散文と誤認しない。FalseClass）。
    # テーブルでなければ何も消費せず false を返す
    def try_table
      return false unless gfm?
      header = @f.gets or return false
      unless @f.peek && TABLE_DELIM_RE =~ @f.peek
        @f.ungets(header)
        return false
      end
      aligns = parse_table_aligns(@f.gets || raise)
      line '<table>'
      line '<thead>'
      table_row(header, 'th', aligns)
      line '</thead>'
      line '<tbody>'
      while @f.peek =~ /\A\s*\|/
        table_row(@f.gets || raise, 'td', aligns)
      end
      line '</tbody>'
      line '</table>'
      true
    end

    def parse_table_aligns(delim)
      split_table_row(delim).map { |cell|
        case cell
        when /\A:-+:\z/ then 'center'
        when /\A:-+\z/  then 'left'
        when /\A-+:\z/  then 'right'
        end
      }
    end

    def table_row(row, tag, aligns)
      cells = split_table_row(row)
      string '<tr>'
      cells.each_with_index do |cell, i|
        align = aligns[i] ? %Q( align="#{aligns[i]}") : ''
        string "<#{tag}#{align}>#{compile_text(cell)}</#{tag}>"
      end
      line '</tr>'
    end

    # 行をセルに分割（先頭/末尾の | を除去、\| はリテラルの |）
    def split_table_row(row)
      row.strip.sub(/\A\|/, '').sub(/\|\z/, '')
         .gsub('\\|', "\x03").split('|', -1)
         .map { |c| c.gsub("\x03", '|').strip }
    end

    # フェンスドコードブロック:
    # - ```lang title="cap"（emlist/samplecode 由来）→ ハイライト付き <pre>
    # - ```（3個・lang なし。//emlist{ 由来）→ 素の <pre>（rstrip escape）
    # - ````+（4個以上。インデントテキスト由来）→ 素の <pre>（rd の list 相当）
    def code_fence
      open_line = @f.gets or raise
      fence = open_line[/\A`+/] or raise
      rest = open_line[fence.size..].to_s.strip
      lang = nil
      caption = nil
      if rest =~ /\A(\w+)?(?:\s+title="((?:[^"\\]|\\.)*)")?\z/
        lang = $1
        caption = $2&.gsub(/\\(["\\])/, '\1')
      end
      terminator = /\A`{#{fence.size}}\s*$/
      if lang
        line "<pre class=\"highlight #{lang}\">"
        line "<span class=\"caption\">#{escape_html(caption)}</span>" if caption
        line "<code>"
        src = +""
        @f.until_terminator(terminator) do |code_line|
          src << code_line
        end
        string highlight_source(src, lang, caption)
        line '</code></pre>'
      elsif fence.size == 3
        line '<pre>'
        @f.until_terminator(terminator) do |code_line|
          line escape_html(code_line.rstrip)
        end
        line '</pre>'
      else
        # 変換器はベースインデント（= フェンス長 - 3）を除去して格納している。
        # RDCompiler の list は detab（タブをカラム位置で空白展開）を元の
        # カラムで行うため、ベースインデントを戻してから同じ処理を通す。
        # #@since/#@else ゲートで分断されたインデントブロックは前処理後に
        # 隣接フェンスとして現れるため、続けてマージする（rd では連続
        # インデント行として1つの <pre> になる。ArgumentError 等）
        segments = [[fence.size - 3, collect_fence_lines(terminator)]]
        loop do
          # rd の pre は空白行を跨ぐ（list は /\A\S/ まで継続）ため、
          # フェンス間の空白のみ行も次が 4+ フェンスならブロックの一部
          blanks = [] #: Array[String]
          blanks << (@f.gets || raise) while @f.peek =~ /\A\s*$/
          unless @f.peek =~ /\A(`{4,})\s*$/
            blanks.reverse_each { |b| @f.ungets(b) }
            break
          end
          next_fence = ($1 || raise)
          @f.gets
          segments.last[1].concat(blanks)
          segments << [next_fence.size - 3,
                       collect_fence_lines(/\A`{#{next_fence.size}}\s*$/)]
        end
        lines = segments.flat_map { |base, ls|
          ls.map { |l| l =~ /\A\s*\z/ ? l : (' ' * base) + l }
        }
        lines = unindent_block(canonicalize(lines))
        while lines.last&.empty?
          lines.pop
        end
        line '<pre>'
        lines.each do |code_line|
          line escape_html(code_line)
        end
        line '</pre>'
      end
    end

    def collect_fence_lines(terminator)
      lines = [] #: Array[String]
      @f.until_terminator(terminator) do |code_line|
        lines << code_line
      end
      lines
    end

    # 箇条書き（- item / N. item、ネスト・継続行あり）
    def item_list(level = 0)
      open_tag = nil
      close_tag = nil
      case @f.peek
      when /\A\s*- /
        open_tag  =  "<ul>"
        close_tag = "</ul>"
      when /\A\s*\d+\. /
        open_tag  = "<ol>"
        close_tag = "</ol>"
      end
      line open_tag
      @item_stack.push(close_tag)
      @f.while_match(MD_ITEM_RE) do |item_line|
        string "<li>"
        @item_stack.push("</li>")
        string compile_text(item_line.sub(/\A\s*(?:-|\d+\.)\s?/, '').strip)
        if /\A(\s+)(?!- |\d+\. )\S/ =~ @f.peek
          @f.while_match(/\A\s+(?!- |\d+\. )\S/) do |cont|
            nl
            string compile_text(cont.strip)
          end
        end
        if (m = MD_ITEM_RE.match(@f.peek)) && level < (m[1] || raise).size
          item_list((m[1] || raise).size)
          line @item_stack.pop # current level li
          break if MD_ITEM_RE =~ @f.peek and level > ($1 || raise).size
        elsif m && level > (m[1] || raise).size
          line @item_stack.pop # current level li
          break
        else
          line @item_stack.pop # current level li
        end
      end
      line @item_stack.pop unless @item_stack.empty?
    end

    # RDCompiler の dd_with_p / dd_without_p の md 版:
    # コードブロック（rd では //emlist）の判定をフェンスに差し替える
    def dd_with_p
      line '<dd>'
      while /\A(?:\s|\z)/ =~ @f.peek or FENCE_RE =~ @f.peek
        case @f.peek
        when /\A$/
          @f.gets
        when /\A[ \t]/
          line '<p>'
          line compile_text(text_node_from_lines(@f.span(/\A[ \t]/)))
          line '</p>'
        when FENCE_RE
          code_fence
        else
          raise 'must not happen'
        end
      end
      line '</dd>'
    end

    def dd_without_p
      line '<dd>'
      while /\A[ \t]/ =~ @f.peek or FENCE_RE =~ @f.peek
        case @f.peek
        when /\A[ \t]/
          line compile_text(text_node_from_lines(@f.span(/\A[ \t]/)))
        when FENCE_RE
          code_fence
        end
      end
      line '</dd>'
    end

    # テキストノード: インライン記法を rd 形式へ復元してから既存の
    # コンパイル（エスケープ・リンク解決）を継承する。
    # M1 等価モード: 変換器が付けた __X__ の自動コードスパンは剥がす
    def compile_text(str)
      return compile_gfm_text(str) if gfm?
      super(restore_rd_text(str))
    end

    # GFM モードのテキストコンパイル:
    # コードスパン `x` → <code>（中身は参照解決しない・HTML エスケープのみ）、
    # 行頭 **N.** → <strong>。エスケープ済み \` はリテラルのバッククォート
    def compile_gfm_text(str)
      hidden = str.gsub(/\\`/, "\x00")
      hidden.split(/(`[^`\n]+`)/, -1).map { |seg|
        if seg =~ /\A`([^`\n]+)`\z/
          "<code>#{escape_html(($1 || raise).gsub("\x00", '`'))}</code>"
        else
          seg = seg.gsub(/^\*\*(\d+\.)\*\* /, "\x01\\1\x02 ")
          rd_compile_text(MarkdownToRRD.restore_inline(seg))
            .gsub("\x01", '<strong>').gsub("\x02", '</strong>')
            .gsub("\x00", '`')
        end
      }.join
    end

    def restore_rd_text(str)
      # M1 等価モード: md のコードスパンを rd の元表記へ戻して描画する
      MarkdownToRRD.restore_text(str)
    end
  end

end
