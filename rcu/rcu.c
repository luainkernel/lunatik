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

struct tvalue {
    union {
        int i;
        bool b;
        const char *s;    
    };
    int type;
};

struct element {
    char *key;
    struct tvalue value;
    struct hlist_node node;
    struct rcu_head rcu;
};

#define BITS 3
#define NBUCKETS (1 << BITS)
#define MASK (NBUCKETS -1)
static DEFINE_HASHTABLE(rcutable, BITS);
static spinlock_t bucket_lock[NBUCKETS];
static bool first_time_setup = true;

#if !defined(LUAI_HASHLIMIT)
#define LUAI_HASHLIMIT		5
#endif

static unsigned int lua_hash_str(const char *str, size_t l, unsigned int seed) {
  unsigned int h = seed ^ cast(unsigned int, l);
  size_t step = (l >> LUAI_HASHLIMIT) + 1;
  for (; l >= step; l -= step)
    h ^= ((h<<5) + (h>>2) + cast_byte(str[l - 1]));
  return h;
}

#define hash_str(str)               \
    lua_hash_str(str, strlen(str), 0)

static struct element* rcu_search_element(const char *key, int idx) {
    struct element *e;        
    
    hlist_for_each_entry(e, &rcutable[idx], node) {
        if (strcmp(e->key, key) == 0) {
            return e;
        }
    }
    
    return NULL;
}

static int rcu_add_element(lua_State *L, const char *key, struct tvalue value, int idx) {
    struct element *e;    

    e = kmalloc(sizeof(struct element), GFP_ATOMIC);
    if (!e) luaL_error(L, "could not allocate memory");
    
    e->key = kmalloc(strlen(key) +1, GFP_ATOMIC); //+1 also consider a \0
    if (!e->key) luaL_error(L, "could not allocate memory");
    strcpy(e->key, key);
    
    e->value.type = value.type;
    switch (e->value.type) {
    case LUA_TSTRING:
        e->value.s = kmalloc(strlen(value.s) +1, GFP_ATOMIC);
        if (!e->value.s) luaL_error(L, "could not allocate memory");
        strcpy(e->value.s, value.s);
        break;
    case LUA_TNUMBER:
        e->value.i = value.i;    
        break;
    case LUA_TBOOLEAN:
        e->value.b = value.b;
        break;
    default:
        printk("could not add the element: unsupported type");
        return 0;
    }
    
    hlist_add_head_rcu(&e->node, &rcutable[idx]);
    
    if (value.type == LUA_TSTRING)
        printk("added pair %s - %s to bucket %d", key, value.s, idx);
    else {
        if (value.type == LUA_TNUMBER)
            printk("added pair %s - %d to bucket %d", key, value.i, idx);
        else printk("added pair %s - %d to bucket %d", key, value.b, idx);
    }
    
    return 0;
}


static int rcu_each(lua_State *L) {
    int bkt = 0;
    struct element *e = NULL;
    
    /*  Whenever we call a function with lua_pcall,
     *  both the arguments and the function are removed from the stack.
     *  Since we want to call the function for each element, we must copy
     *  the function on each iteration.
     *  Also, lua_copy actually replaces an element on the stack, so
     *  we push a nil to guarantee a valid index.
     */
    
    rcu_read_lock();
    hash_for_each_rcu(rcutable, bkt, e, node) {
        lua_pushnil(L);
        lua_copy(L, 1, 2);
        if (e->value.type == LUA_TSTRING)
            lua_pushstring(L, e->value.s);                  
        if (e->value.type == LUA_TNUMBER) 
            lua_pushinteger(L, e->value.i);
        if (e->value.type == LUA_TBOOLEAN) 
            lua_pushboolean(L, e->value.b);
        lua_pcall(L, 1, 0, 0);
    }
    rcu_read_unlock();
    
    return 0;
}

static int rcu_delete_element(struct element *e, int idx) {
    hlist_del_rcu(&e->node);
    printk("deleted key %s on bucket %d", e->key, idx);

    spin_unlock(&bucket_lock[idx]);  
    synchronize_rcu();
    
    if (e->value.type == LUA_TSTRING)
        kfree(e->value.s);
                
    kfree(e->key);
    kfree(e);
    
    return 0;
}

static int rcu_replace_element(lua_State *L, struct element *e, 
                                struct tvalue new_value, int idx) {
    struct element *new_e = NULL;
        
    new_e = kmalloc(sizeof(struct element), GFP_ATOMIC);    
    if (!new_e) luaL_error(L, "could not allocate memory");
    
    new_e->key = kmalloc(strlen(e->key) +1, GFP_ATOMIC);
    if (!new_e->key) luaL_error(L, "could not allocate memory");
    strcpy(new_e->key, e->key);
    
    switch (new_value.type) {
    case LUA_TSTRING:
        new_e->value.s = kmalloc(strlen(new_value.s) +1, GFP_ATOMIC);    
        if (!new_e->value.s) luaL_error(L, "could not allocate memory");
        strcpy(new_e->value.s, new_value.s);
        new_e->value.type = LUA_TSTRING;
        break;
    case LUA_TNUMBER:       
        new_e->value.i = new_value.i;
        new_e->value.type = LUA_TNUMBER;
        break;
    case LUA_TBOOLEAN:
        new_e->value.b = new_value.b;
        new_e->value.type = LUA_TBOOLEAN;       
        break;  
    default:
        printk("could not replace the element: unsupported type");
        return 0;
    }
    
    hlist_replace_rcu(&e->node, &new_e->node);

    spin_unlock(&bucket_lock[idx]);   
    synchronize_rcu();
    
    if (e->value.type == LUA_TSTRING)
        kfree(e->value.s);

    kfree(e->key);
    kfree(e);
    
    if (new_value.type == LUA_TSTRING) 
        printk("updated key %s to value %s on bucket %d", new_e->key, new_value.s, idx);    
    else {
        if (new_value.type == LUA_TNUMBER)
            printk("updated key %s to value %d on bucket %d", new_e->key, new_value.i, idx);
        else printk("updated key %s to value %d on bucket %d", new_e->key, new_value.b, idx); 
    }

    return 0;
}

static int rcu_index(lua_State *L) {
    struct element *e;        
    const char *key;
    int idx;
    
    luaL_checktype(L, -1, LUA_TSTRING);
    key = lua_tostring(L, -1);
    idx = hash_str(key) & MASK;       
    
    rcu_read_lock();
    e = rcu_search_element(key, idx);
    if (e != NULL) {
        if (e->value.type == LUA_TSTRING)
            lua_pushstring(L, e->value.s);                  
        if (e->value.type == LUA_TNUMBER) 
            lua_pushinteger(L, e->value.i);                                
        if (e->value.type == LUA_TBOOLEAN)
            lua_pushboolean(L, e->value.b);            
    }
    else lua_pushnil(L);
    rcu_read_unlock();        
                    
    return 1;
}


static int rcu_newindex(lua_State *L) {
    struct element *e;
    const char *key;
    struct tvalue in;
    int idx;
        
    /*  Only strings are allowed for keys.
     *  Value allows for strings, bools and ints or nil (meaning removal).
     *  Raises an error if the user supply a different type.
     */
     
    luaL_checktype(L, -2, LUA_TSTRING);    
    
    if (lua_type(L, -1) > LUA_TSTRING)
        luaL_argerror(L, -1, "expected a string, int, bool or nil for value");
        
    key = lua_tostring(L, -2);
    idx = hash_str(key) & MASK;
    
    in.type = lua_type(L, -1);
    switch (in.type) {
    case LUA_TSTRING:
        in.s = lua_tostring(L, -1);
        break;
    case LUA_TNUMBER:
        in.i = lua_tointeger(L, -1);
        break;
    case LUA_TBOOLEAN:
        in.b = lua_toboolean(L, -1);
        break;
    case LUA_TNIL:
        break;
    default:
        printk("couldn't complete the operation: unsupported type");
        return 0;        
    }                            

    spin_lock(&bucket_lock[idx]);
    e = rcu_search_element(key, idx);
    if (e != NULL && in.type == LUA_TNIL) {
        rcu_delete_element(e, idx);
        return 0;
    }
    
    if (e == NULL && in.type != LUA_TNIL) {
        rcu_add_element(L, key, in, idx);
        spin_unlock(&bucket_lock[idx]);  
        return 0;
    }

    if (e != NULL && in.type != LUA_TNIL) {      
        rcu_replace_element(L, e, in, idx);
        return 0;
    }

    spin_unlock(&bucket_lock[idx]);  
    return 0;
}

static const struct luaL_Reg rcu_funcs[] = {
    {"for_each", rcu_each},
    {NULL, NULL}
};

static const struct luaL_Reg rcu_methods[] = {
    {"__newindex", rcu_newindex},
    {"__index",    rcu_index},
    {NULL, NULL}
};

int luaopen_rcu(lua_State *L) {
    int i;
    
    if (first_time_setup) {
        hash_init(rcutable);        
        for (i = 0; i < NBUCKETS; i++)
            spin_lock_init(&bucket_lock[i]);                                    
        first_time_setup = false;
    }    
    
    luaL_newmetatable(L, "Rcu.hash");
    luaL_setfuncs(L, rcu_methods, 0);        
    luaL_newlib(L, rcu_funcs);
    luaL_setmetatable(L, "Rcu.hash");
    
    return 1;
}
