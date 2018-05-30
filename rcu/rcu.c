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
    int value;
    struct list_head node;
    struct rcu_head rcu;
};

static LIST_HEAD(numbers);
static spinlock_t num_lock;

static void stackDump(lua_State *L) {
    int i;
    int top = lua_gettop(L); /* depth of the stack */

    for (i = 1; i <= top; i++) { 
        int t = lua_type(L, i);
        switch (t) {
            case LUA_TSTRING: { 
                printk("'%s'", lua_tostring(L, i));
                break;
            }

            case LUA_TBOOLEAN: {
                printk(lua_toboolean(L, i) ? "true" : "false");
                break;
            }
            
            case LUA_TNUMBER: { 
                if (lua_isinteger(L, i)) 
                    printk("%lld", lua_tointeger(L, i));
                else
                    printk("%g", lua_tonumber(L, i));
                break;
            }
            
            default: {
                printk("%s", lua_typename(L, t));
                break;
            }
        }
        printk(" ");
    }
    printk("\n");
}


static int list_add_number(lua_State *L) {
    struct number *n;
    int value = (int) luaL_checkinteger(L, -1);
    
    n = kmalloc(sizeof(struct number), GFP_KERNEL);
    n->value = value;
    
    spin_lock(&num_lock);
    list_add_rcu(&n->node, &numbers);
    spin_unlock(&num_lock);
    
    printk("adding number %d", value);
    return 0;
}

static int list_first_number(lua_State *L) {
    struct number *n = NULL;
    
    rcu_read_lock();
    n = list_first_or_null_rcu(&numbers, struct number, node);
    if (n != NULL) {
        lua_pushinteger(L, n->value);
        rcu_read_unlock();
        return 1;
    }
    
    lua_pushnil(L); //the list is empty
    rcu_read_unlock();
    return 1;
}

static int list_each(lua_State *L) {
    struct number *n;
    
    rcu_read_lock();
    list_for_each_entry_rcu(n, &numbers, node) {
            lua_pushnil(L);
            lua_copy(L, 1, 2);
            lua_pushinteger(L, n->value);
            lua_pcall(L, 1, 0, 0);
    }
    
    rcu_read_unlock();
    return 0;
}

static int list_delete_number(lua_State *L) {
    struct number *n;
    int value = (int) luaL_checkinteger(L, -1);
    
    spin_lock(&num_lock);
    list_for_each_entry(n, &numbers, node) {
        if (n->value == value) {
            list_del_rcu(&n->node);
            spin_unlock(&num_lock);
            
            synchronize_rcu();
            kfree(n);
            printk("number %d deleted", value);
            return 0;
        }
    }
    
    spin_unlock(&num_lock);
    printk("Couldn't find value %d to delete", value);
    return 0;
}



static int list_replace_number(lua_State *L) {
    struct number *n = NULL;
    struct number *old_n = NULL;
    struct number *new_n = NULL;
    
    int old_value = (int) luaL_checkinteger(L, -2);
    int new_value = (int) luaL_checkinteger(L, -1);
    
    spin_lock(&num_lock);
    list_for_each_entry(n, &numbers, node) {
        if (n->value == old_value) {
            old_n = n;
            break;
        }
    }
    
    if (!old_n) {
        spin_unlock(&num_lock);
        lua_pushboolean(L, 0);
        return 1;
    }
    
    new_n = kmalloc(sizeof(struct number), GFP_ATOMIC);
    if (!new_n) {
        spin_unlock(&num_lock);
        lua_pushboolean(L, 0);
        return 1;
    }
    
    memcpy(new_n, old_n, sizeof(struct number));
    new_n->value = new_value;
    
    list_replace_rcu(&old_n->node, &new_n->node);
    spin_unlock(&num_lock);
    
    synchronize_rcu();
    kfree(old_n);
    
    printk("Updated value %d to %d", old_value, new_value);
    lua_pushboolean(L, 1);
    return 1;
}

static int list_is_empty(lua_State *L) {
    struct number *n = NULL;
    
    rcu_read_lock();
    n = list_first_or_null_rcu(&numbers, struct number, node);
    if (n == NULL) {
        lua_pushboolean(L, 1);
        rcu_read_unlock();
        return 1;
    }
    
    lua_pushboolean(L, 0);
    rcu_read_unlock();
    return 1;
}


static int list_search_number(lua_State *L) {
    struct number *n;
    int value = (int) luaL_checkinteger(L, -1);
    
    rcu_read_lock();
    list_for_each_entry_rcu(n, &numbers, node) {
        if (n->value == value) {
            lua_pushboolean(L, 1);
            rcu_read_unlock();
            return 1;
        }
    }
    
    lua_pushboolean(L, 0);
    rcu_read_unlock();    
    return 1;
}


static const struct luaL_Reg rcu_funcs[] = {
    {"add_number",     list_add_number},
    {"first_number",   list_first_number},
    {"for_each",       list_each},
    {"delete_number",  list_delete_number},
    {"replace_number", list_replace_number},
    {"is_empty",       list_is_empty},
    {"search_number",  list_search_number},
    {NULL, NULL}
};

int luaopen_rcu(lua_State *L) {
    spin_lock_init(&num_lock);
    luaL_newlib(L, rcu_funcs);
    return 1;
}
