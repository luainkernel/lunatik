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

#include "lua/lua.h"
#include "lua/lauxlib.h"

typedef struct LoadF {
  struct file *file;
  char *buffer;
  loff_t pos;
} LoadF;

static const char *getF (lua_State *L, void *ud, size_t *size) {
  LoadF *lf = (LoadF *)ud;
  ssize_t ret = kernel_read(lf->file, lf->buffer, PAGE_SIZE, &(lf->pos));

  if (unlikely(ret < 0))
    luaL_error(L, "kernel_read failure %lld", (long long)ret);

  *size = (size_t)ret;
  return lf->buffer;
}

LUALIB_API int luaL_loadfile (lua_State *L, const char *filename) {
  LoadF lf;
  int status = LUA_ERRFILE;
  int fnameindex = lua_gettop(L) + 1;  /* index of filename on the stack */

  if (unlikely(filename == NULL) ||
      IS_ERR(lf.file = filp_open(filename, O_RDONLY, 0600))) {
    lua_pushfstring(L, "cannot open %s", filename);
    goto errfile;
  }

  lf.buffer = kmalloc(PAGE_SIZE, GFP_KERNEL);
  if (lf.buffer == NULL) {
    lua_pushfstring(L, "cannot allocate buffer for %s", filename);
    goto closefile;
  }

  lua_pushfstring(L, "@%s", filename);
  status = lua_load(L, getF, &lf, lua_tostring(L, -1), NULL);
  lua_remove(L, fnameindex);

  kfree(lf.buffer);
closefile:
  filp_close(lf.file, NULL);
errfile:
  return status;
}
EXPORT_SYMBOL(luaL_loadfile);

