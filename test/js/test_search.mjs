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

// A synthetic index mirroring what SearchIndexGenerator actually emits for
// dot-qualified class methods/module functions (see search_index_generator.rb
// and bitclust#279): singleton methods and module functions carry a
// match_name alongside their literal-dot full_name; everything else doesn't.
// Kernel.#open/Kernel?.open both appear here (same path, different spelling)
// the way SearchIndexGenerator.merge's cross-version index can legitimately
// hold both -- pre-4.0 runs emit ".#", 4.0+ runs emit "?." (bitclust#250),
// and merge's dedup key includes full_name, so they don't collapse into one.
const qualifiedIndex = [
  { name: 'open', full_name: 'File.open', match_name: 'File::open',
    type: 'class_method', path: 'method/-file/s/open.html' },
  { name: 'open', full_name: 'Dir.open', match_name: 'Dir::open',
    type: 'class_method', path: 'method/-dir/s/open.html' },
  { name: 'open', full_name: 'Kernel.#open', match_name: 'Kernel::#open',
    type: 'class_method', path: 'method/-kernel/m/open.html' },
  { name: 'open', full_name: 'Kernel?.open', match_name: 'Kernel::#open',
    type: 'class_method', path: 'method/-kernel/m/open.html' },
  { name: 'size', full_name: 'String#size', type: 'instance_method',
    path: 'method/-string/i/size.html' },
  { name: 'HTTP', full_name: 'Net::HTTP', type: 'class', path: 'class/-net-2-1http.html' },
]

// Root-cause check: against the *pristine, unpatched* vendored ranker (no
// search_init.js has been eval'd yet -- that only happens via setupSearchBox
// below), every dot-qualified query below misses its own entry outright.
// parseQuery() rewrites every "." in the query to "::" (RDoc's class-method
// separator), but these full_names keep a literal "."/".#"/"?." for display,
// so nothing matches. This is the bug bitclust#279 is about; the assertions
// further down show it fixed once search_init.js's patch is loaded.
{
  assert(search('File.open', qualifiedIndex).length === 0,
         '(pre-patch) "File.open" matches nothing against the unpatched vendored ranker -- the bug')
  assert(search('Kernel.#open', qualifiedIndex).length === 0,
         '(pre-patch) "Kernel.#open" matches nothing against the unpatched vendored ranker -- the bug')
  assert(search('Kernel?.open', qualifiedIndex).length === 0,
         '(pre-patch) "Kernel?.open" matches nothing against the unpatched vendored ranker -- the bug')
}

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

// --- bitclust#279: qualified-query fix, now that search_init.js's patch is
// loaded (the setupSearchBox() call above already eval'd it once) ---------

// parseQuery(): "?." folds to ".#" before the vendored "." -> "::" rewrite,
// and q.original keeps the *real* original text, not the folded one.
{
  const q = parseQuery('Kernel?.open')
  assert(q.normalized === 'kernel::#open', 'parseQuery folds "?." to ".#" before the "." -> "::" rewrite')
  assert(q.original === 'Kernel?.open', 'parseQuery.original keeps the real original text, not the folded one')
}

// The three previously-dead queries now match their own entry.
{
  const r = search('File.open', qualifiedIndex)
  assert(r.length === 1 && r[0].full_name === 'File.open',
         '(post-patch) "File.open" matches File.open, and only File.open (not the Dir.open decoy)')
}
{
  const r = search('Kernel.#open', qualifiedIndex)
  assert(r.some(e => e.full_name === 'Kernel.#open'), '(post-patch) "Kernel.#open" matches the ".#"-spelled entry')
  assert(r.some(e => e.full_name === 'Kernel?.open'),
         '(post-patch) "Kernel.#open" also matches the "?."-spelled entry (cross-notation, bitclust#250)')
}
{
  const r = search('Kernel?.open', qualifiedIndex)
  assert(r.some(e => e.full_name === 'Kernel.#open'),
         '(post-patch) "Kernel?.open" also matches the ".#"-spelled entry (cross-notation)')
  assert(r.some(e => e.full_name === 'Kernel?.open'), '(post-patch) "Kernel?.open" matches the "?."-spelled entry')
}

// Display safety: the entries search() returns are the *original* qualifiedIndex
// objects, untouched -- full_name is never rewritten to the "::" match_name form.
{
  const r = search('File.open', qualifiedIndex)
  assert(r.length === 1 && r[0] === qualifiedIndex[0],
         'the returned entry is the original object (identity), not a patched clone')
  assert(r.length === 1 && r[0].full_name === 'File.open' && !r[0].full_name.includes('::'),
         'the returned entry\'s full_name is unchanged ("File.open", not "File::open")')
}

// Controls: queries that were never affected by the bug keep working.
{
  const r = search('String#size', qualifiedIndex)
  assert(r.length === 1 && r[0].full_name === 'String#size', '"#"-qualified instance-method queries are unaffected')
}
{
  const r = search('Net::HTTP', qualifiedIndex)
  assert(r.length === 1 && r[0].full_name === 'Net::HTTP', '"::"-qualified constant/namespace queries are unaffected')
}
{
  const r = search('open', qualifiedIndex)
  assert(r.length === 4, 'the unqualified "open" query still finds all four entries by name, as before')
}

// End-to-end through the DOM, same as the "defined?" test above: typing a
// dot-qualified query renders a result whose *displayed* title is the
// original "File.open" -- proving the match_name substitution never reaches
// the page (highlightMatch degrades to no inline <em> marks for this query
// shape, a known/documented limitation -- see the #279 report -- but the
// text itself must still be exactly right and HTML-escaped normally).
{
  const { input, result } = setupSearchBox(qualifiedIndex)
  input.value = 'File.open'
  input.dispatch('keyup', { key: 'n' })
  assert(result.children.length > 0, 'typing "File.open" renders a result (was 0 before the fix)')
  const html = result.children[0].innerHTML
  assert(html.includes('>File.open<') || html.includes('File.open</a>') || /File\.open/.test(html),
         'the rendered result displays the literal "File.open" full_name')
  assert(!html.includes('File::open'), 'the rendered result never shows the "::" match_name form')
  assert(html.includes('method/-file/s/open.html'), 'the result links to the right path')
}

// --- bitclust#279: defensive fallback ------------------------------------
// search_init.js's parseQuery/computeScore wraps are guarded by
// `typeof X === 'function'`. Simulate a hypothetical future Aliki ranker
// that no longer exposes them as bare globals (e.g. hidden inside a
// closure/module) but still honors the same public SearchRanker contract
// (new SearchRanker(index), .ready(fn), .find(query)) with its own
// self-contained matching. Loading search_init.js against that must not
// throw, and ordinary (unqualified) search must keep working through
// whatever the "new" ranker provides on its own -- i.e. bitclust#279's
// enhancement degrades to today's (pre-fix) behavior instead of crashing
// the whole search box.
{
  parseQuery = undefined
  computeScore = undefined
  assert(typeof parseQuery !== 'function' && typeof computeScore !== 'function',
         '(fallback setup) parseQuery/computeScore are hidden, simulating a future closure-based ranker')

  // A closure-hiding stand-in ranker: same public shape as SearchRanker, but
  // its matching logic never touches globalThis.
  ;(function() {
    function stubMatch(entry, normalizedQuery) {
      return entry.name.toLowerCase().indexOf(normalizedQuery) !== -1
    }
    globalThis.SearchRanker = function(idx) {
      this.index = idx
      this.handlers = []
    }
    globalThis.SearchRanker.prototype.ready = function(fn) { this.handlers.push(fn) }
    globalThis.SearchRanker.prototype.find = function(query) {
      const nq = query.toLowerCase()
      const results = this.index
        .filter(e => stubMatch(e, nq))
        .map(e => ({ title: e.full_name, path: e.path, type: e.type }))
      this.handlers.forEach(fn => fn(results, true))
    }
  })()

  let threw = false
  let box = null
  try {
    box = setupSearchBox(qualifiedIndex)
  } catch (e) {
    threw = true
    print('unexpected throw while loading search_init.js: ' + e)
  }
  assert(!threw, 'search_init.js does not throw when parseQuery/computeScore are absent from globalThis')

  if (box) {
    box.input.value = 'open'
    box.input.dispatch('keyup', { key: 'n' })
    assert(box.result.children.length > 0,
           'unqualified search still works end-to-end through the stand-in ranker when the patch cannot attach')
  }
}

if (failures > 0) {
  throw new Error(failures + ' JS test(s) failed')
}
print('all JS tests passed')
