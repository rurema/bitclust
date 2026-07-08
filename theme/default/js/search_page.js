'use strict';
/*
 * Part of BitClust. Distributed under the Ruby License or the MIT License.
 *
 * Wires up the standalone cross-version search page (the static replacement
 * for the server-backed rurema-search app at /ja/search/).
 *
 * The sibling files search_navigation.js, search_ranker.js and
 * search_controller.js are vendored verbatim from RDoc's Aliki theme.
 * They expect these globals to be defined before this script runs:
 *
 *   search_data         - defined by js/search_data.js. Each entry carries a
 *                         `versions` array (ascending) added by
 *                         SearchIndexGenerator.merge.
 *   search_versions     - all indexed versions, ascending (inline in the page).
 *   search_version_base - relative path from this page to the directory that
 *                         holds the per-version document roots ("../" when the
 *                         page lives at /ja/search/).
 */
(function() {
  // BitClust extension (the vendored Aliki files above are kept verbatim).
  //
  // Same special-variable handling as search_init.js: keep "$"-prefixed
  // queries literal (no "." -> "::" rewrite) and match them against
  // full_name, where the "$" sigil lives.
  // See https://github.com/rurema/bitclust/issues/194
  if (typeof parseQuery === 'function') {
    var alikiParseQuery = parseQuery;
    parseQuery = function(query) {
      var q = alikiParseQuery(query);
      if (query.charAt(0) === '$') {
        q.normalized = query.toLowerCase();
        q.matchesFullName = true;
      }
      return q;
    };
  }

  function versionHref(version, path) {
    return search_version_base + version + '/' + path;
  }

  // rurema-search compatibility: accept ?q=, its ?query= parameter, and its
  // /query:<word>/ path form (the latter only reaches this page when the
  // server rewrites unknown /ja/search/* paths here).
  function initialQuery() {
    var q = null;
    if (typeof URLSearchParams !== 'undefined') {
      var params = new URLSearchParams(window.location.search);
      q = params.get('q') || params.get('query');
    }
    if (!q) {
      var m = window.location.pathname.match(/\/query:([^\/]+)/);
      if (m) {
        try {
          q = decodeURIComponent(m[1]);
        } catch (e) {
          q = m[1];
        }
      }
    }
    return q;
  }

  function init() {
    var input = document.querySelector('#search-field');
    var result = document.querySelector('#search-results');
    if (!input || !result) return;

    var search = new SearchController(search_data, input, result);

    search.renderItem = function(r) {
      var li = document.createElement('li');
      var versions = (r.versions || []).slice().reverse();  // newest first
      var newest = versions[0] || '';
      var html = '<p class="search-match"><a href="' +
        this.escapeHTML(versionHref(newest, r.path)) + '">' +
        this.hlt(r.title) + '</a>';
      if (r.type) {
        var typeClass = r.type.replace(/_/g, '-');
        html += '<span class="search-type search-type-' +
          this.escapeHTML(typeClass) + '">' + this.formatType(r.type) + '</span>';
      }
      html += '</p><p class="search-versions">';
      for (var i = 0; i < versions.length; i++) {
        html += '<a href="' + this.escapeHTML(versionHref(versions[i], r.path)) +
          '">' + this.escapeHTML(versions[i]) + '</a>';
      }
      html += '</p>';
      li.innerHTML = html;
      return li;
    };

    search.formatType = function(type) {
      var labels = {
        'class': 'class', 'module': 'module', 'object': 'object',
        'constant': 'const', 'instance_method': 'method', 'class_method': 'method',
        'variable': 'var', 'library': 'lib', 'document': 'doc', 'function': 'func'
      };
      return labels[type] || type;
    };

    search.select = function(selected) {
      if (selected) window.location.href = selected.firstChild.firstChild.href;
    };

    // Keep the query shareable: mirror the box into the ?q= parameter.
    input.addEventListener('input', function() {
      var q = input.value.trim();
      var url = q ? '?q=' + encodeURIComponent(q) : window.location.pathname;
      window.history.replaceState(null, '', url);
    });

    var q = initialQuery();
    if (q) {
      input.value = q;
      window.history.replaceState(null, '', '?q=' + encodeURIComponent(q));
      search.search(q, false);
    }
    input.focus();
  }

  document.addEventListener('DOMContentLoaded', init);
})();
