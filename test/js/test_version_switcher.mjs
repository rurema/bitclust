// QuickJS-based tests for theme/default/js/version_switcher.js.
// Run with: qjs test/js/test_version_switcher.mjs   (see the "test:js" rake task)
//
// version_switcher.js is a classic script: evaluating it with indirect
// eval() attaches RuremaVersionSwitcher to globalThis, as a <script> tag
// would. DOM wiring is exercised through a minimal fake DOM via attach().
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

const indirectEval = eval
indirectEval(std.loadFile(jsdir + 'version_switcher.js'))

const VS = globalThis.RuremaVersionSwitcher
assert(!!VS, 'RuremaVersionSwitcher is exposed on globalThis')

// --- parsePath ----------------------------------------------------------

let p = VS.parsePath('/ja/3.4/method/Array/i/=5b=5d.html')
assert(p && p.base === '/ja/' && p.version === '3.4' &&
       p.rest === '/method/Array/i/=5b=5d.html',
       'parsePath splits a method page path')

p = VS.parsePath('/mirror/ja/latest/doc/index.html')
assert(p && p.base === '/mirror/ja/' && p.version === 'latest',
       'parsePath accepts a deep base and the latest alias')

assert(VS.parsePath('/ja/unknown/doc/index.html') === null,
       'parsePath rejects an unknown version segment')
assert(VS.parsePath('/en/3.4/method/Array/i/pop.html') === null,
       'parsePath rejects non-ja paths')
assert(VS.parsePath('/ja/3.4') === null,
       'parsePath rejects a version segment without a page path')

// --- targetUrl ----------------------------------------------------------

p = VS.parsePath('/ja/3.4/class/Array.html')
assert(VS.targetUrl(p, '2.7.0') === '/ja/2.7.0/class/Array.html',
       'targetUrl swaps only the version segment')

// --- optionVersions -----------------------------------------------------

let opts = VS.optionVersions('3.4')
assert(opts[0] === 'master', 'optionVersions puts master first')
assert(opts[1] === VS.RELEASED_VERSIONS[0],
       'optionVersions lists released versions after master')
assert(opts.indexOf('latest') === -1,
       'optionVersions omits the latest alias for a released version')
assert(opts.indexOf('3.4') !== -1, 'optionVersions contains the current version')

opts = VS.optionVersions('latest')
assert(opts[0] === 'latest', 'optionVersions prepends latest when current')

// --- resolveTarget ------------------------------------------------------
// checkExists is injected so tests control per-URL existence.

function existsFrom(map) {
  return url => Promise.resolve(url in map ? map[url] : false)
}

p = VS.parsePath('/ja/3.4/class/Set.html')

// Requested version has the page: navigate straight there.
let url = await VS.resolveTarget(p, '3.3', existsFrom({'/ja/3.3/class/Set.html': true}))
assert(url === '/ja/3.3/class/Set.html', 'resolveTarget uses the target when it exists')

// Requested version lacks the page: fall back to the newest release that has it.
url = await VS.resolveTarget(p, '1.8.7', existsFrom({
  '/ja/4.0/class/Set.html': false,
  '/ja/3.4/class/Set.html': true,
}))
assert(url === '/ja/3.4/class/Set.html',
       'resolveTarget falls back to the newest existing version')

// Existence unknown (network error): navigate to the target anyway.
url = await VS.resolveTarget(p, '2.0.0', () => Promise.resolve(null))
assert(url === '/ja/2.0.0/class/Set.html',
       'resolveTarget keeps the target when existence is unknown')

// Nothing has the page: land on the target version's root.
url = await VS.resolveTarget(p, '1.9.3', () => Promise.resolve(false))
assert(url === '/ja/1.9.3/', 'resolveTarget falls back to the version root')

// --- attach (fake DOM) --------------------------------------------------

function makeElement(tag) {
  const listeners = {}
  return {
    tagName: (tag || 'div').toUpperCase(),
    children: [],
    value: '',
    disabled: false,
    selected: false,
    textContent: '',
    _attrs: {},
    addEventListener(type, cb) { (listeners[type] ||= []).push(cb) },
    dispatch(type, e) { (listeners[type] || []).forEach(cb => cb(e || {})) },
    setAttribute(name, v) { this._attrs[name] = String(v) },
    appendChild(child) { this.children.push(child); return child },
  }
}

function makeDocument(slot) {
  return {
    createElement: makeElement,
    getElementById(id) { return id === 'version-switcher' ? slot : null },
  }
}

// No slot or unrecognized path: attach is a no-op and reports false.
assert(VS.attach({
  document: makeDocument(null),
  location: { pathname: '/ja/3.4/class/Set.html' },
  setHref() { failures++ },
  checkExists: () => Promise.resolve(true),
}) === false, 'attach without a slot is a no-op')

assert(VS.attach({
  document: makeDocument(makeElement('div')),
  location: { pathname: '/ja/search/index.html' },
  setHref() { failures++ },
  checkExists: () => Promise.resolve(true),
}) === false, 'attach outside a versioned page is a no-op')

// Local statichtml output (rake statichtml:X.Y opened via file:// or a
// local server without the /ja/<version>/ prefix): no switcher, no fetch.
assert(VS.attach({
  document: makeDocument(makeElement('div')),
  location: { pathname: '/tmp/html/3.4/class/Array.html' },
  setHref() { failures++ },
  checkExists: () => { failures++; return Promise.resolve(true) },
}) === false, 'attach on a local statichtml path is a no-op')

// Normal attachment: builds a select with the current version selected.
let slot = makeElement('div')
let navigated = []
let probed = []
const deps = {
  document: makeDocument(slot),
  location: { pathname: '/ja/3.3/class/Set.html' },
  setHref(u) { navigated.push(u) },
  checkExists(u) {
    probed.push(u)
    return Promise.resolve(!u.startsWith('/ja/1.8.7/'))
  },
}
assert(VS.attach(deps) === true, 'attach wires up on a versioned page')
const select = slot.children[0]
assert(select && select.tagName === 'SELECT', 'attach appends a select to the slot')
assert(select.value === '3.3', 'the current version is selected')
const versions = select.children.map(o => o.value)
assert(versions[0] === 'master' && versions.indexOf('1.8.7') !== -1,
       'options cover master and released versions')

// First interaction probes all other versions and disables missing ones.
select.dispatch('focus')
await Promise.resolve(); await Promise.resolve(); await Promise.resolve()
const opt187 = select.children.find(o => o.value === '1.8.7')
assert(opt187 && opt187.disabled === true, 'missing versions are disabled after probing')
const optCurrent = select.children.find(o => o.value === '3.3')
assert(optCurrent && optCurrent.disabled === false, 'the current version stays enabled')
assert(probed.every(u => !u.startsWith('/ja/3.3/')), 'the current version is not probed')

const probesAfterFirst = probed.length
select.dispatch('focus')
assert(probed.length === probesAfterFirst, 'probing happens only once')

// Changing the selection navigates to the resolved URL.
select.value = '3.0'
select.dispatch('change')
await Promise.resolve(); await Promise.resolve(); await Promise.resolve()
assert(navigated.length === 1 && navigated[0] === '/ja/3.0/class/Set.html',
       'changing the selection navigates to the same page in that version')

print(failures === 0 ? 'ALL OK' : failures + ' failure(s)')
if (failures > 0) std.exit(1)
