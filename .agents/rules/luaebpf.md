---
paths:
  - "**/bin/luaebpf/**"
---

# The Lua to eBPF compiler

* A construct the compiler lowers computes what the kernel's Lua computes, or is refused at its
  line; it never answers as the eBPF instruction alone would. The guide page on the compiler's
  architecture says, for each lowering, what Lua computes, what the instruction alone would and
  what the compiler emits between them, with an example: `-7 // 2` is -4 in Lua, `BPF_SDIV` gives
  -3, and the quotient is corrected as `luaV_idiv` corrects it. It names each place a compiled
  function parts from Lua, which is a refusal and never a different answer, with the reason the
  bits cannot settle it: an `==` on a register a join left with several types, whose bits hold
  `false`, `nil` and 0 as the same zero. A change that adds a lowering or changes one changes that
  page in the same pull request, since a lowering the page does not list is one the next reader
  works out again from `emit.lua`.
