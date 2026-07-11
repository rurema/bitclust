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
// script.js only assigns elem.innerHTML across elements and to a fresh
// textarea, so innerHTML is modeled as an opaque snapshot (string or
// {ownText, children}) instead of parsed HTML.
class FakeElement {
  constructor(tag, className = '', text = '') {
    this.tagName = tag.toUpperCase()
    this.className = className
    this.ownText = text
    this.children = []
    this.onclick = null
  }
  setAttribute(name, value) {
    if (name === 'class') this.className = value
  }
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

function runOnload(elements) {
  globalThis.document = makeDocument(elements)
  globalThis.window = { setTimeout() { return 0 } }
  ;(0, eval)(source)
  globalThis.window.onload()
  return elements
}

// A ruby sample keeps getting the COPY button (regression)
{
  const pre = new FakeElement('pre', 'highlight ruby')
  pre.appendChild(new FakeElement('code', '', 'puts 1\n'))
  runOnload([pre])
  assert(pre.childByClass('highlight__copy-button') !== null,
         'pre.highlight.ruby gets a COPY button')
  assert(pre.firstChild === pre.childByClass('highlight__copy-button'),
         'COPY button is prepended as the first child')
  const copyText = pre.childByClass('highlight__copy-text')
  assert(copyText !== null && copyText.textContent === 'puts 1\n',
         'copy text preserves the sample code')
}

// A plain <pre> (no language fence, //emlist{ origin) also gets the button
{
  const pre = new FakeElement('pre', '', 'ary = []\n')
  runOnload([pre])
  assert(pre.childByClass('highlight__copy-button') !== null,
         'plain <pre> without highlight class gets a COPY button')
  const copyText = pre.childByClass('highlight__copy-text')
  assert(copyText !== null && copyText.textContent === 'ary = []\n',
         'plain <pre> copy text preserves the block content')
}

// A non-ruby language fence keeps the button
{
  const pre = new FakeElement('pre', 'highlight c')
  pre.appendChild(new FakeElement('code', '', 'VALUE v;\n'))
  runOnload([pre])
  assert(pre.childByClass('highlight__copy-button') !== null,
         'pre.highlight.c gets a COPY button')
}

// Non-pre elements are left alone
{
  const div = new FakeElement('div', 'highlight')
  const pre = new FakeElement('pre', '')
  runOnload([div, pre])
  assert(div.childByClass('highlight__copy-button') === null,
         'non-pre element does not get a COPY button')
}

// The caption is excluded from the copied text
{
  const pre = new FakeElement('pre', 'highlight ruby')
  pre.appendChild(new FakeElement('span', 'caption', '例'))
  pre.appendChild(new FakeElement('code', '', 'p 42\n'))
  runOnload([pre])
  const copyText = pre.childByClass('highlight__copy-text')
  assert(copyText !== null && copyText.textContent === 'p 42\n',
         'caption text is excluded from the copy text')
  assert(pre.childByClass('caption') !== null,
         'caption itself stays visible in the sample')
}

// Leading blank lines are stripped, trailing ones squeezed to one
{
  const pre = new FakeElement('pre', '', '\n\nputs 1\n\n\n')
  runOnload([pre])
  const copyText = pre.childByClass('highlight__copy-text')
  assert(copyText !== null && copyText.textContent === 'puts 1\n',
         'copy text is trimmed (leading newlines dropped, trailing squeezed)')
}

if (failures > 0) {
  print(failures + ' failure(s)')
  std.exit(1)
}
print('all passed')
