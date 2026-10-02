/*
* SPDX-FileCopyrightText: (c) 2023-2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#include <linux/slab.h>
#include <linux/fs.h>
#include <linux/version.h>
#include <linux/sched/task_stack.h>
#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 7, 0)
#include <linux/errname.h>
#endif

#include <lua.h>
#include <lauxlib.h>

#include <lunatik.h>
#include "lunatik_core.h"

typedef struct lunatik_file {
	struct file *file;
	char *buffer;
	loff_t pos;
} lunatik_file;

static const char *lunatik_loader(lua_State *L, void *ud, size_t *size)
{
	lunatik_file *lf = (lunatik_file *)ud;
	ssize_t ret;

	lunatik_tryret(L, ret, kernel_read, lf->file, lf->buffer, PAGE_SIZE, &(lf->pos));
	*size = (size_t)ret;
	return lf->buffer;
}

int lunatik_loadfile(lua_State *L, const char *filename, const char *mode)
{
	lunatik_file lf = {NULL, NULL, 0};
	int status = LUA_ERRFILE;
	int fnameindex = lua_gettop(L) + 1;  /* index of filename on the stack */

	if (unlikely(lunatik_cannotsleep(L, lunatik_isready(lunatik_toruntime(L))))) {
		lua_pushliteral(L, LUNATIK_ERR_ARMED);
		goto error;
	}

	if (unlikely(filename == NULL)) {
		lua_pushfstring(L, "cannot open %s", filename);
		goto error;
	}

	lua_pushfstring(L, "@%s", filename); /* nothing to release is held while this can raise */

	if (IS_ERR(lf.file = filp_open(filename, O_RDONLY, 0600))) {
		lua_pushfstring(L, "cannot open %s: ", filename);
		lunatik_pusherrname(L, PTR_ERR(lf.file));
		lua_concat(L, 2);
		goto remove;
	}

	lf.buffer = kmalloc(PAGE_SIZE, GFP_KERNEL);
	if (lf.buffer == NULL) {
		filp_close(lf.file, NULL);
		lua_pushliteral(L, "not enough memory");
		status = LUA_ERRMEM;
		goto remove;
	}

	status = lua_load(L, lunatik_loader, &lf, lua_tostring(L, fnameindex), mode);

	kfree(lf.buffer);
	filp_close(lf.file, NULL);
remove:
	lua_remove(L, fnameindex); /* the chunk name */
error:
	return status;
}
EXPORT_SYMBOL(lunatik_loadfile);

#define LUNATIK_MAXCCALLS	200
#define LUNATIK_CSTACK		(THREAD_SIZE / 8 * 5)
#define LUNATIK_CSTACKMIN	(THREAD_SIZE / 16)
#define LUNATIK_CSTACKSLACK	(THREAD_SIZE / 8)
#define LUNATIK_CSTACKFLOOR	(THREAD_SIZE / 4)

/* Lua raises "C stack overflow" at count, "error in error handling" at 0, and neither at count + 1 */
long long lunatik_maxccalls(lua_State *L, unsigned int count)
{
	unsigned long cstack = lunatik_cstack(lunatik_toruntime(L));
	unsigned long room = current_stack_pointer - (unsigned long)task_stack_page(current);
	long used = cstack != 0 ? (long)(cstack - current_stack_pointer) : 0;

	if (room < THREAD_SIZE)
		used = max(used, (long)(LUNATIK_CSTACK + LUNATIK_CSTACKFLOOR - room));
	if (used < LUNATIK_CSTACK - LUNATIK_CSTACKMIN)
		return LUNATIK_MAXCCALLS;
	if (used < LUNATIK_CSTACK)
		return count + 1;
	return used < LUNATIK_CSTACK + LUNATIK_CSTACKSLACK ? count : 0;
}

void lunatik_pusherrname(lua_State *L, int err)
{
    err = abs(err);
#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 7, 0)
    const char *name = errname(err);
    lua_pushstring(L, name ? name : "unknown");
#else
    char buf[LUAL_BUFFERSIZE];
    snprintf(buf, sizeof(buf), "%pe", ERR_PTR(-err)); /* %pe keeps the sign, e.g. "-ENOENT" */
    lua_pushstring(L, buf[1] == 'E' ? buf + 1 : "unknown");
#endif
}
EXPORT_SYMBOL(lunatik_pusherrname);

#ifdef MODULE /* see https://lwn.net/Articles/813350/ */
#include <linux/kprobes.h>

#include "lunatik_cfi.h"

static unsigned long (*__lunatik_lookup)(const char *) = NULL;

void lunatik_resolve(void)
{
#ifdef CONFIG_KPROBES
	struct kprobe kp = {.symbol_name = "kallsyms_lookup_name"};

	if (register_kprobe(&kp) != 0)
		return;

	__lunatik_lookup = (unsigned long (*)(const char *))lunatik_cfi_entry(kp.addr);
	unregister_kprobe(&kp);
#endif /* CONFIG_KPROBES */
}

void *lunatik_lookup(const char *symbol)
{
	return __lunatik_lookup == NULL ? NULL : (void *)lunatik_cfi_call(__lunatik_lookup(symbol));
}
EXPORT_SYMBOL(lunatik_lookup);
#endif /* MODULE */

#if BITS_PER_LONG == 32
/* require by lib/lualinux.c */
EXPORT_SYMBOL(__moddi3);
#endif /* BITS_PER_LONG == 32 */

