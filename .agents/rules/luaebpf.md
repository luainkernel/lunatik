---
paths:
  - "**/bin/luaebpf/**"
---

# The Lua to eBPF compiler

* A construct the compiler lowers computes what the kernel's Lua computes, is refused at its line,
  or, where Lua would raise, stops the program with its default verdict; it never answers as the
  eBPF instruction alone would. `doc/guide/08-luaebpf.md`, whose reader writes program files,
  gives each construct a row of *The Lua a program may use*: what the program gives, when it
  stops and when it is refused, "never" written out, as `-7 // 2` gives `-4` and stops where the
  divisor is 0. `doc/guide/09-luaebpf-by-example.md`, whose reader changes the compiler, gives it a
  row of *What the compiler emits*, what Lua computes, what the instruction alone would and what is
  emitted between them, `BPF_SDIV` giving -3 and the quotient corrected as `luaV_idiv` corrects
  it, and its group a compiled program's listing, annotated and traced to a result. The guide
  names each place a compiled function parts from Lua, which is a refusal and never a different
  answer, with the reason the bits cannot settle it: an `==` on a register a join left with
  several types, whose bits hold `false`, `nil` and 0 as the same zero. A change that adds a
  lowering or changes one changes both pages in the same pull request, since a lowering they do
  not list is one the next reader works out again from `emit/`.
