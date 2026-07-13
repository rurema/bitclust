// Module Worker that runs one RUN-button sample. Loaded by theme/default/js/run.js
// via `new Worker(url, { type: 'module' })`; one Worker instance per execution
// (see run.js for why: a fresh VM per run needs no cross-run state, and it
// makes terminate()-to-stop trivial). Named .js rather than .mjs for the same
// MIME-serving reason as run.js (see the comment at the top of that file).
//
// Protocol:
//   main -> worker: { module: WebAssembly.Module, code: string }
//   worker -> main: { type: 'output', text: string }   (zero or more, in order)
//   worker -> main: { type: 'done' }                   (exactly one, on success)
//   worker -> main: { type: 'error', message: string } (exactly one, on failure)
// Exactly one of 'done'/'error' is posted, always last. The main thread may
// also just call worker.terminate() (STOP button / timeout); the worker does
// not need to post anything in that case.

const VM_ESM_URL = 'https://cdn.jsdelivr.net/npm/@ruby/wasm-wasi@2.9.3-2.9.4/dist/browser/+esm'

// Same idea as run.js's old (pre-Worker) PRELUDE -- redirect $stdout/$stderr
// -- but instead of buffering into a StringIO for one bulk read at the end,
// each write is forwarded to the main thread immediately via postOutput()
// so long-running or infinite-output samples show progress instead of
// growing an in-wasm string forever. $stderr shares the same sink so
// interleaving still reads naturally, matching the previous StringIO-based
// behavior. Ruby only ever hands the JS bridge a plain string, so
// $stdout.write calls self.postOutput(), a small helper defined below
// (rather than calling self.postMessage directly from Ruby) so that
// postMessage itself stays the single place that emits the { type: ... }
// envelope; main.onmessage never has to disambiguate a bare string from a
// control message.
//
// Kernel#puts/print/p reach a non-IO $stdout through its #write, but the
// manual's samples also call IO methods on $stdout/$stderr *directly*
// ($stderr.puts, $stdout.putc, $stdout.print, $stdout.flush, $stderr.tty?,
// ...). The old StringIO provided those for free, so the common ones are
// implemented here; their semantics are covered by test/test_run_worker_prelude.rb,
// which evals this prelude in a real Ruby with the JS bridge stubbed.
export const PRELUDE = `
require "js"
class JSStreamIO
  def write(*parts)
    text = parts.join
    JS.global.call(:postOutput, text)
    text.bytesize
  end
  def <<(obj)
    write(obj)
    self
  end
  def puts(*args)
    if args.empty?
      write("\n")
    else
      args.flatten.each do |arg|
        s = arg.to_s
        s = s + "\n" unless s.end_with?("\n")
        write(s)
      end
    end
    nil
  end
  def print(*args)
    write(args.join)
    nil
  end
  def printf(*args)
    write(sprintf(*args))
    nil
  end
  def putc(ch)
    write(ch.is_a?(String) ? ch[0] : ch.chr)
    ch
  end
  def flush; self; end
  def sync; true; end
  def sync=(value); value; end
  def tty?; false; end
  alias isatty tty?
end
$stdout = JSStreamIO.new
$stderr = $stdout
`

export function formatRunError(error) {
  const text = String((error && error.message) || error)
  return text.split('\n').slice(0, 20).join('\n')
}

// Guarded the same way run.js guards its init(): this file is imported by
// test/js/test_run.mjs under QuickJS, which has neither `self` (as the
// Worker global) nor a real postMessage/onmessage.
if (typeof self !== 'undefined' && typeof WorkerGlobalScope !== 'undefined') {
  self.postOutput = (text) => self.postMessage({ type: 'output', text })

  self.onmessage = async (event) => {
    const { module, code } = event.data
    try {
      const { DefaultRubyVM } = await import(VM_ESM_URL)
      const { vm } = await DefaultRubyVM(module, { consolePrint: false })
      vm.eval(PRELUDE)
      try {
        vm.eval(code)
      } catch (e) {
        self.postMessage({ type: 'error', message: formatRunError(e) })
        return
      }
      self.postMessage({ type: 'done' })
    } catch (e) {
      self.postMessage({ type: 'error', message: formatRunError(e) })
    }
  }
}
