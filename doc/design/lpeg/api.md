# Proposed Lua API: `lpeg` and `re`

This is a design proposal, not a specification. The `lpeg` and `re` surfaces are **upstream LPeg's**
and are not open for redesign — vendoring them faithfully is a project goal. What *is* proposed here is
the thin Lunatik-specific surface: how a pattern matches a `data` object, the compile/match
discipline for kernel contexts, and how the modules are exposed. Anything that conflicts with a kernel
constraint (`kernel-notes.md`) loses.

Two modules:

* `lpeg` — the C library, exposed exactly as upstream `luaopen_lpeg` builds it (`luaL_newlib` over
  `pattreg`: `match`, `P`, `R`, `S`, `C`, `Ct`, `Cg`, `Cc`, `Cp`, `Cmt`, `B`, `V`, grammars, …);
* `re` — the pure-Lua grammar-string front end (`lib/re.lua`, installed verbatim), which `require`s
  `lpeg`.

## Conventions

* A **pattern** is a userdata whose uservalue holds its `ktable` (subpattern references and capture
  constants); it is ordinary GC-managed Lua state. Nothing to free by hand.
* Compilation happens in a **process** runtime; matching happens wherever the pattern is used, subject
  to the softirq rules below.
* The subject of a match is a Lua string **or** a `data` object; captures come back as Lua values.

## Using it — combinators

    local lpeg = require("lpeg")

    local digit  = lpeg.R("09")
    local number = lpeg.C(digit^1) / tonumber      -- capture, converted
    local ws     = lpeg.S(" \t")^0
    local pair   = lpeg.Ct(number * ws * number)   -- table capture

    local t = lpeg.match(pair, "12   34")          -- {12, 34}

## Using it — the `re` grammar syntax

    local re = require("re")

    local ip = re.compile[[
      ip     <- octet "." octet "." octet "." octet
      octet  <- %d %d? %d?
    ]]

    print(lpeg.match(ip, "192.168.0.1"))           -- end position, or nil

`re.match(subject, patt)` and `re.compile(grammar)` behave as upstream. `re` is Lua only; it adds no
kernel surface of its own beyond needing `lpeg` loaded.

## Matching a `data` object

The one genuinely new entry point. Upstream `lp_match` takes the subject via `luaL_checklstring`; a
kernel hook holds packet bytes as a `data` object, not a Lua string, and copying a packet to a string
per match is exactly the cost this binding exists to avoid.

Proposal: `lpeg.match` accepts a `data` object as the subject and reads its buffer `(ptr, len)`
directly, with no copy.

    local function hook(skb)
        local payload = skb:data()                 -- a data object, no copy
        local m = lpeg.match(http_request, payload)
        ...
    end

Lifetime rule: the `data` buffer must stay valid for the duration of the match. Inside a hook it does
(the `skb` is live for the callback). A pattern must not stash the subject and match it later against a
buffer that has been freed — matching is synchronous and does not retain the buffer.

Open question: whether this is a `data`-aware branch inside the existing `lpeg.match` (preferred — one
function, subject is string-or-data) or a separate `lpeg.matchdata`. The single-function form reads
better and mirrors how `skb:data()` already returns something the rest of the API consumes.

## The compile / match discipline

This is the part that is Lunatik's, not LPeg's, and it exists because of the kernel stack and context
rules in `kernel-notes.md`.

LPeg compiles a pattern **lazily**, on its first match (`prepcompile` inside `lp_match`). In userspace
that is invisible. In the kernel it means the first match decides *where compilation runs* — and
compilation allocates and recurses over the pattern tree, which must not happen in softirq.

Proposal: an explicit compile step, so a pattern that will be used from a softirq hook is compiled
ahead of time in the process runtime that builds it.

    -- process context (script body, runs once at runtime creation):
    local http_request = lpeg.compile(grammar)     -- forces prepcompile now

    -- softirq hook (later): matches an already-compiled pattern, never compiles
    lpeg.match(http_request, payload)

`lpeg.compile(patt)` returns the same pattern, compiled. If the maintainer prefers not to add API, the
alternative is a documented rule ("match once in process context to warm the pattern"), but an explicit
`compile` is harder to get wrong and self-documenting. Either way, **a softirq runtime that reaches an
uncompiled pattern raises** rather than compiling in atomic context.

Matching itself from softirq is allowed once the pattern is compiled, the on-stack arrays are shrunk
(build-time, `kernel-notes.md`), and the pattern is linear by construction. If phase 3 finds softirq
matching cannot be made safe, `lpeg.match` from a non-sleepable runtime raises via the
`lunatik_cannotsleep` path, and matching is process-only — a documented restriction, not a crash.

## Match-time captures (`Cmt`)

`Cmt(patt, f)` calls the Lua function `f` *during* the match. That is legal and useful (a rule can run
code as it parses), but the callback runs in the matching runtime's context: in a softirq runtime it
must not sleep, the same rule every Lunatik softirq callback already follows. Documented, and covered
by a test.

## Worked example: HTTP request line and Host

The demonstration of the engine — a grammar, not a gateway. It parses one buffer; it does not
reassemble TCP (that is the `stream` project), and the example says so.

    local lpeg = require("lpeg")
    local C, Ct, P, R, S = lpeg.C, lpeg.Ct, lpeg.P, lpeg.R, lpeg.S

    local crlf   = P"\r\n"
    local sp     = P" "
    local token  = C((R("!~") - sp)^1)                    -- non-space run
    local method = token
    local target = token
    local version= C(P"HTTP/" * R"09" * P"." * R"09")

    local reqline = Ct(method * sp * target * sp * version * crlf)

    local hdr_host = P"Host:" * S" \t"^0 * C((1 - crlf)^1)
    local host     = (crlf^-1 * (hdr_host + (1 - crlf)^0 * crlf))^0

    local request  = lpeg.compile(Ct(reqline * (host + P(1))))   -- compiled in process

    -- in a hook (softirq), against packet bytes with no copy:
    local function classify(payload)
        local r = lpeg.match(request, payload)
        -- r[1] = {method, target, version}; capture Host as needed
        return r
    end

The grammar produces structured fields; a routing decision on top of them belongs to the router
project, not here.

## Open questions for review

1. `lpeg.match` accepting a `data` subject (one function) versus a separate `lpeg.matchdata`.
2. Adding `lpeg.compile` versus documenting a warm-up match. (Proposal: add it.)
3. Whether `re` should be installed unconditionally or only when `lpeg` is present (it `require`s
   `lpeg`, so it is inert without it — installing both together is simplest).
4. Whether to expose `lpeg.setmaxstack` (it exists upstream, sets the per-state backtrack cap stored
   in the registry) so a script can tune the heap-spill threshold, or fix it at a kernel-safe value.

