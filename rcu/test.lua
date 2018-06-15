print("begin")

rcu["q"] = "vv"
assert(rcu["q"] == "vv")
rcu["q"] = nil
assert(rcu["q"] == nil)


rcu["q"] = "dd"
rcu["q"] = "rr"
rcu["q"] = "tt"
assert(rcu["q"] == "tt")
rcu["q"] = nil
assert(rcu["q"] == nil)


rcu["a"] = "aa"
rcu["b"] = "bb"
rcu["c"] = "cc"

rcu["b"] = "bbbb"
rcu["a"] = "aaaa"

rcu["d"] = "dd"

assert(rcu["a"] == "aaaa")
assert(rcu["c"] == "cc")
assert(rcu["b"] == "bbbb")
assert(rcu["d"] == "dd")

rcu.for_each()

rcu["a"] = nil
rcu["b"] = nil
rcu["c"] = nil
rcu["d"] = nil

assert(rcu["a"] == nil)
assert(rcu["c"] == nil)
assert(rcu["b"] == nil)
assert(rcu["d"] == nil)

print("end")
