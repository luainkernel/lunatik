#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/slab.h>
#include <linux/list.h>
#include <linux/rculist.h>
#include <linux/spinlock.h>
#include <linux/preempt.h>
#include <linux/hashtable.h>

#include <lua/lua.h>
#include <lua/lauxlib.h>
#include <lua/lualib.h>
#include <lua/llimits.h>

struct element {
    char *key;
    char *value;
    struct hlist_node node;
    struct rcu_head rcu;
};

#define nbits 3
#define mask ((1 << nbits) -1)
static DEFINE_HASHTABLE(table, nbits);
static spinlock_t bucket_lock[1 << nbits];


#if !defined(LUAI_HASHLIMIT)
#define LUAI_HASHLIMIT		5
#endif

unsigned int lua_hash_str(const char *str, size_t l, unsigned int seed) {
  unsigned int h = seed ^ cast(unsigned int, l);
  size_t step = (l >> LUAI_HASHLIMIT) + 1;
  for (; l >= step; l -= step)
    h ^= ((h<<5) + (h>>2) + cast_byte(str[l - 1]));
  return h;
}

#define hash_str(str)               \
    lua_hash_str(str, strlen(str), 0)


static struct element* hash_search_element(const char *key) {
    struct element *e;        
    int idx = hash_str(key) & mask;
    
    hlist_for_each_entry(e, &table[idx], node) {
        if (strcmp(e->key, key) == 0) {
            printk("found [%s] - %s on bucket %d", e->key, e->value, idx);
            return e;
        }
    }
    
    printk("key %s not found", key);
    return NULL;
}


static int hash_add_element(const char *key, const char *value, int idx) {
    struct element *e;    
    e = kmalloc(sizeof(struct element), GFP_KERNEL);
    
    e->key = kmalloc(strlen(key) +1, GFP_KERNEL); //+1 also consider a \0
    strcpy(e->key, key);
    e->value = kmalloc(strlen(value) +1, GFP_KERNEL);
    strcpy(e->value, value);    
        
    hlist_add_head_rcu(&e->node, &table[idx]);
    
    printk("adding pair %s - %s to bucket %d", key, value, idx);
    return 0;
}

static int hash_each(lua_State *L) {
    int bkt = 0;
    struct element *e = NULL;
    
    rcu_read_lock();
    hash_for_each_rcu(table, bkt, e, node) {
        printk("[%s] = %s", e->key, e->value);
    }
    rcu_read_unlock();
    return 0;
}

static int hash_delete_element(struct element *e, int idx) {
    hlist_del_rcu(&e->node);

    synchronize_rcu();
    kfree(e->key);
    kfree(e->value);
    kfree(e);
    
    return 0;
}



static int hash_replace_element(struct element *e, const char *new_value, int idx) {
    struct element *new_e = NULL;
        
    new_e = kmalloc(sizeof(struct element), GFP_KERNEL);    
    
    new_e->key = kmalloc(strlen(e->key) +1, GFP_KERNEL);
    strcpy(new_e->key, e->key);    
    new_e->value = kmalloc(strlen(new_value) +1, GFP_KERNEL);
    strcpy(new_e->value, new_value);
    
    hlist_replace_rcu(&e->node, &new_e->node);
    
    synchronize_rcu();
    kfree(e->value);
    kfree(e->key);
    kfree(e);
    
    printk("Updated key %s to value %s on bucket %d", new_e->key, new_value, idx);
    return 0;
}

static int hash_search_value(lua_State *L) {
    struct element *e;        
    const char *key;
    int idx;
    
    luaL_checktype(L, -1, LUA_TSTRING);
    key = lua_tostring(L, -1);
    idx = hash_str(key) & mask;
    
    rcu_read_lock();
    hlist_for_each_entry_rcu(e, &table[idx], node) {
        if (strcmp(e->key, key) == 0) {
            printk("found [%s] - %s on bucket %d", e->key, e->value, idx);
            lua_pushstring(L, e->value);
            rcu_read_unlock();
            return 1;
        }
    }
    
    lua_pushnil(L);
    rcu_read_unlock();    
    printk("key %s not found", key);
    return 1;
}


static int hash_newindex(lua_State *L) {
    struct element *e;
    const char *key, *value;
    int idx;
        
    //Only strings are allowed for keys.
    //Value allows for both strings or nil (meaning deletion).
    //Raises an error if the user supply different types.
    luaL_checktype(L, -2, LUA_TSTRING);    
    
    if (lua_type(L, -1) != LUA_TNIL && lua_type(L, -1) != LUA_TSTRING)
        luaL_argerror(L, -1, "Expected a string or nil for value");
        
    key = lua_tostring(L, -2);
    idx = hash_str(key) & mask;

    spin_lock(&bucket_lock[idx]);
    e = hash_search_element(key);
    if (e == NULL) {
        value = lua_tostring(L, -1); 
        hash_add_element(key, value, idx);
    }
    else {
        if (lua_isnil(L, -1)) {
            hash_delete_element(e, idx);
        }
        else {            
            value = lua_tostring(L, -1); 
            hash_replace_element(e, value, idx);
        }

    }    
    spin_unlock(&bucket_lock[idx]);    
    return 0;
}

static const struct luaL_Reg rcu_funcs[] = {
    {"for_each", hash_each},
    {NULL, NULL}
};

static const struct luaL_Reg rcu_methods[] = {
    {"__newindex", hash_newindex},
    {"__index",    hash_search_value},
    {NULL, NULL}
};

int luaopen_rcu(lua_State *L) {
    int i;
    hash_init(table);
    
    for (i = 0; i < (1 << nbits); i++)
        spin_lock_init(&bucket_lock[i]);

    luaL_newmetatable(L, "Rcu.hash");
    luaL_setfuncs(L, rcu_methods, 0);        
    luaL_newlib(L, rcu_funcs);
    luaL_setmetatable(L, "Rcu.hash");
    
    return 1;
}
