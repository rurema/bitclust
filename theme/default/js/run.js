// RUN button for Ruby sample code: executes the sample in-browser with
// ruby.wasm. Named .js rather than .mjs: module scripts are subject to
// strict MIME checking, and servers whose MIME table lacks an "mjs" entry
// (e.g. nginx before 1.21.4) serve .mjs as application/octet-stream, which
// browsers refuse to execute. Enabled per page via
//   <meta name="rurema-run-ruby-wasm" content="<ruby+stdlib.wasm URL>">
// which the layout emits when statichtml was invoked with --run-ruby-wasm.
// The wasm URL is chosen by the build side to match the documented Ruby
// version; this file only pins the loader library.

// Exact pin of the npm "latest" dist-tag at the time of writing. Note the
// version scheme: stable @ruby/* packages are published as
// "<pkg version>-<ruby.wasm version>" (e.g. 2.9.3-2.9.4); plain "2.9.4"
// does not exist on npm.
const VM_ESM_URL = 'https://cdn.jsdelivr.net/npm/@ruby/wasm-wasi@2.9.3-2.9.4/dist/browser/+esm'
const OUTPUT_LIMIT = 64 * 1024

// Wrap an async loader so concurrent and repeated calls share one in-flight
// promise, while a rejected attempt clears the cache so the next call
// retries instead of staying broken forever.
export function createOnceLoader(loadFn) {
  let cached
  return function () {
    if (!cached) {
      cached = (async () => {
        try {
          return await loadFn()
        } catch (error) {
          cached = undefined
          throw error
        }
      })()
    }
    return cached
  }
}

// Collect $stdout/$stderr into one StringIO so the output can be read back
// after eval; sharing one StringIO preserves stdout/stderr interleaving.
export const PRELUDE = 'require "stringio"; $stdout = StringIO.new; $stderr = $stdout'

export function formatRunError(error) {
  const text = String((error && error.message) || error)
  return text.split('\n').slice(0, 20).join('\n')
}

export function truncateOutput(text, limit = OUTPUT_LIMIT) {
  if (text.length <= limit) return text
  return text.slice(0, limit) + '\n... (truncated)'
}

// One runner per page: the wasm module is compiled once and cached, but each
// run gets a fresh VM so samples never see each other's state. `running`
// keeps a single VM alive at a time; a run attempted meanwhile returns null.
function createRunner(wasmUrl) {
  const loadModule = createOnceLoader(async () => {
    const [{ DefaultRubyVM }, module] = await Promise.all([
      import(VM_ESM_URL),
      WebAssembly.compileStreaming(fetch(wasmUrl)).catch(async () => {
        // Retry without streaming for servers that send a non-wasm MIME type
        // (e.g. `ruby -run -e httpd` when testing locally).
        const response = await fetch(wasmUrl)
        return WebAssembly.compile(await response.arrayBuffer())
      }),
    ])
    return { DefaultRubyVM, module }
  })
  let running = false
  return async function run(code, onLoaded) {
    if (running) return null
    running = true
    try {
      const { DefaultRubyVM, module } = await loadModule()
      if (onLoaded) onLoaded()
      const { vm } = await DefaultRubyVM(module, { consolePrint: false })
      vm.eval(PRELUDE)
      let error = null
      try {
        vm.eval(code)
      } catch (e) {
        error = formatRunError(e)
      }
      const output = vm.eval('$stdout.string').toString()
      return { output: truncateOutput(output), error }
    } finally {
      running = false
    }
  }
}

function setupBlock(pre, run) {
  const code = pre.querySelector('code')
  if (!code) return

  const button = document.createElement('button')
  button.type = 'button'
  button.className = 'highlight__run-button'
  button.textContent = 'RUN'
  // script.js has already prepended the COPY button (its window.onload
  // handler fires before our load listener); keep COPY rightmost.
  const copyButton = pre.querySelector('.highlight__copy-button')
  if (copyButton) {
    copyButton.after(button)
  } else {
    pre.prepend(button)
  }

  let output
  const ensureOutput = () => {
    if (!output) {
      output = document.createElement('pre')
      output.className = 'highlight__run-output'
      output.setAttribute('aria-live', 'polite')
      pre.after(output)
    }
    return output
  }

  // After the first run the sample becomes editable (like a scratchpad);
  // Ctrl+Enter (or Cmd+Enter) re-runs the edited code. Editing gradually
  // loses the syntax-highlight spans; the COPY button keeps copying the
  // original text.
  const enableEditing = () => {
    if (code.isContentEditable) return
    code.contentEditable = 'true'
    code.spellcheck = false
    pre.dataset.editing = 'true'
    pre.addEventListener('keydown', (event) => {
      if (event.key === 'Enter' && (event.ctrlKey || event.metaKey)) {
        event.preventDefault()
        execute()
      }
    })
  }

  const execute = async () => {
    if (button.disabled) return
    button.disabled = true
    button.setAttribute('aria-busy', 'true')
    button.textContent = 'LOADING...'
    const out = ensureOutput()
    out.classList.remove('highlight__run-output--error')
    out.textContent = ''
    let label = 'RUN'
    try {
      const result = await run(code.textContent, () => {
        button.textContent = 'RUNNING...'
      })
      if (result) {
        out.textContent = result.error
          ? (result.output === '' ? result.error : result.output + '\n' + result.error)
          : result.output
        if (result.error) out.classList.add('highlight__run-output--error')
        enableEditing()
      }
    } catch (e) {
      out.classList.add('highlight__run-output--error')
      out.textContent = formatRunError(e)
      label = 'RETRY'
    } finally {
      button.textContent = label
      button.disabled = false
      button.removeAttribute('aria-busy')
    }
  }
  button.addEventListener('click', execute)
}

function init() {
  const meta = document.querySelector('meta[name="rurema-run-ruby-wasm"]')
  if (!meta || !meta.content) return
  const blocks = document.querySelectorAll('pre.highlight.ruby')
  if (blocks.length === 0) return
  const run = createRunner(meta.content)
  blocks.forEach((pre) => setupBlock(pre, run))
}

// Guarded so the module stays side-effect-free outside a browser
// (test/js/test_run.mjs imports it under QuickJS).
if (typeof window !== 'undefined' && typeof document !== 'undefined') {
  if (document.readyState === 'complete') {
    init()
  } else {
    window.addEventListener('load', init)
  }
}
