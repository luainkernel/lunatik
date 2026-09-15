/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/*
* lunatikc: compiles kernel Lua scripts into binary chunks for lunatik, and Lua program files
* into BPF objects.
*
* Built from the same lua/ sources and _KERNEL configuration as lunatik.ko,
* so that its chunks match the kernel's opcode set and number format.
*/

#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

#define LUNATIKC_PROTO	"luaebpf.proto"

int luaopen_luaebpf_proto(lua_State *L);

#define LUNATIKC_EXT	".luac"
#define LUNATIKC_BPF_EXT	".o"

static const char *progname = "lunatikc";

static void usage(void)
{
	fprintf(stderr, "usage: %s [-s] [-o output] [-n chunkname] input.lua ...\n"
		"       %s bpf [-o output] input.bpf.lua\n"
		"  -s             strip debug information\n"
		"  -o output      output file (or directory, with several inputs); default: input" LUNATIKC_EXT "\n"
		"  -n chunkname   chunk name recorded in the dump; default: @input\n"
		"  bpf            compile a program file into a BPF object; default: input" LUNATIKC_BPF_EXT "\n",
		progname, progname);
	exit(2);
}

static void fail(const char *msg)
{
	fprintf(stderr, "%s: %s\n", progname, msg);
	exit(1);
}

static char *readfile(const char *path, size_t *size)
{
	FILE *f = fopen(path, "rb");
	if (f == NULL || fseek(f, 0, SEEK_END) != 0)
		return NULL;

	long n = ftell(f);
	if (n < 0 || fseek(f, 0, SEEK_SET) != 0)
		return NULL;

	char *buffer = malloc(n + 1); /* n may be 0 */
	if (buffer != NULL && fread(buffer, 1, n, f) != (size_t)n) {
		free(buffer);
		buffer = NULL;
	}
	fclose(f);
	*size = (size_t)n;
	return buffer;
}

/* what lunatik_loadfile is to the kernel: lua/ fences the C library's luaL_loadfilex out under
 * _KERNEL, so package's Lua searcher has none until the driver supplies one */
int lunatikc_loadfile(lua_State *L, const char *filename, const char *mode)
{
	size_t size;
	char *source = filename != NULL ? readfile(filename, &size) : NULL;

	if (source == NULL) {
		lua_pushfstring(L, "cannot open %s", filename);
		return LUA_ERRFILE;
	}

	char name[PATH_MAX + 1];
	snprintf(name, sizeof(name), "@%s", filename);

	int status = luaL_loadbufferx(L, source, size, name, mode);
	free(source);
	return status;
}

static int writer(lua_State *L, const void *p, size_t size, void *ud)
{
	(void)L;
	return size != 0 && fwrite(p, size, 1, (FILE *)ud) != 1;
}

static int isdir(const char *path)
{
	struct stat st;
	return stat(path, &st) == 0 && S_ISDIR(st.st_mode);
}

static char *outname(const char *output, const char *input, const char *ext)
{
	const char *base = strrchr(input, '/');
	base = base != NULL ? base + 1 : input;

	size_t n = strlen(base);
	if (n > 4 && strcmp(base + n - 4, ".lua") == 0)
		n -= 4;

	size_t prefix = output != NULL ? strlen(output) + 1 : (size_t)(base - input);
	char *name = malloc(prefix + n + strlen(ext) + 1);
	if (name == NULL)
		fail(strerror(ENOMEM));

	if (output == NULL) /* next to the input */
		sprintf(name, "%.*s%.*s%s", (int)(base - input), input, (int)n, base, ext);
	else
		sprintf(name, "%s/%.*s%s", output, (int)n, base, ext);
	return name;
}

static void compile(lua_State *L, const char *input, const char *output, const char *chunkname, int strip)
{
	size_t size;
	char *source = readfile(input, &size);
	if (source == NULL) {
		fprintf(stderr, "%s: cannot read %s: %s\n", progname, input, strerror(errno));
		exit(1);
	}

	char name[PATH_MAX + 1];
	if (chunkname == NULL) {
		snprintf(name, sizeof(name), "@%s", input);
		chunkname = name;
	}

	if (luaL_loadbufferx(L, source, size, chunkname, "t") != LUA_OK)
		fail(lua_tostring(L, -1));
	free(source);

	FILE *f = fopen(output, "wb");
	if (f == NULL) {
		fprintf(stderr, "%s: cannot write %s: %s\n", progname, output, strerror(errno));
		exit(1);
	}

	int ret = lua_dump(L, writer, f, strip);
	if (ret != 0 || fclose(f) != 0) {
		remove(output);
		fprintf(stderr, "%s: cannot write %s\n", progname, output);
		exit(1);
	}
	lua_pop(L, 1);
}

/* one line per call into the kernel Lua runtime, which the compiler collected as it lowered them */
static void report(lua_State *L, int ix)
{
	lua_Integer i, n = luaL_len(L, ix);

	for (i = 1; i <= n; i++) {
		lua_geti(L, ix, i);
		printf("%s\n", lua_tostring(L, -1));
		lua_pop(L, 1);
	}
}

/* the translator is Lua (luaebpf/); the driver stands up the state it needs and writes what it
 * returns, so a refusal raises before any file exists */
static void bpf(const char *input, const char *output)
{
	lua_State *L = luaL_newstate();
	if (L == NULL)
		fail("cannot create state");
	luaL_openlibs(L);
	luaL_requiref(L, LUNATIKC_PROTO, luaopen_luaebpf_proto, 0);
	lua_pop(L, 1);

	lua_getglobal(L, "require");
	lua_pushliteral(L, "luaebpf");
	if (lua_pcall(L, 1, 1, 0) != LUA_OK)
		fail(lua_tostring(L, -1));

	lua_getfield(L, -1, "compile");
	lua_pushstring(L, input);
	if (lua_pcall(L, 1, 2, 0) != LUA_OK)
		fail(lua_tostring(L, -1));

	size_t size;
	const char *object = lua_tolstring(L, -2, &size);
	if (object == NULL)
		fail("luaebpf.compile returned no object");

	FILE *f = fopen(output, "wb");
	if (f == NULL || fwrite(object, 1, size, f) != size || fclose(f) != 0) {
		if (f != NULL)
			remove(output);
		fprintf(stderr, "%s: cannot write %s: %s\n", progname, output, strerror(errno));
		exit(1);
	}
	report(L, -1);
	lua_close(L);
}

int main(int argc, char **argv)
{
	const char *output = NULL, *chunkname = NULL;
	int strip = 0;
	int i;

	int bpfmode = argc > 1 && strcmp(argv[1], "bpf") == 0;
	for (i = 1 + bpfmode; i < argc && argv[i][0] == '-'; i++) {
		if (strcmp(argv[i], "-s") == 0)
			strip = 1;
		else if (strcmp(argv[i], "-o") == 0 && i + 1 < argc)
			output = argv[++i];
		else if (strcmp(argv[i], "-n") == 0 && i + 1 < argc)
			chunkname = argv[++i];
		else
			usage();
	}

	int ninputs = argc - i;
	if (ninputs < 1 || (bpfmode && (ninputs > 1 || strip || chunkname != NULL)))
		usage();
	if (ninputs > 1 && (chunkname != NULL || (output != NULL && !isdir(output))))
		fail("several inputs need a directory as -o and no -n");

	if (bpfmode) {
		char *name = (output != NULL && !isdir(output)) ? NULL : outname(output, argv[i], LUNATIKC_BPF_EXT);
		bpf(argv[i], name != NULL ? name : output);
		free(name);
		return 0;
	}

	lua_State *L = luaL_newstate();
	if (L == NULL)
		fail("cannot create state");
	luaL_openlibs(L);

	for (; i < argc; i++) {
		const char *input = argv[i];
		char *name = (output != NULL && !isdir(output)) ? NULL : outname(output, input, LUNATIKC_EXT);
		compile(L, input, name != NULL ? name : output, chunkname, strip);
		free(name);
	}

	lua_close(L);
	return 0;
}

