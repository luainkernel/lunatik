/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/*
* lunatikc: compiles kernel Lua scripts into binary chunks for lunatik.
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

#define LUNATIKC_EXT	".luac"

static const char *progname = "lunatikc";

static void usage(void)
{
	fprintf(stderr, "usage: %s [-s] [-o output] [-n chunkname] input.lua ...\n"
		"  -s             strip debug information\n"
		"  -o output      output file (or directory, with several inputs); default: input" LUNATIKC_EXT "\n"
		"  -n chunkname   chunk name recorded in the dump; default: @input\n", progname);
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

	char *buffer = malloc(n);
	if (buffer != NULL && fread(buffer, 1, n, f) != (size_t)n) {
		free(buffer);
		buffer = NULL;
	}
	fclose(f);
	*size = (size_t)n;
	return buffer;
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

static char *outname(const char *output, const char *input)
{
	const char *base = strrchr(input, '/');
	base = base != NULL ? base + 1 : input;

	size_t n = strlen(base);
	if (n > 4 && strcmp(base + n - 4, ".lua") == 0)
		n -= 4;

	const char *dir = output != NULL ? output : "";
	char *name = malloc(strlen(dir) + 1 + n + sizeof(LUNATIKC_EXT));
	if (name == NULL)
		fail(strerror(ENOMEM));

	if (output == NULL) /* next to the input */
		sprintf(name, "%.*s%.*s" LUNATIKC_EXT, (int)(base - input), input, (int)n, base);
	else
		sprintf(name, "%s/%.*s" LUNATIKC_EXT, dir, (int)n, base);
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

int main(int argc, char **argv)
{
	const char *output = NULL, *chunkname = NULL;
	int strip = 0;
	int i;

	for (i = 1; i < argc && argv[i][0] == '-'; i++) {
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
	if (ninputs < 1)
		usage();
	if (ninputs > 1 && (chunkname != NULL || (output != NULL && !isdir(output))))
		fail("several inputs need a directory as -o and no -n");

	lua_State *L = luaL_newstate();
	if (L == NULL)
		fail("cannot create state");

	for (; i < argc; i++) {
		const char *input = argv[i];
		char *name = (output != NULL && !isdir(output)) ? NULL : outname(output, input);
		compile(L, input, name != NULL ? name : output, chunkname, strip);
		free(name);
	}

	lua_close(L);
	return 0;
}

