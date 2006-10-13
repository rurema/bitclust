#
# bitclust/textutils
#
# Copyright (c) 2006 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the Ruby License.
#

module BitClust

  module TextUtils

    module_function

    def detab(str, ts = 8)
      add = 0
      str.gsub(/\t/) {
        len = ts - ($~.begin(0) + add) % ts
        add += len - 1
        ' ' * len
      }
    end

    def unindent_block(lines)
      n = n_minimum_indent(lines)
      lines.map {|line| unindent(line, n) }
    end

    def n_minimum_indent(lines)
      lines.reject {|line| line.strip.empty? }.map {|line| n_indent(line) }.min
    end

    def n_indent(line)
      line.slice(/\A\s*/).size
    end

    INDENT_RE = {
      2 => /\A {2}/,
      4 => /\A {4}/,
      8 => /\A {8}/
    }

    def unindent(line, n)
      re = (INDENT_RE[n] ||= /\A {#{n}}/)
      line.sub(re, '')
    end

  end

end
