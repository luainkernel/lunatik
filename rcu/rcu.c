#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/slab.h>
#include <linux/list.h>
#include <linux/rculist.h>
#include <linux/spinlock.h>
#include <linux/preempt.h>

#include <lua/lua.h>
#include <lua/lauxlib.h>
#include <lua/lualib.h>

struct number {
    int key;
    int value;
    struct list_head node;
    struct rcu_head rcu;
};

static LIST_HEAD(numbers);
static spinlock_t num_lock;

static int add_number(lua_State *L) {
    struct number *n;
    int key = (int) luaL_checkinteger(L, -2);
    int value = (int) luaL_checkinteger(L, -1);
    
    n = (struct number *) lua_newuserdata(L, sizeof(struct number));
    n->key = key;
    n->value = value;
    
    spin_lock(&num_lock);
    list_add_rcu(&n->node, &numbers);
    spin_unlock(&num_lock);
    
    printk("adding pair %d - %d", key, value);
    return 1;
}

static int search_number(lua_State *L) {
    struct number *n;
    int key = (int) luaL_checkinteger(L, -1);
    
    rcu_read_lock();
    list_for_each_entry_rcu(n, &numbers, node) {
        if (n->key == key) {
            lua_pushinteger(L, n->value);
            rcu_read_unlock();
            return 1;
        }
    }
    
    rcu_read_unlock();    
    lua_pushnil(L);
    return 1;
}

static int delete_number(lua_State *L) {
    struct number *n;
    int key = (int) luaL_checkinteger(L, -1);
    
    spin_lock(&num_lock);
    list_for_each_entry(n, &numbers, node) {
        if (n->key == key) {
            list_del_rcu(&n->node);
            spin_unlock(&num_lock);
            
            synchronize_rcu();
            kfree(n);
            printk("pair %d - %d deleted", key, value);
            return 0;
        }
    }
    
    spin_unlock(&num_lock);
    printk("Couldn't find key %d to delete", key);
    return 0;
}

static int update_number(lua_State *L) {
    struct number *n = NULL;
    struct number *old_n = NULL;
    struct number *new_n = NULL;
    
    int key = (int) luaL_checkinteger(L, -2);
    int value = (int) luaL_checkinteger(L, -1);
    
    spin_lock(&num_lock);
    list_for_each_entry(n, &numbers, node) {
        if (n->key == key) {
            old_n = n;
            break;
        }
    }
    
    if (!old_n) {
        spin_unlock(&num_lock);
        lua_pushnil(L);
        return 1;
    }
    
    new_n = kmalloc(sizeof(struct number), GFP_ATOMIC);
    if (!new_n) {
        spin_unlock(&num_lock);
        lua_pushnil(L);
        return 1;
    }
    
    memcpy(new_n, old_n, sizeof(struct number));
    new_n->value = value;
    
    list_replace_rcu(&old_n->node, &new_n->node);
    spin_unlock(&num_lock);
    
    synchronize_rcu();
    kfree(old_n);
    
    printk("Updated key %d with value %d", key, value);
    lua_pushboolean(L, 1); //sucess
    return 1;
}

static int my_read_lock(lua_State *L) {
    printk(KERN_INFO "read_lock from C");
    return 0;
}

static const struct luaL_Reg rcu_funcs[] = {
    {"my_read_lock", my_read_lock},
    {"add_number", add_number},
    {"search_number", search_number},
    {"delete_number", delete_number},
    {"update_number", update_number},
    {NULL, NULL}
};

int luaopen_rcu(lua_State *L) {
    luaL_newlib(L, rcu_funcs);
    return 1;
}
