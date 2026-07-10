// QuickJS-based tests for the pure logic in theme/default/js/run.js.
// Run with: qjs test/js/test_run.mjs   (see the "test:js" rake task)
// Importing the module doubles as a syntax/eval smoke test: its DOM setup is
// guarded by `typeof window !== 'undefined'`.
import { createOnceLoader, PRELUDE, formatRunError, truncateOutput } from '../../theme/default/js/run.js'

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

// PRELUDE captures both streams into one StringIO
assert(PRELUDE.includes('require "stringio"') &&
       PRELUDE.includes('$stdout = StringIO.new') &&
       PRELUDE.includes('$stderr = $stdout'),
       'PRELUDE redirects $stdout and $stderr into one StringIO')

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

if (failures > 0) {
  throw new Error(failures + ' JS test(s) failed')
}
print('all JS tests passed')
