-- helper function
local str2table = function(str)
    local tab = {}
    for i = 1, #str do
        tab[i] = string.sub(str, i, i)
    end
    return tab
end    

s1 = "abcdefghijkl"
tab = str2table(s1)

for i = 1, #tab do
    c = tab[i]
    rcu[c] = c..c
    assert(rcu[c] == c..c)

    rcu[c] = true
    assert(rcu[c] == true)
    
    rcu[c] = i
    assert(rcu[c] == i)

    rcu[c] = rcu[c] + 1
    assert(rcu[c] == (i+1))

    rcu[c] = nil
    assert(rcu[c] == nil)
    
    rcu[c] = c..c..c
    assert(rcu[c] == c..c..c)
    
    rcu[c] = nil
    assert(rcu[c] == nil)

    rcu[c] = i + 1
    assert(rcu[c] == (i+1))
    
    rcu[c] = false 
    assert(rcu[c] == false)
    
    rcu[c] = c..c
    assert(rcu[c] == c..c)
    
    rcu[c] = c..c..c
    assert(rcu[c] == c..c..c)
    
    rcu[c] = i
    assert(rcu[c] == i)
end

rcu.for_each(print)      
   
print("end test")
