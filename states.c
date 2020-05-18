#include <linux/hashtable.h>
#include <linux/types.h>
#include <linux/kernel.h>
#include <linux/module.h>
#include "states.h"
#include "klua_conf.h"


DECLARE_HASHTABLE(states_table, MAX_STATES_COUNT);

static __u32 states_counter = 0;

static __u32 hash_func(const char * text)
{
    __u32 key = 0;
    char temp;
    while((temp = *text++)){
        key += temp;
    }

    return key;
}

int klua_createstate(const char *name){
	struct klua_state *kls;

	kls = kmalloc(sizeof(struct klua_state), GFP_ATOMIC);

	kls->L = luaL_newstate();
	strcpy(kls->name, name);

	if (hash_empty(states_table)){
		hash_init(states_table);
	}

	hash_add(states_table, &(kls->node), hash_func(name));
	states_counter++;

	return 1;
}

void klua_liststates(void){
	__u32 bucket;
	struct klua_state *curr;
	hash_for_each(states_table, bucket, curr, node){
		printk(KERN_INFO "State name: %s\n", curr->name);
	}
}
