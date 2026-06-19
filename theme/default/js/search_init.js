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
        'variable': 'var', 'library': 'lib', 'document': 'doc', 'function': 'func'
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
