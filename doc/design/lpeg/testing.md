# Testing the LPeg binding

Lunatik's tests are shell scripts emitting KTAP, driving a kernel Lua script and asserting on what it
prints to `dmesg`. `tests/crypto/` and `tests/set/` are the closest models — a C-backed library
exercised from a kernel Lua script over a matrix of inputs, no packets or namespaces needed. Read
`tests/lib.sh` (`run_test`, `mark_dmesg`, `dmesg_since`, `check_dmesg`, `ktap_skip`) first.

Run everything with `sudo lunatik test`, one suite with `sudo lunatik test lpeg`.

## What this suite needs that others do not

Two things, both cheap:

**A vendored-behaviour baseline.** Because most of the code is upstream LPeg, a chunk of the value is
proving the *port* did not change LPeg's behaviour. The most economical way is to lift a subset of
LPeg's own `test.lua` assertions (the parts that do not need `io`/`os`/coroutines) and run them in the
kernel state. A divergence there means the port broke something; a plain pass means the vendored engine
behaves in-kernel as upstream. Keep this a small, curated subset, not the whole upstream test file.

**A stack-safety test that must not crash the machine.** Phase 3's deep-backtrack test deliberately
drives the matcher past the shrunk on-stack arrays to prove the heap spill and the clean
`"backtrack stack overflow"` error, rather than a silent kernel-stack overflow. Run it in a process
runtime first (where a bug is a clean error), and only then in softirq. If it can wedge a machine, it
is written wrong.

## Test matrix

Coverage means the matrix of construct × subject × context, including the successes and the clean
failures, not a list of features.

### Phase 0: it builds and loads

| Test | Proves |
|------|--------|
| `load.sh` | `require("lpeg")` loads in a process runtime; `lpeg.match(lpeg.P"a","a")` returns 2, `lpeg.match(lpeg.P"a","b")` returns nil |
| `version.sh` | the imported LPeg version is what the vendored tree records (guards against an accidental partial import) |

### Phase 1: the API surface (string subjects)

| Test | Proves |
|------|--------|
| `basic.sh` | `P`, `R`, `S`, literals, ordered choice `+`, sequence `*`, repetition `^`, `-` (difference), `#` (lookahead) each match and fail as specified |
| `captures.sh` | `C`, `Ct`, `Cg`/back-reference, `Cc`, `Cp`, `Cs` each return the right Lua values; a `/` function/string/table capture transforms correctly |
| `grammar.sh` | a recursive grammar (balanced parens, a small arithmetic grammar) matches nested input and rejects malformed input |
| `re.sh` | `re.compile`/`re.match` parse the grammar-string syntax and agree with the equivalent combinators |
| `cmt.sh` | a `Cmt` match-time capture calls its Lua function during the match and its return steers the match |
| `nomatch.sh` | failed matches return nil (not an error) at the right position; a partial match reports the right end position |

### Phase 2: `data` subjects

| Test | Proves |
|------|--------|
| `data_match.sh` | the same pattern matches a `data` object and a Lua string with identical results, no copy |
| `data_offset.sh` | matching from an init position into a `data` buffer works; out-of-range init is handled |
| `data_lifetime.sh` | a match consumes the `data` synchronously; the documented "do not stash and match later" rule holds (the buffer is not retained) |

### Phase 3: contexts and stack safety

| Test | Proves |
|------|--------|
| `compile_context.sh` | `lpeg.compile` in a process runtime produces a pattern that a softirq runtime matches without compiling; a softirq match of an *uncompiled* pattern raises rather than compiling |
| `softirq_match.sh` | a compiled, linear pattern matches packet bytes from a `softirq` runtime (driven through a netfilter/XDP hook) and returns the right captures |
| `deep_backtrack.sh` | a pattern that exceeds the shrunk on-stack backtrack array spills to the heap and either matches or raises `"backtrack stack overflow"` cleanly — the machine survives; run in process first, then softirq |
| `atomic_alloc.sh` | a softirq match that must grow the capture/backtrack stack under `GFP_ATOMIC` either succeeds or fails as a clean match error, never oopses |
| `cmt_softirq.sh` | a `Cmt` callback in a softirq runtime that does not sleep works; documentation states a sleeping callback is illegal there |

`compile_context.sh` and `deep_backtrack.sh` are the two that justify the whole phase; write them
before declaring softirq support done. If phase 3 concludes softirq matching cannot be made safe,
these become the tests that a non-sleepable `lpeg.match` raises cleanly, and `softirq_match.sh` is
removed with the reason recorded.

### Phase 4: the example

| Test | Proves |
|------|--------|
| `example_http.sh` | the HTTP request-line + `Host` grammar extracts method, target, version and host from a well-formed request buffer, and rejects a malformed one |
| `example_partial.sh` | the example behaves as documented on a buffer that ends mid-request (no crash, a clean no-match) — the honest single-buffer limitation |

## Conventions to follow

* skip, do not fail, when a needed config is absent;
* mark `dmesg` before the run, read only what came after, and `check_dmesg` at the end;
* `lunatik run` exits 0 even when the script fails to load — assert on output, never on exit status;
* the `.sh` carries the description; the `.lua` gets one line pointing back at it;
* one `.sh` per row above, wired into `tests/lpeg/run.sh` and described in `tests/README.md`, in the
  same commit as the code it tests.

## A note on where these run

Everything except the phase-3 softirq rows runs in a plain process runtime and needs nothing special.
The softirq rows need a netfilter or XDP hook to carry the match into softirq context; model them on
the existing `tests/` that drive loopback traffic, and confine any packet matching to a scratch
port/interface so a matcher bug cannot disturb the machine's real traffic.

