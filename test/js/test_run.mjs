// QuickJS-based tests for the pure logic in theme/default/js/run.js and
// theme/default/js/run-worker.js.
// Run with: qjs test/js/test_run.mjs   (see the "test:js" rake task)
// Importing each module doubles as a syntax/eval smoke test: run.js's DOM
// setup is guarded by `typeof window !== 'undefined'`, and run-worker.js's
// Worker setup is guarded by `typeof self !== 'undefined' && typeof
// WorkerGlobalScope !== 'undefined'` -- neither exists under QuickJS, so
// importing either file here never touches a real DOM/Worker.
import {
  createOnceLoader, formatRunError, truncateOutput,
  accumulateOutput, STOPPED_NOTE, timeoutNote,
} from '../../theme/default/js/run.js'
import { PRELUDE, formatRunError as formatWorkerRunError } from '../../theme/default/js/run-worker.js'

let failures = 0
function assert(cond, message) {
  if (cond) {
    print('ok: ' + message)
  } else {
    failures++
    print('FAIL: ' + message)
  }
}

// createOnceLoader: repeated calls share one load
{
  let calls = 0
  const loader = createOnceLoader(async () => { calls++; return 'value' })
  const [a, b] = [await loader(), await loader()]
  assert(a === 'value' && b === 'value' && calls === 1,
         'createOnceLoader loads once for repeated calls')
}

// createOnceLoader: concurrent calls share one in-flight promise
{
  let calls = 0
  const loader = createOnceLoader(async () => { calls++; return calls })
  const [a, b] = await Promise.all([loader(), loader()])
  assert(a === 1 && b === 1 && calls === 1,
         'createOnceLoader shares an in-flight load')
}

// createOnceLoader: a rejected load is retried on the next call
// (regression test for the old draft's dataset.loading permadeath bug)
{
  let calls = 0
  const loader = createOnceLoader(async () => {
    await 0 // reject asynchronously, like a real network failure (also keeps
            // this qjs build's unhandled-rejection tracker quiet)
    calls++
    if (calls === 1) throw new Error('network down')
    return 'recovered'
  })
  let firstError = null
  try { await loader() } catch (e) { firstError = e }
  const second = await loader()
  assert(firstError !== null && firstError.message === 'network down',
         'first failing load rejects')
  assert(second === 'recovered' && calls === 2,
         'next call after a rejection retries the load')
}

// PRELUDE (run-worker.js) streams both channels to the main thread via the
// JS bridge, instead of buffering into a StringIO like the old single-eval
// PRELUDE did.
assert(PRELUDE.includes('require "js"') &&
       PRELUDE.includes('JS.global.call(:postOutput, text)') &&
       PRELUDE.includes('$stdout = JSStreamIO.new') &&
       PRELUDE.includes('$stderr = $stdout'),
       'PRELUDE redirects $stdout and $stderr through postOutput()')

// run-worker.js's formatRunError is the same shape as run.js's copy (each
// runs in its own realm -- main thread vs. worker -- so it is a small
// intentional duplication rather than an import cycle across the two files)
assert(formatWorkerRunError(new Error('boom')) === 'boom',
       'run-worker.js formatRunError matches run.js formatRunError')

// formatRunError
assert(formatRunError(new Error('boom')) === 'boom',
       'formatRunError uses error.message')
assert(formatRunError('plain') === 'plain',
       'formatRunError accepts non-Error values')
{
  const long = Array.from({ length: 30 }, (_, i) => 'line' + i).join('\n')
  const formatted = formatRunError(new Error(long))
  assert(formatted.split('\n').length === 20,
         'formatRunError caps long messages at 20 lines')
}

// truncateOutput
assert(truncateOutput('short') === 'short', 'truncateOutput keeps short output')
{
  const truncated = truncateOutput('x'.repeat(100), 10)
  assert(truncated.startsWith('x'.repeat(10)) && truncated.endsWith('... (truncated)'),
         'truncateOutput cuts long output with a marker')
}

// accumulateOutput: incremental version of truncateOutput, used to append
// each Worker 'output' message to what is already on screen.
assert(accumulateOutput('foo', 'bar') === 'foobar',
       'accumulateOutput appends a chunk to the existing text')
assert(accumulateOutput('', 'first') === 'first',
       'accumulateOutput handles an empty starting value')
{
  const grown = accumulateOutput('x'.repeat(8), 'y'.repeat(8), 10)
  assert(grown === 'x'.repeat(8) + 'y'.repeat(2) + '\n... (truncated)',
         'accumulateOutput truncates once the cap is crossed mid-chunk')
}
{
  // A chunk arriving after the cap was already hit must be a no-op, not a
  // second "... (truncated)" marker or renewed growth.
  const alreadyTruncated = truncateOutput('x'.repeat(20), 10)
  const next = accumulateOutput(alreadyTruncated, 'more output', 10)
  assert(next === alreadyTruncated,
         'accumulateOutput drops further chunks once truncated')
}

// STOPPED_NOTE / timeoutNote: the notes appended to output on STOP / timeout
assert(STOPPED_NOTE === '(停止しました)', 'STOPPED_NOTE is the stop notice')
assert(timeoutNote(30) === '(30秒でタイムアウトしました)',
       'timeoutNote formats the configured timeout in seconds')

if (failures > 0) {
  throw new Error(failures + ' JS test(s) failed')
}
print('all JS tests passed')
