/*
* SPDX-FileCopyrightText: (c) 2023-2024 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#include <linux/slab.h>
#include <linux/fs.h>

#include <lua.h>
#include <lauxlib.h>

#include <lunatik.h>

typedef struct lunatik_file {
	struct file *file;
	char *buffer;
	loff_t pos;
} lunatik_file;

static const char *lunatik_loader(lua_State *L, void *ud, size_t *size)
{
	lunatik_file *lf = (lunatik_file *)ud;
	ssize_t ret = kernel_read(lf->file, lf->buffer, PAGE_SIZE, &(lf->pos));

	if (unlikely(ret < 0))
		luaL_error(L, "kernel_read failure %I", (lua_Integer)ret);

	*size = (size_t)ret;
	return lf->buffer;
}

int lunatik_loadfile(lua_State *L, const char *filename, const char *mode)
{
	lunatik_file lf = {NULL, NULL, 0};
	int status = LUA_ERRFILE;
	int fnameindex = lua_gettop(L) + 1;  /* index of filename on the stack */

	if (unlikely(lunatik_cannotsleep(L, lunatik_isready(L)))) {
		lua_pushfstring(L, "cannot load file on non-sleepable runtime");
		goto error;
	}

	if (unlikely(filename == NULL) || IS_ERR(lf.file = filp_open(filename, O_RDONLY, 0600))) {
		lua_pushfstring(L, "cannot open %s", filename);
		goto error;
	}

	lf.buffer = kmalloc(PAGE_SIZE, GFP_KERNEL);
	if (lf.buffer == NULL) {
		lua_pushfstring(L, "cannot allocate buffer for %s", filename);
		goto close;
	}

	lua_pushfstring(L, "@%s", filename);
	status = lua_load(L, lunatik_loader, &lf, lua_tostring(L, -1), mode);
	lua_remove(L, fnameindex);

	kfree(lf.buffer);
close:
	filp_close(lf.file, NULL);
error:
	return status;
}
EXPORT_SYMBOL(lunatik_loadfile);

#ifdef MODULE /* see https://lwn.net/Articles/813350/ */
#include <linux/kprobes.h>

static unsigned long (*__lunatik_lookup)(const char *) = NULL;

void *lunatik_lookup(const char *symbol)
{
#ifdef CONFIG_KPROBES
	if (__lunatik_lookup == NULL) {
		struct kprobe kp = {.symbol_name = "kallsyms_lookup_name"};

		if (register_kprobe(&kp) != 0)
			return NULL;

		__lunatik_lookup = (unsigned long (*)(const char *))kp.addr;
		unregister_kprobe(&kp);

		BUG_ON(__lunatik_lookup == NULL);
	}
	return (void *)__lunatik_lookup(symbol);
#else /* CONFIG_KPROBES */
	return NULL;
#endif /* CONFIG_KPROBES */
}
EXPORT_SYMBOL(lunatik_lookup);
#endif /* MODULE */

/* used by lib/luarcu.c */
#include <lua/lstring.h>
EXPORT_SYMBOL(luaS_hash);

