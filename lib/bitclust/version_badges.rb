# frozen_string_literal: true
#
# bitclust/version_badges.rb
#
# This program is free software.
# You can distribute/modify this program under the Ruby License.
#

module BitClust

  # Renders the small "since"/"until" version badges shown next to a
  # method's signature (bitclust#132 phase P3). The version data comes from
  # MethodEntry's per-name since_map/until_map (bitclust#132 phase P2); an
  # empty map means "no badge", which keeps the output byte-identical to
  # what it was before this feature existed.
  #
  # Included by both RDCompiler (the <dt class="method-heading"> emitted
  # for RD/Markdown method pages) and TemplateScreen (the default server
  # template's method table rows), so it only relies on the `_`
  # (Translatable) and escape_html (HTMLUtils) methods that both hosts
  # already provide.
  module VersionBadges
    SINCE_CSS_CLASS = 'method-since-badge'
    UNTIL_CSS_CLASS = 'method-until-badge'
    SINCE_CATALOG_KEY = 'since Ruby %s'
    UNTIL_CATALOG_KEY = 'removed in Ruby %s'

    # HTML for the badges attached to the <dt> heading of one of +entry+'s
    # signature lines (RDCompiler#method_signature). since/until are
    # decided independently: when every one of entry's names maps to the
    # very same version, the badge is rendered once, on the first
    # signature's <dt> (+first+ true), instead of being repeated on every
    # alias's <dt>; otherwise (mixed/partial) it is looked up per +name+.
    def heading_version_badges(entry, name, first)
      name = badge_lookup_name(name)
      join_badge_spans(
        heading_badge_span(entry, name, first, entry.since_map,
                            SINCE_CSS_CLASS, SINCE_CATALOG_KEY),
        heading_badge_span(entry, name, first, entry.until_map,
                            UNTIL_CSS_CLASS, UNTIL_CATALOG_KEY)
      )
    end

    # HTML for the badges attached to a single signature line in the
    # default (server) template's method table
    # (data/bitclust/template/class). Each row already lists every alias on
    # its own line, so this always looks the version up by +name+ directly
    # -- no uniform-across-all-names aggregation, unlike heading_version_badges.
    def row_version_badges(entry, name)
      name = badge_lookup_name(name)
      join_badge_spans(
        badge_span(entry.since_map[name], SINCE_CSS_CLASS, SINCE_CATALOG_KEY),
        badge_span(entry.until_map[name], UNTIL_CSS_CLASS, UNTIL_CATALOG_KEY)
      )
    end

    private

    # シグネチャ行から取り出した名前を since_map/until_map のキーに合わせる。
    # 特殊変数のシグネチャ名は "$SAFE" のように $ 付きだが、エントリの names
    # (= マップのキー)は先頭の $ を除いた形("SAFE"。"$$" なら "$")で
    # 格納されている(rrdparser の method_signature と同じ規約)
    def badge_lookup_name(name)
      name.sub(/\A\$/, '')
    end

    def heading_badge_span(entry, name, first, map, css_class, catalog_key)
      return nil if map.empty?
      version = uniform_map?(entry, map) ? (first ? map.values.first : nil) : map[name]
      badge_span(version, css_class, catalog_key)
    end

    # Whether +map+ assigns the very same version to every one of entry's
    # names, i.e. the badge applies uniformly and doesn't need to be
    # repeated per alias.
    def uniform_map?(entry, map)
      map.size == entry.names.size && map.values.uniq.size == 1
    end

    def badge_span(version, css_class, catalog_key)
      return nil unless version
      %Q(<span class="#{css_class}">#{escape_html(_(catalog_key, version))}</span>)
    end

    def join_badge_spans(*spans)
      spans.compact.join(' ')
    end
  end
end
