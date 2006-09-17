#
# bitclust/htmlutils.rb
#
# Copyright (C) 2006 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the Ruby License.
#

module BitClust

  module HTMLUtils

    private

    def library_link(id, label = nil)
      a_href(@urlmapper.library_url(id), label || id)
    rescue LibraryNotFound
      escape_html(label || id)
    end

    def class_link(id, label = nil)
      a_href(@urlmapper.class_url(id), label || id)
    rescue ClassNotFound
      escape_html(label || id)
    end

    def method_link_short(m)
      a_href(@urlmapper.method_url(m.klass.name, m.typemark, m.name), m.name)
    rescue MethodNotFound
      escape_html(id)
    end

    def method_link(id, label = nil)
      if m = /\A([\w\:]+)(\.\#|[\.\#]|::)([^:\s]+)\z/.match(id)
        a_href(@urlmapper.method_url($1, $2, $3), (label || id))
      elsif m = /\A\$(\w+|\-.|.)\z/.match(id)
        a_href(@urlmapper.method_url('Kernel', '$', $1), (label || id))
      else
        escape_html(label || id)
      end
    rescue MethodNotFound
      escape_html(id)
    end

    def a_href(url, label)
      %Q(<a href="#{url}">#{escape_html(label)}</a>)
    end

    ESC = {
      '&' => '&amp;',
      '"' => '&quot;',
      '<' => '&lt;',
      '>' => '&gt;'
    }

    def escape_html(str)
      table = ESC   # optimize
      str.gsub(/[&"<>]/) {|s| table[s] }
    end

    ESCrev = ESC.invert

    def unescape_html(str)
      table = ESCrev   # optimize
      str.gsub(/&\w+;/) {|s| table[s] }
    end

  end

end
