# frozen_string_literal: true

require 'bitclust/nameutils'

module BitClust

  # statichtml の --markdown-output 用に、HTML の各ページと対になる Markdown を
  # エントリの前処理済みソース(Markdown ツリー由来の md)から組み立てる。
  # 参照記法(単一ブラケットの [m:...] 等と、参照 scheme を宛先にした
  # ラベル付きリンク)は相対 .md リンクへ解決する。解決できない参照
  # (未対応の種別・不正な指定)はそのまま残し、エラーにしない。
  # コードスパンとコードフェンスの中は変換しない。
  class MarkdownExporter

    # クラスページの メソッド種別 → セクション見出し(doctree の md と同じ名称)
    CLASS_SECTIONS = [
      ["Class Methods",              :public,    :singleton_method],
      ["Instance Methods",           :public,    :instance_method],
      ["Private Class Methods",      :private,   :singleton_method],
      ["Private Instance Methods",   :private,   :instance_method],
      ["Protected Instance Methods", :protected, :instance_method],
      ["Module Functions",           :public,    :module_function],
      ["Constants",                  :public,    :constant],
      ["Special Variables",          :public,    :special_variable],
    ].freeze

    def initialize(urlmapper, html_suffix)
      @urlmapper = urlmapper
      @html_suffix = html_suffix
    end

    def library_page(entry)
      page("# library #{entry.name}", entry.source)
    end

    # クラスページは HTML と同じく本文+メソッドリンク一覧(本文は載せない)
    def class_page(entry)
      out = +""
      CLASS_SECTIONS.each do |section, visibility, type|
        methods = entry.entries.select { |m|
          !m.undefined? && m.type == type && m.visibility == visibility
        }
        next if methods.empty?
        out << "\n## #{section}\n\n"
        methods.each do |m|
          m.names.each do |name|
            spec = m.klass.name + m.typemark + name
            url = ref_url('m', spec)
            out << (url ? "- [#{escape_label(name)}](#{url})\n" : "- #{escape_label(name)}\n")
          end
        end
      end
      page(class_heading(entry), entry.source, out)
    end

    def method_page(method_name, entries)
      out = +"# #{method_name.sub('.#', '?.')}\n"
      entries.each do |m|
        body = m.source.strip
        out << "\n" << convert_text(body) << "\n" unless body.empty?
      end
      out
    end

    def doc_page(entry)
      page("# #{entry.title}", entry.source)
    end

    def function_page(entry)
      page("# #{entry.name}", "### #{entry.header}\n#{entry.source}")
    end

    # 本文中の参照をコードスパン・コードフェンスを避けて相対 .md リンクへ
    # 変換する
    def convert_text(str)
      out = +''
      fence = nil
      str.each_line do |line|
        if fence
          out << line
          stripped = line.strip
          fence = nil if stripped.match?(/\A`+\z/) && stripped.length >= (fence || 0)
        elsif (m = /\A {0,3}(`{3,})/.match(line))
          fence = (m[1] || raise).length
          out << line
        else
          out << convert_line(line)
        end
      end
      out
    end

    private

    def page(heading, source, trailer = "")
      out = +"#{heading}\n"
      body = source.strip
      out << "\n" << convert_text(body) << "\n" unless body.empty?
      out << trailer
      out
    end

    def class_heading(entry)
      case entry.type
      when :class
        sc = entry.superclass
        sc ? "# class #{entry.name} < #{sc.name}" : "# class #{entry.name}"
      when :module
        "# module #{entry.name}"
      when :object
        "# object #{entry.name}"
      else
        "# #{entry.name}"
      end
    end

    def convert_line(line)
      spans = [] #: Array[String]
      converted = convert_refs(extract_code_spans(line, spans))
      converted.gsub(/\x00(\d+)\x00/) { spans[($1 || raise).to_i] || raise }
    end

    # インラインコードスパン(CommonMark 6.1、N 連バッククォートの同長
    # ペアリング)を書かれたままプレースホルダへ退避する
    def extract_code_spans(str, saved)
      result = +''
      i = 0
      len = str.length
      while i < len
        c = str[i] or raise
        if c == '\\' && i + 1 < len
          result << (str[i, 2] || raise)
          i += 2
          next
        end
        if c == '`'
          run = 1
          run += 1 while str[i + run] == '`'
          close = find_code_span_close(str, i + run, run)
          if close
            saved << (str[i...(close + run)] || raise)
            result << "\x00#{saved.size - 1}\x00"
            i = close + run
            next
          end
          result << ('`' * run)
          i += run
          next
        end
        result << c
        i += 1
      end
      result
    end

    def find_code_span_close(str, from, run_len)
      i = from
      len = str.length
      while i < len
        case str[i]
        when "\n"
          return nil
        when '`'
          j = i
          j += 1 while str[j] == '`'
          return i if j - i == run_len
          i = j
        else
          i += 1
        end
      end
      nil
    end

    REF_SCHEME_RE = /\A([a-zA-Z][a-zA-Z-]*):(.*)\z/m

    def convert_refs(str)
      result = +''
      i = 0
      while i < str.length
        if str[i] == '\\' && i + 1 < str.length
          result << (str[i, 2] || raise)
          i += 2
          next
        end
        if str[i] == '['
          close = matching_delimiter(str, i, '[', ']')
          if close
            if str[close + 1] == '(' &&
               (dest_end = matching_delimiter(str, close + 1, '(', ')', space_ends: true)) &&
               (dest = str[(close + 2)...dest_end])
              # ラベル付きリンク [text](dest)
              if (m = REF_SCHEME_RE.match(dest)) && (url = ref_url(m[1] || raise, m[2] || raise))
                result << "[#{str[(i + 1)...close]}](#{url})"
                i = dest_end + 1
                next
              end
              if dest.start_with?('#') || dest.match?(%r{\Ahttps?://})
                # 通常の Markdown リンクはそのまま(ラベル内は再解釈しない)
                result << (str[i..dest_end] || raise)
                i = dest_end + 1
                next
              end
            end
            # 単一ブラケット参照 [type:target]([[ は除外)
            inner = str[(i + 1)...close] || raise
            if str[i + 1] != '[' && (m = REF_SCHEME_RE.match(inner)) &&
               (converted = bare_ref(m[1] || raise, m[2] || raise, inner))
              result << converted
              i = close + 1
              next
            end
          end
        end
        result << (str[i] || raise)
        i += 1
      end
      result
    end

    # open 位置の括弧に対応する閉じ括弧の位置(\ エスケープ対応・ネスト可)。
    # space_ends: リンク宛先用。空白が現れたらリンクではない(nil)
    def matching_delimiter(str, open, open_char, close_char, space_ends: false)
      depth = 0
      i = open
      while i < str.length
        c = str[i]
        if c == '\\'
          i += 1
        elsif space_ends && c =~ /\s/
          return nil
        elsif c == open_char
          depth += 1
        elsif c == close_char
          depth -= 1
          return i if depth == 0
        end
        i += 1
      end
      nil
    end

    # 単一ブラケット参照 1 個を Markdown リンクにする。ラベルは書かれた
    # ままの形(エスケープ込み)から type: を落としたもの
    def bare_ref(type, arg, written)
      label =
        case type
        when 'm', 'c', 'lib', 'd', 'f'
          written.split(':', 2)[1]
        when 'url'
          arg
        when 'ref'
          case arg
          when /\A(\w+):(.*)\#([-\w]+)\z/
            "#{$2}##{$3}"
          when /\A[-\w]+\z/
            arg
          end
        end
      return nil unless label
      url = ref_url(type, arg)
      return nil unless url
      "[#{label}](#{url})"
    end

    # 参照 scheme の宛先 URL(.md への相対リンク)。解決できなければ nil
    def ref_url(type, arg)
      arg = unescape_md_brackets(arg)
      case type
      when 'm'
        # md 表記の module function ?. は内部表記 .# に正規化して引く
        md_suffix(@urlmapper.method_url(arg.sub('?.', '.#')))
      when 'c'
        md_suffix(@urlmapper.class_url(arg))
      when 'lib'
        md_suffix(@urlmapper.library_url(arg))
      when 'd'
        md_suffix(@urlmapper.document_url(arg))
      when 'f'
        md_suffix(@urlmapper.function_url(arg))
      when 'url'
        arg
      when 'ref'
        case arg
        when /\A(\w+):(.*)\#([-\w]+)\z/
          url = ref_url($1 || raise, $2 || raise)
          url ? "#{url}##{$3}" : nil
        when /\A[-\w]+\z/
          "##{arg}"
        end
      end
    rescue StandardError
      nil
    end

    def md_suffix(html_url)
      return html_url unless html_url.end_with?(@html_suffix)
      "#{html_url[0, html_url.length - @html_suffix.length]}.md"
    end

    def unescape_md_brackets(str)
      str.gsub(/\\([\[\]\\])/, '\1')
    end

    def escape_label(text)
      text.gsub(/[\\\[\]]/) { "\\#{$&}" }
    end

  end

end
