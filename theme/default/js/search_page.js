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
  //
  // Same bitclust#279 handling as search_init.js too: fold "?." to ".#" so
  // both module-function spellings ("Kernel.#open" pre-4.0, "Kernel?.open"
  // 4.0+ — see #250) normalize the same way, and score dot-qualified
  // entries via their match_name (added by SearchIndexGenerator) instead of
  // full_name, since BitClust keeps a literal "." there for display while
  // parseQuery's rewrite expects "::". See search_init.js for the full
  // rationale; SearchIndexGenerator.merge keeps match_name on merged
  // cross-version entries same as any other field.
  if (typeof parseQuery === 'function') {
    var alikiParseQuery = parseQuery;
    parseQuery = function(query) {
      var folded = query.indexOf('?.') === -1 ? query : query.replace(/\?\./g, '.#');
      var q = alikiParseQuery(folded);
      if (query.charAt(0) === '$') {
        q.normalized = query.toLowerCase();
        q.matchesFullName = true;
      }
      q.original = query;
      return q;
    };
  }

  if (typeof computeScore === 'function') {
    var alikiComputeScore = computeScore;
    computeScore = function(entry, q) {
      if (entry && entry.match_name) {
        return alikiComputeScore({ name: entry.name, full_name: entry.match_name, type: entry.type }, q);
      }
      return alikiComputeScore(entry, q);
    };
  }

  // Same highlightMatch wrap as search_init.js: when the vendored code
  // found nothing to mark (dot-qualified queries never contiguous-match a
  // literal-dot full_name once "." has been rewritten to "::"), retry with
  // the user's original query text, treating ".#" and "?." as the same
  // module-function spelling. On this page the merged index only carries
  // the "?." spelling (SearchIndexGenerator.merge folds ".#" away), so
  // this is what lets a query typed in the pre-4.0 ".#" notation still
  // light up the "?."-spelled row it matched. Both marks are two
  // characters, so indexes into the folded strings map 1:1 onto the text.
  if (typeof highlightMatch === 'function') {
    var alikiHighlightMatch = highlightMatch;
    highlightMatch = function(text, q) {
      var marked = alikiHighlightMatch(text, q);
      if (marked !== text) return marked;         // the vendored code managed
      if (!text || !q || !q.original) return marked;
      var canonText = text.toLowerCase().replace(/\.#/g, '?.');
      var canonQuery = q.original.toLowerCase().replace(/\.#/g, '?.');
      if (!canonQuery) return marked;
      var start = canonText.indexOf(canonQuery);
      if (start === -1) return marked;
      var end = start + canonQuery.length;
      return text.substring(0, start) +
        '\u0001' + text.substring(start, end) + '\u0002' +
        text.substring(end);
    };
  }

  function versionHref(version, path) {
    return search_version_base + version + '/' + path;
  }

  function compareVersions(a, b) {
    var as = a.split('.');
    var bs = b.split('.');
    for (var i = 0; i < Math.max(as.length, bs.length); i++) {
      var d = parseInt(as[i] || '0', 10) - parseInt(bs[i] || '0', 10);
      if (d) return d;
    }
    return 0;
  }

  // ranker の formatResult は {title, path, type} だけを結果に残し、統合 index の
  // versions を落とす（vendored ファイルは verbatim 維持）。path から versions を
  // 引けるよう対応表を作る。同じ path が複数エントリに現れる稀なケース
  // （版によって type 等が違う）は、ページとしては存在する版の和集合が正しい
  function buildVersionsByPath() {
    var map = {};
    for (var i = 0; i < search_data.index.length; i++) {
      var e = search_data.index[i];
      var list = map[e.path] || (map[e.path] = []);
      var vs = e.versions || [];
      for (var j = 0; j < vs.length; j++) {
        if (list.indexOf(vs[j]) < 0) list.push(vs[j]);
      }
    }
    return map;
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
    var versionsByPath = buildVersionsByPath();

    search.renderItem = function(r) {
      var li = document.createElement('li');
      var versions = (versionsByPath[r.path] || [])
        .slice().sort(compareVersions).reverse();  // newest first
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
        'variable': 'var', 'library': 'lib', 'document': 'doc', 'function': 'func',
        'heading': 'section'
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
