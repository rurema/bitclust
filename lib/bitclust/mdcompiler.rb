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
# M1（等価モード）: 変換器が生成する md に対して、対応する rd を
# RDCompiler にかけた場合と同一の HTML を出力する（tools/md-compile-check.rb
# が全実データで検証する）。GFM 拡張（テーブル、コードスパンの <code> 化等）は
# M2 で解禁する。

require 'bitclust/rdcompiler'
require 'bitclust/markdown_to_rrd'

module BitClust

  class MDCompiler < RDCompiler

    private

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
          doc_see
        when DLIST_RE
          dlist
        when MD_ITEM_RE
          @item_stack = []
          item_list(($1 || raise).size)
          raise "@item_stack should be empty. #{@item_stack.inspect}" unless @item_stack.empty?
        when FENCE_RE
          code_fence
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
        when /@todo/
          todo
        when RAW_META_RE
          entry_info
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
      f.span(%r{\A(?!\#|`{3}|- |\d+\. )\S|\A\\#})
    end

    def read_entry_paragraph(f)
      f.span(%r{\A(?!\#|`{3}|- |\d+\. |@[a-z])\S|\A\\#})
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
          line "<dt class='#{@type.to_s}-param'>[PARAM] #{escape_html($2)}:</dt>"
          rest = $3 ? ($3 || raise).sub(/\A --/, '') : +"\n"
        when /\A- \*\*raise\*\*\s+`([^`]+)`( --(?:.*))?$/m
          line "<dt>[EXCEPTION] #{escape_html($1)}:</dt>"
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

    # doc/lib ページの @see: RDCompiler の library_file には @see の解釈が
    # なく段落テキスト「@see ...」として描画される（pack_template 等）。
    # md の - **SEE** を @see 行に戻して段落として流す
    def doc_see
      header = @f.gets or raise
      body = ["@see#{header.sub(SEE_RE, '')}"] + @f.span(/\A\s+\S/)
      line '<p>'
      line compile_text(text_node_from_lines(body))
      line '</p>'
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
          # rd の dt は term を strip する（term 末尾スペースは dt に含めない）
          term = strip_code_span(($1 || raise)).strip
          inline = l.sub(DLIST_RE, '').strip
          @f.ungets("  #{inline}\n") unless inline.empty?
          line dt(compile_text(term))
        end
        dd_with_p
      end
      line '</dl>'
    end

    def strip_code_span(text)
      text.sub(/\A`(.+)`\z/, '\1')
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
        if lang == "ruby"
          begin
            filename = (caption&.size || 0) > 2 ? caption : @f.name or raise
            string BitClust::SyntaxHighlighter.new(src, filename).highlight
          rescue BitClust::SyntaxHighlighter::Error => ex
            $stderr.puts ex.message
            if stop_on_syntax_error?
              exit(false)
            else
              string src
            end
          end
        else
          string src
        end
        line '</code></pre>'
      elsif fence.size == 3
        line '<pre>'
        @f.until_terminator(terminator) do |code_line|
          line escape_html(code_line.rstrip)
        end
        line '</pre>'
      else
        lines = [] #: Array[String]
        @f.until_terminator(terminator) do |code_line|
          lines << code_line
        end
        # 変換器はベースインデント（= フェンス長 - 3）を除去して格納している。
        # RDCompiler の list は detab（タブをカラム位置で空白展開）を元の
        # カラムで行うため、ベースインデントを戻してから同じ処理を通す
        base = fence.size - 3
        lines = lines.map { |l| l =~ /\A\s*\z/ ? l : (' ' * base) + l }
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
      super(restore_rd_text(str))
    end

    def restore_rd_text(str)
      # 行頭の **N.**（離散番号の太字化）は rd の素のテキスト「N.」に戻す
      MarkdownToRRD.restore_inline(
        str.gsub(/`(__\w+__)`/, '\1').gsub(/^\*\*(\d+\.)\*\* /, '\1 ')
      )
    end
  end

end
