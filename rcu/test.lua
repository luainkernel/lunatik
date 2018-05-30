print("begin of tests")
rcu.add_number(0)
assert(rcu.search_number(0))
assert(rcu.first_number() == 0)

rcu.add_number(9)
assert(rcu.first_number() == 9)
assert(rcu.search_number(9))

rcu.for_each(print)

rcu.delete_number(9)
assert(rcu.first_number() == 0)
assert(rcu.search_number(9) == false)


rcu.replace_number(0, -1)
rcu.for_each(print)
assert(rcu.search_number(0) == false)
assert(rcu.search_number(-1))
rcu.delete_number(-1)

assert(rcu.is_empty())

rcu.add_number(10)
rcu.add_number(20)
rcu.add_number(30)
assert(rcu.search_number(30))
assert(rcu.search_number(10))
assert(rcu.search_number(20))

rcu.for_each(print)

rcu.replace_number(30, 20)
assert(rcu.search_number(30) == false)
assert(rcu.search_number(20))

rcu.delete_number(20)
assert(rcu.search_number(20))
rcu.delete_number(10)
rcu.delete_number(20)

assert(rcu.is_empty())
print("all done")
