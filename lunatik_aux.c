/*
* Copyright (c) 2023 ring-0 Ltda.
*
* Permission is hereby granted, free of charge, to any person obtaining
* a copy of this software and associated documentation files (the
* "Software"), to deal in the Software without restriction, including
* without limitation the rights to use, copy, modify, merge, publish,
* distribute, sublicense, and/or sell copies of the Software, and to
* permit persons to whom the Software is furnished to do so, subject to
* the following conditions:
*
* The above copyright notice and this permission notice shall be
* included in all copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
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

	if (unlikely(!lunatik_cansleep(L))) {
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

/* used by lib/luarcu.c */
#include <lua/lstring.h>
EXPORT_SYMBOL(luaS_hash);

