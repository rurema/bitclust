// QuickJS-based tests for theme/default/js/search_*.js.
// Run with: qjs test/js/test_search.mjs   (see the "test:js" rake task)
//
// search_ranker.js / search_navigation.js / search_controller.js are
// vendored verbatim from RDoc's Aliki theme and are classic (non-module,
// non-strict) scripts: evaluating them with indirect eval() attaches their
// top-level `var`/function declarations to globalThis, exactly as a
// `<script src="...">` tag would in a browser. search_init.js is BitClust's
// own wiring on top of them (also a classic script); it is exercised through
// a minimal fake DOM rather than by calling its internals directly, since
// everything in it lives inside an IIFE.
import * as std from 'std'

let failures = 0
function assert(cond, message) {
  if (cond) {
    print('ok: ' + message)
  } else {
    failures++
    print('FAIL: ' + message)
  }
}

const here = import.meta.url.replace(/^file:\/\//, '').replace(/\/[^/]*$/, '')
const jsdir = here + '/../../theme/default/js/'

// --- minimal fake DOM ---------------------------------------------------
// Just enough for SearchController/SearchNavigation/search_init.js to run:
// element creation, event listener registration + manual dispatch,
// attributes, classList and a parentNode link for `this.view`.
function makeElement(tag) {
  const listeners = {}
  return {
    tagName: (tag || 'div').toUpperCase(),
    children: [],
    parentNode: null,
    value: '',
    _attrs: {},
    _html: '',
    classList: {
      _set: new Set(),
      add(c) { this._set.add(c) },
      remove(c) { this._set.delete(c) },
      contains(c) { return this._set.has(c) },
    },
    addEventListener(type, cb) { (listeners[type] ||= []).push(cb) },
    dispatch(type, e) { (listeners[type] || []).forEach(cb => cb(e || {})) },
    setAttribute(name, v) { this._attrs[name] = String(v) },
    getAttribute(name) { return this._attrs[name] },
    appendChild(child) {
      child.parentNode = this
      this.children.push(child)
      return child
    },
    get childElementCount() { return this.children.length },
    get firstChild() { return this.children.length > 0 ? this.children[0] : null },
    set innerHTML(v) { this._html = v; this.children = [] },
    get innerHTML() { return this._html },
  }
}

function makeDocument(elementsById) {
  const listeners = {}
  return {
    addEventListener(type, cb) { (listeners[type] ||= []).push(cb) },
    dispatch(type, e) { (listeners[type] || []).forEach(cb => cb(e || {})) },
    createElement(tag) { return makeElement(tag) },
    querySelector(sel) { return elementsById[sel.replace(/^#/, '')] || null },
  }
}

// --- wire up search_init.js against the fake DOM ------------------------
// Mirrors production script order (statichtml_command.rb's SEARCH_JS_FILES).
// search_ranker.js/search_navigation.js/search_controller.js don't touch
// `document` at eval time, so they can load immediately; search_init.js
// registers its DOMContentLoaded listener as soon as it is eval'd, so a fake
// `document` must already exist before it loads.
function loadRankerScripts() {
  ['search_navigation.js', 'search_ranker.js', 'search_controller.js']
    .forEach(f => (0, eval)(std.loadFile(jsdir + f)))
}

function setupSearchBox(index) {
  const input = makeElement('input')
  const result = makeElement('ul')
  result.parentNode = makeElement('div') // SearchController reads result.parentNode as `view`
  globalThis.document = makeDocument({ 'search-field': input, 'search-results': result })
  globalThis.search_data = { index }
  globalThis.index_rel_prefix = '../'
  ;(0, eval)(std.loadFile(jsdir + 'search_init.js'))
  document.dispatch('DOMContentLoaded')
  return { input, result }
}

loadRankerScripts()

// A synthetic index: one "heading" entry (the new type this change adds --
// see rurema/doctree#2352, "defined?/undef/alias don't show up in search")
// alongside a couple of ordinary entries, to check the new type doesn't
// disturb ranking of the existing ones.
const index = [
  { name: 'defined?', full_name: 'defined? (クラス／メソッドの定義)', type: 'heading',
    path: 'doc/spec=2fdef.html#defined' },
  { name: 'undef', full_name: 'undef (クラス／メソッドの定義)', type: 'heading',
    path: 'doc/spec=2fdef.html#undef' },
  { name: 'each', full_name: 'Array#each', type: 'instance_method', path: 'method/x' },
  { name: 'Array', full_name: 'Array', type: 'class', path: 'class/-array.html' },
]

// search_ranker.js's search(): a keyword query exactly matching a heading
// entry's name should return that entry (core ranking logic is untouched
// vendored code -- this checks the new entry shape doesn't fall through it).
{
  const results = search('defined?', index)
  assert(results.length > 0 && results[0].name === 'defined?',
         'search("defined?") ranks the heading entry for spec/def.md first')
}
{
  const results = search('undef', index)
  assert(results.length > 0 && results[0].name === 'undef',
         'search("undef") ranks the heading entry for spec/def.md first')
}
// An unrelated query still finds the ordinary instance_method entry (the
// new type must not shadow existing results).
{
  const results = search('each', index)
  assert(results.length > 0 && results[0].name === 'each' && results[0].type === 'instance_method',
         'search("each") still finds the ordinary method entry')
}

// End-to-end through search_init.js's DOM wiring: typing "defined?" and
// dispatching keyup renders a result item carrying the new search-type-
// heading badge, labeled via the formatType map added in this change.
{
  const { input, result } = setupSearchBox(index)
  input.value = 'defined?'
  input.dispatch('keyup', { key: 'd' })
  assert(result.children.length > 0, 'typing a keyword renders at least one result')
  const html = result.children[0].innerHTML
  assert(html.includes('search-type-heading'), 'the result item carries the search-type-heading class')
  assert(html.includes('>section<'), 'the heading badge is labeled "section" via the formatType map')
  assert(html.includes('doc/spec=2fdef.html#defined'), 'the result links straight to the anchored heading')
}

if (failures > 0) {
  throw new Error(failures + ' JS test(s) failed')
}
print('all JS tests passed')
