function rcu_protect()
    local proxy = {}    
    local mt = {}
    
    mt.__index = function(_, k)
        return rcu.search_number(k)
    end
    
    mt.__newindex = function(_, k, v)
        if v == nil then
            rcu.delete_number(k)
        else
            if rcu.search_number(k) then
                rcu.update_number(k, v)
            else                 
                rcu.add_number(k, v)
            end
        end
    end
    
    setmetatable(proxy, mt)
    return proxy
end

print("-- BEGIN")
tab = rcu_protect()
tab[3] = 1
assert(tab[3] == 1)
tab[3] = 2
assert(tab[3] == 2)
tab[3] = 3
assert(tab[3] == 3)
tab[3] = nil
assert(tab[3] == nil)
tab[3] = 3
assert(tab[3] == 3)
tab[4] = 5
assert(tab[4] == 5)
print("-- END")
