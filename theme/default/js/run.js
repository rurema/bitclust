// RUN button for Ruby sample code: executes the sample in-browser with
// ruby.wasm, off the main thread in a Web Worker (theme/default/js/run-worker.js)
// so an infinite loop or long sleep in the sample can't freeze the page; a
// STOP button and a timeout both just Worker.terminate() it. Named .js
// rather than .mjs: module scripts are subject to strict MIME checking, and
// servers whose MIME table lacks an "mjs" entry (e.g. nginx before 1.21.4)
// serve .mjs as application/octet-stream, which browsers refuse to execute.
// The same reasoning applies to run-worker.js. Enabled per page via
//   <meta name="rurema-run-ruby-wasm" content="<ruby+stdlib.wasm URL>">
// which the layout emits when statichtml was invoked with --run-ruby-wasm.
// The wasm URL is chosen by the build side to match the documented Ruby
// version. This file only compiles that wasm (WebAssembly.compileStreaming
// needs no loader library, just the bytes); the CDN-hosted @ruby/wasm-wasi
// loader is pinned and imported inside run-worker.js, which is the only
// place that actually instantiates a VM from the compiled module.
const OUTPUT_LIMIT = 64 * 1024
const RUN_TIMEOUT_MS = 30 * 1000

// Resolved relative to this module's own URL (not the page URL), so it keeps
// working regardless of how deep the current page is under the site root or
// how custom_js_url() built run.js's own <script src>. Computed lazily
// (rather than as a module-level constant) because the `URL` global does
// not exist under QuickJS, which imports this file for its pure-function
// tests without ever calling into the browser-only code path below.
function workerUrl() {
  return new URL('run-worker.js', import.meta.url)
}

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

export function formatRunError(error) {
  const text = String((error && error.message) || error)
  return text.split('\n').slice(0, 20).join('\n')
}

export function truncateOutput(text, limit = OUTPUT_LIMIT) {
  if (text.length <= limit) return text
  return text.slice(0, limit) + '\n... (truncated)'
}

// Appends one output chunk to the accumulated text, applying the same
// display cap as truncateOutput. Once the cap is hit, further chunks are
// dropped (not just re-truncating the same prefix again and again), so a
// runaway output loop does the "... (truncated)" marker once and then does
// O(1) work per chunk instead of O(output length).
export function accumulateOutput(current, chunk, limit = OUTPUT_LIMIT) {
  if (current.endsWith('\n... (truncated)')) return current
  return truncateOutput(current + chunk, limit)
}

export const STOPPED_NOTE = '(停止しました)'
export function timeoutNote(seconds) {
  return `(${seconds}秒でタイムアウトしました)`
}

// Compiles the wasm module once (cached like the old single-VM version) and
// hands a fresh Worker + that same compiled Module to each run. The Module
// is a structured-cloneable postMessage payload, so terminate()-ing a run
// and starting another never needs to recompile.
function createRunner(wasmUrl) {
  const loadModule = createOnceLoader(async () => {
    return WebAssembly.compileStreaming(fetch(wasmUrl)).catch(async () => {
      // Retry without streaming for servers that send a non-wasm MIME type
      // (e.g. `ruby -run -e httpd` when testing locally).
      const response = await fetch(wasmUrl)
      return WebAssembly.compile(await response.arrayBuffer())
    })
  })
  return {
    loadModule,
    // One Worker per run (see module comment): terminate() always yields a
    // clean slate, and samples never see another run's VM state.
    spawn() {
      return new Worker(workerUrl(), { type: 'module' })
    },
  }
}

function setupBlock(pre, runner) {
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
  let outputTextNode
  const ensureOutput = () => {
    if (!output) {
      output = document.createElement('pre')
      output.className = 'highlight__run-output'
      output.setAttribute('aria-live', 'polite')
      // COPY ボタン(先頭)を残したまま本文を書き換えられるように、
      // 出力テキストは専用のテキストノードに持つ
      outputTextNode = document.createTextNode('')
      output.appendChild(outputTextNode)
      pre.after(output)
      // 実行結果もコピーできるようにする(script.js の公開フック)。
      // 出力は実行のたびに変わるので、クリック時のテキストを渡す
      if (window.ruremaAddCopyButton) {
        window.ruremaAddCopyButton(output, () => outputTextNode.data)
      }
    }
    return output
  }
  const setOutputText = (text) => {
    outputTextNode.data = text
  }

  // After the first run the sample becomes editable (like a scratchpad);
  // Ctrl+Enter (or Cmd+Enter) re-runs the edited code. The COPY button
  // keeps copying the original text.
  const enableEditing = () => {
    if (code.isContentEditable) return
    // 編集でハイライトの span に文字が食い込むと、貼り付けた文字が
    // その場の色を引き継いで中途半端に崩れるため、編集可能にする
    // 時点でプレーンテキスト化して色を消す
    code.textContent = code.textContent
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

  // Non-null exactly while a run's Worker is alive; STOP terminates it and
  // the timeout/message handlers all check this to avoid acting twice on
  // the same run (e.g. a timeout racing a message that just arrived).
  let current = null

  const finish = (out, label, isError) => {
    if (current && current.timer) clearTimeout(current.timer)
    current = null
    if (isError) out.classList.add('highlight__run-output--error')
    enableEditing()
    button.textContent = label
    button.disabled = false
    button.removeAttribute('aria-busy')
  }

  // Final notes (stop / timeout / the run's error message) are appended
  // directly, bypassing accumulateOutput's 64KB cap: the cap exists to stop
  // unbounded *output* growth, and these one-shot notes are bounded — they
  // must stay visible precisely in the runaway-output case where the cap
  // has already been hit and accumulateOutput would drop them.
  const appendNote = (text) => {
    const separator = outputTextNode.data === '' ? '' : '\n'
    setOutputText(outputTextNode.data + separator + text)
  }

  const stop = () => {
    if (!current) return
    current.worker.terminate()
    const out = ensureOutput()
    appendNote(STOPPED_NOTE)
    finish(out, 'RUN', false)
  }

  const execute = async () => {
    if (current) return // mid-run click on the (now STOP-labeled) button; use the dedicated STOP path
    if (button.disabled) return
    button.disabled = true
    button.setAttribute('aria-busy', 'true')
    button.textContent = 'LOADING...'
    const out = ensureOutput()
    out.classList.remove('highlight__run-output--error')
    setOutputText('')

    let module
    try {
      module = await runner.loadModule()
    } catch (e) {
      setOutputText(formatRunError(e))
      finish(out, 'RETRY', true)
      return
    }

    const worker = runner.spawn()
    const timer = setTimeout(() => {
      if (!current) return
      worker.terminate()
      appendNote(timeoutNote(RUN_TIMEOUT_MS / 1000))
      finish(out, 'RUN', false)
    }, RUN_TIMEOUT_MS)
    current = { worker, timer }

    button.textContent = 'STOP'
    button.disabled = false
    button.setAttribute('aria-busy', 'true')

    worker.onmessage = (event) => {
      const message = event.data
      if (!current || current.worker !== worker) return
      if (message.type === 'output') {
        setOutputText(accumulateOutput(outputTextNode.data, message.text))
      } else if (message.type === 'done') {
        finish(out, 'RUN', false)
      } else if (message.type === 'error') {
        appendNote(message.message)
        finish(out, 'RUN', true)
      }
    }
    worker.onerror = (event) => {
      if (!current || current.worker !== worker) return
      event.preventDefault()
      setOutputText(formatRunError(event.message || event))
      finish(out, 'RETRY', true)
    }
    worker.postMessage({ module, code: code.textContent })
  }
  button.addEventListener('click', () => {
    if (current) {
      stop()
    } else {
      execute()
    }
  })
}

function init() {
  const meta = document.querySelector('meta[name="rurema-run-ruby-wasm"]')
  if (!meta || !meta.content) return
  const blocks = document.querySelectorAll('pre.highlight.ruby')
  if (blocks.length === 0) return
  const runner = createRunner(meta.content)
  blocks.forEach((pre) => setupBlock(pre, runner))
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
