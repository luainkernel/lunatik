#include <linux/hashtable.h>
#include <linux/types.h>
#include <linux/kernel.h>
#include <linux/module.h>
#include <lualib.h>
#include "states.h"
#include "klua_conf.h"


DECLARE_HASHTABLE(states_table, MAX_STATES_COUNT);

static __u32 states_counter = 0;

static __u32 hash_func(const char * text){
    __u32 key = 0;
    char temp;
    while((temp = *text++)){
        key += temp;
    }

    return key;
}

static struct klua_state * get_state(const char *name){
    __u32 key;
    __u32 smaller;
    struct klua_state *curr;

    key = hash_func(name);

    hash_for_each_possible(states_table, curr, node, key){
        
        smaller = strlen(name) < strlen(curr->name) ? strlen(name) : strlen(curr->name);

		if (!strncmp(curr->name, name, smaller)){
			return curr;
		}else{
			continue;
		}

    }
    return NULL;
}

int klua_createstate(const char *name){
	struct klua_state *kls;

	if(get_state(name) != NULL){
		printk(KERN_INFO "klua: State %s already exists\n", name);
		return STATE_CREATION_ERROR;
	}

	kls = kmalloc(sizeof(struct klua_state), GFP_ATOMIC);

	if(kls == NULL){
		printk(KERN_INFO "klua: Failed to allocated memory for state %s\n", name);
		return STATE_CREATION_ERROR;
	}

	kls->L = luaL_newstate();
	strcpy(kls->name, name);

	if (hash_empty(states_table)){
		hash_init(states_table);
	}

	hash_add(states_table, &(kls->node), hash_func(name));
	states_counter++;

	return STATE_CREATION_SUCCESS;
}

void klua_liststates(void){
	__u32 bucket;
	struct klua_state *curr;
	hash_for_each(states_table, bucket, curr, node){
		printk(KERN_INFO "State name: %s\n", curr->name);
	}
}

int klua_deletestate(const char *name){
	struct klua_state *curr;
	
	curr = get_state(name);

	if(curr == NULL){
		printk(KERN_INFO "klua: State %s not found\n", name);
		return STATE_DELETION_ERROR;
	}

	printk(KERN_INFO "klua: Deleting the following state: %s\n", curr->name);
	lua_close(curr->L);
	hash_del(&(curr->node));
	states_counter--;

	return STATE_DELETION_SUCCESS;
}

int klua_execute(const char *name, const char *code){
	struct klua_state *kls = get_state(name);

	if (kls != NULL){
		luaL_openlibs(kls->L);
		luaL_dostring(kls->L, code);
	}else{
		printk(KERN_INFO "klua: State %s not found\n", name);
	}

	return 1;
}