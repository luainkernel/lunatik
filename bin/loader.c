/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/*
* lunatik.loader: the libbpf half of `lunatik run`.
*
* The CLI is Lua 5.4 and libbpf is C, so this is the one host module lunatik loads through
* package.cpath. It opens a script's compiled program, pins the maps it declares under the
* script's root, attaches every program to the device the command line named and pins each link,
* which is what keeps the programs attached after the CLI exits.
*
* Every entry point answers nil and a message instead of raising, so the CLI decides what to undo.
*/

#include <errno.h>
#include <limits.h>
#include <net/if.h>
#include <stdarg.h>
#include <stdlib.h>

#include <bpf/libbpf.h>
#include <bpf/libbpf_version.h>

#include <lua.h>
#include <lauxlib.h>

#define LUALOADER_OBJECT	"lunatik.loader.object"

/* the verifier log of a rejected program, which the CLI prints as the error */
#define LUALOADER_LOGSIZE	(1 << 16)

/* one libbpf message, the size libbpf itself formats into */
#define LUALOADER_MESSAGESIZE	128

/* what tells a link's pin from a map's in the same root: bpf_lookup refuses a dot in a bpffs
 * name (kernel/bpf/inode.c), and a map name is a C identifier, so a hyphen cannot collide */
#define LUALOADER_LINK		"-link"

/* bpf_program__attach_tcx is libbpf 1.3.0 (tools/lib/bpf/libbpf.map); below it a SCHED_CLS
 * program has no attach here, and targets() says so before anything is created */
#if LIBBPF_MAJOR_VERSION > 1 || (LIBBPF_MAJOR_VERSION == 1 && LIBBPF_MINOR_VERSION >= 3)
#define LUALOADER_TCX	1
#else
#define LUALOADER_TCX	0
#endif

typedef struct lualoader_object {
	struct bpf_object *object;
	char log[LUALOADER_LOGSIZE];
} lualoader_object_t;

static int lualoader_failure(lua_State *L, const char *format, ...)
{
	va_list args;

	lua_pushnil(L);
	va_start(args, format);
	lua_pushvfstring(L, format, args);
	va_end(args);
	return 2;
}

/* libbpf answers its own codes above 4000 as well as errnos, and strerror knows only the second */
static const char *lualoader_strerror(int err)
{
	static char message[LUALOADER_MESSAGESIZE];

	libbpf_strerror(err, message, sizeof(message));
	return message;
}

/* __gc is reachable from Lua, so a method may find the object already closed */
static lualoader_object_t *lualoader_check(lua_State *L)
{
	lualoader_object_t *loaded = luaL_checkudata(L, 1, LUALOADER_OBJECT);

	luaL_argcheck(L, loaded->object != NULL, 1, "object is closed");
	return loaded;
}

static int lualoader_open(lua_State *L)
{
	const char *path = luaL_checkstring(L, 1);
	lualoader_object_t *loaded = lua_newuserdatauv(L, sizeof(lualoader_object_t), 0);
	LIBBPF_OPTS(bpf_object_open_opts, opts, .kernel_log_buf = loaded->log,
		.kernel_log_size = sizeof(loaded->log));

	loaded->object = NULL; /* the open has not answered yet, and the metatable below arms __gc */
	luaL_setmetatable(L, LUALOADER_OBJECT);
	loaded->object = bpf_object__open_file(path, &opts);
	if (loaded->object == NULL)
		return lualoader_failure(L, "couldn't open %s: %s", path, lualoader_strerror(errno));
	return 1;
}

static int lualoader_gc(lua_State *L)
{
	lualoader_object_t *loaded = luaL_checkudata(L, 1, LUALOADER_OBJECT);

	bpf_object__close(loaded->object);
	loaded->object = NULL;
	return 0;
}

static int lualoader_targets(lua_State *L)
{
	lualoader_object_t *loaded = lualoader_check(L);
	struct bpf_program *program;
	int device = 0;

	bpf_object__for_each_program(program, loaded->object) {
		switch (bpf_program__type(program)) {
		case BPF_PROG_TYPE_XDP:
			break;
		case BPF_PROG_TYPE_SCHED_CLS:
			if (!LUALOADER_TCX)
				return lualoader_failure(L, "tcx needs libbpf 1.3.0");
			break;
		default:
			return lualoader_failure(L, "lunatik doesn't attach a '%s' program",
				bpf_program__section_name(program));
		}
		device = 1;
	}
	lua_createtable(L, device, 0);
	if (device) {
		lua_pushliteral(L, "dev");
		lua_rawseti(L, -2, 1);
	}
	return 1;
}

static int lualoader_load(lua_State *L)
{
	lualoader_object_t *loaded = lualoader_check(L);
	const char *root = luaL_checkstring(L, 2);
	struct bpf_map *map;
	char path[PATH_MAX];

	/* the emitter writes no pinning attribute, so pin_root_path would reach no map */
	bpf_object__for_each_map(map, loaded->object) {
		const char *name = bpf_map__name(map);

		snprintf(path, sizeof(path), "%s/%s", root, name);
		if (bpf_map__set_pin_path(map, path) != 0)
			return lualoader_failure(L, "couldn't pin '%s': %s", name, lualoader_strerror(errno));
	}
	loaded->log[0] = '\0';
	/* log_level 0 with a buffer makes libbpf retry a failed load verbosely into it */
	if (bpf_object__load(loaded->object) != 0)
		return lualoader_failure(L, "%s", loaded->log[0] != '\0' ? loaded->log : lualoader_strerror(errno));
	lua_pushboolean(L, 1);
	return 1;
}

static struct bpf_link *lualoader_link(const struct bpf_program *program, int ifindex)
{
	switch (bpf_program__type(program)) {
	case BPF_PROG_TYPE_XDP:
		return bpf_program__attach_xdp(program, ifindex);
#if LUALOADER_TCX
	case BPF_PROG_TYPE_SCHED_CLS:
		return bpf_program__attach_tcx(program, ifindex, NULL);
#endif
	default:
		errno = ENOTSUP;
		return NULL;
	}
}

static void lualoader_release(struct bpf_link **links, int attached)
{
	while (attached-- > 0)
		bpf_link__destroy(links[attached]);
	free(links);
}

/* BPF_LINK_DETACH takes the program off the device before it returns; dropping the pin's last
 * reference detaches too, but from a work item (bpf_link_put, kernel/bpf/syscall.c) */
static void lualoader_undo(struct bpf_link **links, int attached)
{
	int i;

	for (i = 0; i < attached; i++) {
		bpf_link__detach(links[i]);
		if (bpf_link__pin_path(links[i]) != NULL)
			bpf_link__unpin(links[i]);
	}
	lualoader_release(links, attached);
}

static int lualoader_attach(lua_State *L)
{
	lualoader_object_t *loaded = lualoader_check(L);
	const char *root = luaL_checkstring(L, 2);
	const char *device = luaL_checkstring(L, 3);
	unsigned int ifindex = if_nametoindex(device);
	struct bpf_program *program;
	struct bpf_link **links;
	const char *reason = NULL;
	char path[PATH_MAX];
	int declared = 0, attached = 0;

	if (ifindex == 0)
		return lualoader_failure(L, "couldn't find device '%s'", device);
	bpf_object__for_each_program(program, loaded->object)
		declared++;
	links = calloc(declared, sizeof(struct bpf_link *));
	if (links == NULL)
		return lualoader_failure(L, "%s", lualoader_strerror(ENOMEM));

	bpf_object__for_each_program(program, loaded->object) {
		const char *name = bpf_program__name(program);
		struct bpf_link *link = lualoader_link(program, (int)ifindex);

		if (link == NULL) {
			reason = lua_pushfstring(L, "couldn't attach '%s': %s", name, lualoader_strerror(errno));
			break;
		}
		links[attached++] = link;
		snprintf(path, sizeof(path), "%s/%s" LUALOADER_LINK, root, name);
		if (bpf_link__pin(link, path) != 0) {
			reason = lua_pushfstring(L, "couldn't pin %s: %s", path, lualoader_strerror(errno));
			break;
		}
	}
	if (reason != NULL) {
		lualoader_undo(links, attached);
		lua_pushnil(L);
		lua_insert(L, -2);
		return 2;
	}
	lualoader_release(links, attached); /* the pins hold what the handles held */
	lua_pushboolean(L, 1);
	return 1;
}

static int lualoader_unpin(lua_State *L)
{
	const char *path = luaL_checkstring(L, 1);
	struct bpf_link *link = bpf_link__open(path);
	int err;

	if (link == NULL)
		return lualoader_failure(L, "couldn't open %s: %s", path, lualoader_strerror(errno));
	bpf_link__detach(link);
	err = bpf_link__unpin(link);
	bpf_link__destroy(link);
	if (err != 0)
		return lualoader_failure(L, "couldn't unpin %s: %s", path, lualoader_strerror(-err));
	lua_pushboolean(L, 1);
	return 1;
}

static const luaL_Reg lualoader_mt[] = {
	{"targets", lualoader_targets},
	{"load", lualoader_load},
	{"attach", lualoader_attach},
	{"__gc", lualoader_gc},
	{NULL, NULL}
};

static const luaL_Reg lualoader_lib[] = {
	{"open", lualoader_open},
	{"unpin", lualoader_unpin},
	{NULL, NULL}
};

int luaopen_lunatik_loader(lua_State *L)
{
	/* every failure comes back as a value; libbpf's own stderr would be a second report */
	libbpf_set_print(NULL);
	luaL_newmetatable(L, LUALOADER_OBJECT);
	luaL_setfuncs(L, lualoader_mt, 0);
	lua_pushvalue(L, -1);
	lua_setfield(L, -2, "__index");
	lua_pop(L, 1);
	luaL_newlib(L, lualoader_lib);
	return 1;
}

