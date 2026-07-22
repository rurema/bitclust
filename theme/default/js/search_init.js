'use strict';
/*
 * Part of BitClust. Distributed under the Ruby License or the MIT License.
 *
 * Wires up the client-side search box for statichtml output.
 *
 * The sibling files search_navigation.js, search_ranker.js and
 * search_controller.js are vendored verbatim from RDoc's Aliki theme.
 * They expect two globals to be defined before this script runs:
 *
 *   search_data       - defined by js/search_data.js (the index)
 *   index_rel_prefix  - relative path from the current page to the site root,
 *                       set inline in the page <head> by the layout template.
 */
(function() {
  // BitClust extension (the vendored Aliki files above are kept verbatim).
  //
  // RDoc's parseQuery() rewrites "." to "::" (its class-method separator) and
  // matches "::"/"."/"#" queries against full_name instead of name. Ruby's
  // special variables are indexed with their "$" sigil in full_name, and one of
  // them ($.) contains a literal "." — so a "$." query would become "$::" and
  // never match. Wrap parseQuery so that any "$"-prefixed (special variable)
  // query keeps its literal text and is matched against full_name.
  // See https://github.com/rurema/bitclust/issues/194
  //
  // Separately (bitclust#279): BitClust keeps a literal "." in full_name for
  // singleton methods ("File.open") and ".#"/"?." for module functions
  // ("Kernel.#open" pre-4.0, "Kernel?.open" 4.0+ — see #250), instead of
  // RDoc's "::" convention. The same "." -> "::" rewrite above then makes
  // every one of those dot-qualified queries miss its own entry. Fold "?."
  // to ".#" here so both module-function spellings collapse to the same
  // query text before the "." -> "::" rewrite runs; the other half of the
  // fix (matching against SearchIndexGenerator's match_name instead of
  // full_name) is the computeScore wrap below.
  if (typeof parseQuery === 'function') {
    var alikiParseQuery = parseQuery;
    parseQuery = function(query) {
      var folded = query.indexOf('?.') === -1 ? query : query.replace(/\?\./g, '.#');
      var q = alikiParseQuery(folded);
      if (query.charAt(0) === '$') {
        q.normalized = query.toLowerCase();  // undo the "." -> "::" rewrite
        q.matchesFullName = true;            // the "$" sigil lives in full_name
      }
      q.original = query;  // keep the real original text, not the folded one
      return q;
    };
  }

  // bitclust#279 (continued): computeScore() scores a query against
  // entry.full_name, which — per the comment above — doesn't use "::" the
  // way parseQuery's rewrite expects. SearchIndexGenerator adds a
  // match_name to affected entries (full_name with "?." folded to ".#" and
  // then every "." turned into "::", mirroring parseQuery's own rewrite —
  // see search_index_generator.rb's header comment). When an entry carries
  // one, score a shallow clone with full_name swapped to match_name instead
  // — the original entry object (and its displayed full_name) is never
  // touched, so this only affects which entries match, not what is shown.
  // Entries without a match_name (instance methods, constants, classes,
  // special variables, ...) are scored exactly as before.
  if (typeof computeScore === 'function') {
    var alikiComputeScore = computeScore;
    computeScore = function(entry, q) {
      if (entry && entry.match_name) {
        return alikiComputeScore({ name: entry.name, full_name: entry.match_name, type: entry.type }, q);
      }
      return alikiComputeScore(entry, q);
    };
  }

  // bitclust#279 (continued): highlightMatch() compares q.normalized (with
  // "." already rewritten to "::" and "?." folded to ".#" by the wrap
  // above) against the displayed full_name, which keeps its literal
  // "."/".#"/"?." — so the dot-qualified queries fixed above matched their
  // entry but never earned an <em> highlight (at best the vendored fuzzy
  // fallback gave up at the first ":"). Whenever the vendored code found
  // nothing to mark, retry a contiguous match with the user's *original*
  // query text (q.original, restored by the parseQuery wrap), treating
  // ".#" and "?." as the same module-function spelling. Both marks are two
  // characters long, so indexes into the folded strings map 1:1 onto the
  // displayed text and the markers can be spliced straight into it.
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

  function createSearchInstance(input, result) {
    if (!input || !result) return null;

    var search = new SearchController(search_data, input, result);

    search.renderItem = function(r) {
      var li = document.createElement('li');
      var html = '<p class="search-match"><a href="' +
        index_rel_prefix + this.escapeHTML(r.path) + '">' +
        this.hlt(r.title) + '</a>';
      if (r.type) {
        var typeClass = r.type.replace(/_/g, '-');
        html += '<span class="search-type search-type-' +
          this.escapeHTML(typeClass) + '">' + this.formatType(r.type) + '</span>';
      }
      html += '</p>';
      if (r.snippet) html += '<div class="search-snippet">' + r.snippet + '</div>';
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

    return search;
  }

  function hookSearch() {
    var input = document.querySelector('#search-field');
    var result = document.querySelector('#search-results');
    if (!input || !result) return;

    var search = createSearchInstance(input, result);
    if (!search) return;

    document.addEventListener('click', function(e) {
      if (!e.target.closest('#search-section')) search.hide();
    });
    document.addEventListener('keydown', function(e) {
      if (e.key === 'Escape' && input.matches(':focus')) { search.hide(); input.blur(); }
    });
    input.addEventListener('focus', function() {
      if (input.value.trim()) search.show();
    });

    if (typeof URLSearchParams !== 'undefined') {
      var q = new URLSearchParams(window.location.search).get('q');
      if (q) { input.value = q; search.search(q, false); }
    }
  }

  // Press "/" anywhere to focus the search box.
  function hookFocus() {
    document.addEventListener('keydown', function(e) {
      if (document.activeElement && document.activeElement.tagName === 'INPUT') return;
      if (e.key === '/') {
        var f = document.querySelector('#search-field');
        if (f) { e.preventDefault(); f.focus(); }
      }
    });
  }

  document.addEventListener('DOMContentLoaded', function() {
    hookSearch();
    hookFocus();
  });
})();
