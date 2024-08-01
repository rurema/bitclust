const rubyWasmUrl = 'https://cdn.jsdelivr.net/npm/ruby-head-wasm-wasi@latest/dist/ruby.wasm'
const rubyVmUrl = 'https://cdn.jsdelivr.net/npm/ruby-wasm-wasi@latest/dist/browser.esm.js'

let moduleCache
const loadRubyModule = async () => {
  if (moduleCache) {
    return moduleCache
  }
  moduleCache = await WebAssembly.compileStreaming(fetch(rubyWasmUrl))
  return moduleCache
}

let defaultRubyVMCache
const loadRubyVM = async () => {
  if (!defaultRubyVMCache) {
    const { DefaultRubyVM } = await import(rubyVmUrl)
    defaultRubyVMCache = DefaultRubyVM
  }
  return await defaultRubyVMCache(await loadRubyModule(), { consolePrint: false })
}

const isHighlightElement = (preElement) => {
  if (!preElement || preElement.tagName !== 'PRE') return false

  const [highlight, lang] = [...preElement.classList]
  return highlight === 'highlight' && lang === 'ruby'
}

const setupWriteSync = (fs, output) => {
  const originalWriteSync = fs.writeSync.bind(fs)
  const writeSync = function () {
    const fd = arguments[0]
    if (fd === 1 || fd === 2) {
      const textOrBuffer = arguments[1]
      const text = arguments.length === 4 ? textOrBuffer : new TextDecoder('utf-8').decode(textOrBuffer)
      output(text)
    }
    return originalWriteSync(...arguments)
  }
  fs.writeSync = writeSync
}

const createOutputTextArea = () => {
  const textarea = document.createElement('textarea')
  textarea.classList.add('highlight__run-output')
  return textarea
}

const runRuby = async (event) => {
  const runButton = event.target
  const preElement = runButton.parentElement
  if (!isHighlightElement(preElement)) return
  if (runButton.dataset.loading) return

  let rubyVM
  runButton.dataset.loaderror = false
  try {
    runButton.dataset.loading = true
    runButton.innerText = 'LOADING...'
    rubyVM = await loadRubyVM()
  } catch (error) {
    runButton.dataset.loaderror = true
    return
  } finally {
    runButton.dataset.loading = false
    runButton.innerText = 'RUN'
  }

  const outputTextarea = createOutputTextArea()
  preElement.insertAdjacentElement('afterend', outputTextarea)
  const { vm, fs: { fs } } = rubyVM
  setupWriteSync(fs, (text) => { outputTextarea.value += text })

  const codeElement = preElement.querySelector('code')

  const evalSource = () => {
    outputTextarea.value = ''
    try {
      runButton.dataset.running = true
      runButton.innerText = 'RUNNING...'
      vm.eval(codeElement.textContent)
    } catch (error) {
      outputTextarea.value = error
    } finally {
      setTimeout(() => { runButton.dataset.running = false }, 600)
      runButton.innerText = 'RUN'
    }
  }
  runButton.onclick = evalSource
  runButton.onkeydown = (event) => {
    if (event.code === 'Enter' || event.code === 'Space') {
      event.stopPropagation()
      evalSource()
      return false
    }
  }

  preElement.dataset.editing = true
  codeElement.setAttribute('spellcheck', 'off')
  codeElement.setAttribute('contenteditable', 'true')
  preElement.addEventListener('keydown', (event) => {
    if (event.code === 'Enter' && event.ctrlKey) {
      event.stopPropagation()
      evalSource()
    }
  })

  evalSource()
}

const createRunButton = () => {
  const button = document.createElement('span')
  button.innerText = 'RUN'
  button.setAttribute('role', 'button')
  button.setAttribute('class', 'highlight__run-button')
  button.setAttribute('tabindex', '0')
  button.onclick = runRuby
  button.onkeydown = (event) => {
    if (event.code === 'Enter' || event.code === 'Space') {
      event.stopPropagation()
      runRuby(event)
      return false
    }
  }
  return button
}

document.querySelectorAll('.highlight.ruby').forEach((elem) => {
  const button = createRunButton()
  elem.insertAdjacentElement('afterbegin', button)
})
