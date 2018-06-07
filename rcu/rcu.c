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
#include <lua/lstring.h>

struct element {
    char *key;
    char *value;
    struct hlist_node node;
    struct rcu_head rcu;
};

#define nbits 3
static DEFINE_HASHTABLE(table, nbits);
static spinlock_t bucket_lock[1 << nbits];

#define hash_str(str)            \
    luaS_hash(str, strlen(str), 0)

static int hash_add_element(lua_State *L) {
    struct element *e;
    const char *key = lua_tostring(L, -2); 
    const char *value = lua_tostring(L, -1);
    unsigned int idx;
    
    e = kmalloc(sizeof(struct element), GFP_KERNEL);
    
    e->key = kmalloc(strlen(key) +1, GFP_KERNEL); //+1 also consider a \0
    strcpy(e->key, key);

    e->value = kmalloc(strlen(value) +1, GFP_KERNEL);
    strcpy(e->value, value);
    
    idx = hash_str(key) % (1 << nbits);
        
    spin_lock(&bucket_lock[idx]);
    hlist_add_head_rcu(&e->node, &table[idx]);
    spin_unlock(&bucket_lock[idx]);
    
    printk("adding pair %s - %s to bucket %d", key, value, idx);
    printk("hash: %u", hash_str(key));
    return 0;
}

static int hash_each(lua_State *L) {
    int bkt = 0;
    struct element *e = NULL;
    hash_for_each_rcu(table, bkt, e, node) {
        printk("[%s] = %s", e->key, e->value);
    }
    return 0;
}

static int hash_delete_element(lua_State *L) {
    struct element *e;
    const char *key = lua_tostring(L, -1);
    int idx = hash_str(key) % 8;
    
    rcu_read_lock();
    hlist_for_each_entry_rcu(e, &table[idx], node) {
        if (strcmp(e->key, key) == 0) {
            spin_lock(&bucket_lock[idx]);
            hlist_del_rcu(&e->node);
            spin_unlock(&bucket_lock[idx]);
            
            rcu_read_unlock();            
            synchronize_rcu();
            kfree(e->key);
            kfree(e->value);
            kfree(e);
            printk("key %s deleted", key);
            return 0;
        }
    }
    
    rcu_read_unlock();
    printk("Couldn't find key %s to delete", key);
    return 0;
}



static int hash_replace_element(lua_State *L) {
    struct element *e = NULL;
    struct element *old_e = NULL;
    struct element *new_e = NULL;
    
    const char *key = lua_tostring(L, -2);
    const char *new_value = lua_tostring(L, -1);
    int idx = hash_str(key) % 8;
           
    rcu_read_lock();
    hlist_for_each_entry_rcu(e, &table[idx], node) {        
        if (strcmp(e->key, key) == 0) {
            old_e = e;
            break;
        }
    }
    
    if (!old_e) { //key wasn't found
        printk("key %s wasn't found", key);
        lua_pushboolean(L, 0);
        rcu_read_unlock();
        return 1;
    }
    
    new_e = kmalloc(sizeof(struct element), GFP_KERNEL);
    if (!new_e) {
        lua_pushboolean(L, 0);
        rcu_read_unlock();
        return 1;
    }
    
    memcpy(new_e, old_e, sizeof(struct element));
    new_e->key = kmalloc(strlen(key) + 1, GFP_KERNEL);
    strcpy(new_e->key, key);
    
    new_e->value = kmalloc(strlen(new_value) + 1, GFP_KERNEL);
    strcpy(new_e->value, new_value);
    
    spin_lock(&bucket_lock[idx]);
    hlist_replace_rcu(&old_e->node, &new_e->node);
    spin_unlock(&bucket_lock[idx]);
    
    rcu_read_unlock();
    synchronize_rcu();
    kfree(old_e->value);
    kfree(old_e->key);
    kfree(old_e);
    
    printk("Updated key %s to value %s on bucket %d", key, new_value, idx);
    lua_pushboolean(L, 1);
    return 1;
}

static int hash_search_element(lua_State *L) {
    struct element *e;
        
    const char *key = lua_tostring(L, -1);
    int idx = hash_str(key) % 8;
    
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


static const struct luaL_Reg rcu_funcs[] = {
    {"add",      hash_add_element},
    {"for_each", hash_each},
    {"delete",   hash_delete_element},
    {"replace",  hash_replace_element},
    {"search",   hash_search_element},
    {NULL, NULL}
};

int luaopen_rcu(lua_State *L) {
    int i;
    hash_init(table);
    
    for (i = 0; i < (1 << nbits); i++)
        spin_lock_init(&bucket_lock[i]);
        
    luaL_newlib(L, rcu_funcs);
    return 1;
}
