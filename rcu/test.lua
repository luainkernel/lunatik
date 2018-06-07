rcu.add("hello", "hello123")
assert(rcu.search("hello") == "hello123")
rcu.replace("hello", "123hello")
assert(rcu.search("hello") == "123hello")

assert(rcu.search("non existant key") == nil)

rcu.add("helloo", "hello1234")
rcu.replace("helloo", "1234hello")
assert(rcu.search("helloo") == "1234hello")

rcu.for_each()

rcu.delete("hello")
assert(rcu.search("hello") == nil)

rcu.delete("helloo")
assert(rcu.search("helloo") == nil)

rcu.for_each()
