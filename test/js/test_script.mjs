// QuickJS-based tests for theme/default/script.js (COPY button setup).
// Run with: qjs test/js/test_script.mjs   (see the "test:js" rake task)
// script.js is a classic (non-module) script, so it is evaluated with eval()
// against a minimal fake DOM defined on globalThis.
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

// --- minimal fake DOM -------------------------------------------------
// script.js only assigns elem.innerHTML across elements, so innerHTML is
// modeled as an opaque snapshot (string or {ownText, children}) instead of
// parsed HTML.
class FakeElement {
  constructor(tag, className = '', text = '') {
    this.tagName = tag.toUpperCase()
    this.className = className
    this.ownText = text
    this.children = []
    this.onclick = null
    this.value = ''
    const classes = new Set()
    this.classList = {
      add(c) { classes.add(c) },
      remove(c) { classes.delete(c) },
      contains(c) { return classes.has(c) },
    }
  }
  setAttribute(name, value) {
    if (name === 'class') this.className = value
  }
  select() {}
  appendChild(child) {
    this.children.push(child)
    return child
  }
  insertBefore(child, ref) {
    const i = this.children.indexOf(ref)
    if (ref == null || i < 0) this.children.push(child)
    else this.children.splice(i, 0, child)
    return child
  }
  removeChild(child) {
    const i = this.children.indexOf(child)
    if (i >= 0) this.children.splice(i, 1)
    return child
  }
  get firstChild() {
    return this.children.length > 0 ? this.children[0] : null
  }
  get textContent() {
    return this.ownText + this.children.map(c => c.textContent).join('')
  }
  get innerHTML() {
    return { ownText: this.ownText, children: this.children.slice() }
  }
  set innerHTML(value) {
    if (typeof value === 'string') {
      this.ownText = value
      this.children = []
    } else {
      this.ownText = value.ownText
      this.children = value.children.slice()
    }
  }
  getElementsByClassName(name) {
    const found = []
    const walk = (el) => {
      for (const c of el.children) {
        if (c.className.split(' ').indexOf(name) >= 0) found.push(c)
        walk(c)
      }
    }
    walk(this)
    return found
  }
  classesOfChildren() {
    return this.children.map(c => c.className)
  }
  childByClass(name) {
    return this.children.find(c => c.className.split(' ').indexOf(name) >= 0) || null
  }
}

function makeDocument(elements) {
  return {
    _elements: elements,
    body: new FakeElement('body'),
    createElement(tag) { return new FakeElement(tag) },
    getElementsByClassName(name) {
      return this._elements.filter(e => e.className.split(' ').indexOf(name) >= 0)
    },
    querySelectorAll(selector) {
      return this._elements.filter(e => e.tagName === selector.toUpperCase())
    },
    execCommand() { return true },
  }
}

// --- load script.js against the fake DOM ------------------------------
const here = import.meta.url.replace(/^file:\/\//, '').replace(/\/[^/]*$/, '')
const source = std.loadFile(here + '/../../theme/default/script.js')

function runOnload(elements, navigatorFake) {
  globalThis.document = makeDocument(elements)
  globalThis.window = { setTimeout() { return 0 } }
  globalThis.navigator = navigatorFake || {}
  ;(0, eval)(source)
  globalThis.window.onload()
  return elements
}

// Clipboard API を捕捉する navigator フェイク
function clipboardSpy() {
  const written = []
  return {
    written,
    navigator: {
      clipboard: {
        writeText(text) {
          written.push(text)
          return Promise.resolve()
        },
      },
    },
  }
}

// クリックの Promise 連鎖(writeClipboard().then)を流すための待ち
async function settle() {
  await 0
  await 0
}

// A ruby sample keeps getting the COPY button (regression)
{
  const spy = clipboardSpy()
  const pre = new FakeElement('pre', 'highlight ruby')
  pre.appendChild(new FakeElement('code', '', 'puts 1\n'))
  runOnload([pre], spy.navigator)
  const btn = pre.childByClass('highlight__copy-button')
  assert(btn !== null, 'pre.highlight.ruby gets a COPY button')
  assert(pre.firstChild === btn, 'COPY button is prepended as the first child')
  btn.onclick()
  await settle()
  assert(spy.written.length === 1 && spy.written[0] === 'puts 1\n',
         'clicking COPY writes the sample code via the Clipboard API')
  assert(btn.classList.contains('copied'),
         'the copied indicator is shown after a successful write')
}

// A plain <pre> (no language fence, //emlist{ origin) also gets the button
{
  const spy = clipboardSpy()
  const pre = new FakeElement('pre', '', 'ary = []\n')
  runOnload([pre], spy.navigator)
  const btn = pre.childByClass('highlight__copy-button')
  assert(btn !== null, 'plain <pre> without highlight class gets a COPY button')
  btn.onclick()
  await settle()
  assert(spy.written[0] === 'ary = []\n',
         'plain <pre> copy writes the block content')
}

// A non-ruby language fence keeps the button
{
  const pre = new FakeElement('pre', 'highlight c')
  pre.appendChild(new FakeElement('code', '', 'VALUE v;\n'))
  runOnload([pre], clipboardSpy().navigator)
  assert(pre.childByClass('highlight__copy-button') !== null,
         'pre.highlight.c gets a COPY button')
}

// Non-pre elements are left alone
{
  const div = new FakeElement('div', 'highlight')
  const pre = new FakeElement('pre', '')
  runOnload([div, pre], clipboardSpy().navigator)
  assert(div.childByClass('highlight__copy-button') === null,
         'non-pre element does not get a COPY button')
}

// The caption is excluded from the copied text
{
  const spy = clipboardSpy()
  const pre = new FakeElement('pre', 'highlight ruby')
  pre.appendChild(new FakeElement('span', 'caption', '例'))
  pre.appendChild(new FakeElement('code', '', 'p 42\n'))
  runOnload([pre], spy.navigator)
  pre.childByClass('highlight__copy-button').onclick()
  await settle()
  assert(spy.written[0] === 'p 42\n',
         'caption text is excluded from the copied text')
  assert(pre.childByClass('caption') !== null,
         'caption itself stays visible in the sample')
}

// Leading blank lines are stripped, trailing ones squeezed to one
{
  const spy = clipboardSpy()
  const pre = new FakeElement('pre', '', '\n\nputs 1\n\n\n')
  runOnload([pre], spy.navigator)
  pre.childByClass('highlight__copy-button').onclick()
  await settle()
  assert(spy.written[0] === 'puts 1\n',
         'copied text is trimmed (leading newlines dropped, trailing squeezed)')
}

// Clipboard API が無い環境では textarea + execCommand にフォールバックする
{
  const pre = new FakeElement('pre', '', 'fallback code\n')
  const elements = [pre]
  globalThis.document = makeDocument(elements)
  let captured = null
  globalThis.document.execCommand = function (command) {
    if (command === 'copy') {
      const ta = globalThis.document.body.children.find(c => c.tagName === 'TEXTAREA')
      captured = ta ? ta.value : null
    }
    return true
  }
  globalThis.window = { setTimeout() { return 0 } }
  globalThis.navigator = {}   // clipboard なし
  ;(0, eval)(source)
  globalThis.window.onload()
  const btn = pre.childByClass('highlight__copy-button')
  btn.onclick()
  await settle()
  assert(captured === 'fallback code\n',
         'without the Clipboard API the text is copied via textarea + execCommand')
  assert(globalThis.document.body.children.length === 0,
         'the fallback textarea is removed after copying')
  assert(btn.classList.contains('copied'),
         'the copied indicator is shown for the fallback path too')
}

if (failures > 0) {
  print(failures + ' failure(s)')
  std.exit(1)
}
print('all passed')
