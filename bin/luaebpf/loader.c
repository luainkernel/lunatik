/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/*
* luaebpf.loader: the libbpf half of `lunatik run`, a C module of the CLI's Lua. It opens a
* script's compiled program, pins the maps the program declares under the script's root, attaches
* every program to a device and pins each link, which keeps the program attached once the command
* has exited, and reads back an entry of a pinned map. Every function answers nil and a message
* rather than raising, so the CLI decides what to undo.
*/

#include <errno.h>
#include <net/if.h>
#include <stdarg.h>
#include <string.h>
#include <unistd.h>

#include <bpf/bpf.h>
#include <bpf/libbpf.h>

#include <lua.h>
#include <lauxlib.h>

/* below 1.0 a failed call answers an error pointer by default, which every NULL check here misses */
#if LIBBPF_MAJOR_VERSION < 1
#error "luaebpf.loader needs libbpf 1.0"
#endif

#define LUALOADER_OBJECT	"luaebpf.loader"

/* the verifier's log of a rejected program, which the CLI prints as the error */
#define LUALOADER_LOGSIZE	(1 << 16)

/* bpffs refuses a dot in a name (bpf_lookup), and a map name is a C identifier, so a hyphen tells
 * a link's pin from a map's */
#define LUALOADER_LINK		"%s/%s-link"

/* the section the compiler lays the line of each place a stop counts at in, whose map is pinned
 * beside the map of the counts under a name of a link's kind */
#define LUALOADER_PLACES	".data.luaebpf_errors"
#define LUALOADER_LINES		"%s/luaebpf_errors-lines"

#define LUALOADER_TCX		"tcx/"

/* bpf_program__attach_tcx, and the "tcx/" sections it attaches, are libbpf 1.3.0 */
#define LUALOADER_HASTCX	(LIBBPF_MAJOR_VERSION > 1 || \
	(LIBBPF_MAJOR_VERSION == 1 && LIBBPF_MINOR_VERSION >= 3))

typedef struct lualoader_s {
	struct bpf_object *object;
	char log[LUALOADER_LOGSIZE];
} lualoader_t;

static int lualoader_fail(lua_State *L, const char *format, ...)
{
	va_list args;

	lua_pushnil(L);
	va_start(args, format);
	lua_pushvfstring(L, format, args);
	va_end(args);
	return 2;
}

/* libbpf answers codes of its own above 4000, which strerror does not know */
static const char *lualoader_strerror(int err)
{
	static char message[128];

	libbpf_strerror(err, message, sizeof(message));
	return message;
}

static inline int lualoader_istcx(const struct bpf_program *program)
{
	return strncmp(bpf_program__section_name(program), LUALOADER_TCX, strlen(LUALOADER_TCX)) == 0;
}

static struct bpf_link *lualoader_attachprogram(const struct bpf_program *program, int ifindex)
{
#if LUALOADER_HASTCX
	if (lualoader_istcx(program))
		return bpf_program__attach_tcx(program, ifindex, NULL);
#endif
	return bpf_program__attach_xdp(program, ifindex);
}

static int lualoader_open(lua_State *L)
{
	const char *path = luaL_checkstring(L, 1);
	lualoader_t *loader = lua_newuserdatauv(L, sizeof(lualoader_t), 0);
	LIBBPF_OPTS(bpf_object_open_opts, opts, .kernel_log_buf = loader->log,
		.kernel_log_size = sizeof(loader->log));
	struct bpf_program *program;

	loader->object = NULL; /* the metatable arms __gc before the open answers */
	loader->log[0] = '\0';
	luaL_setmetatable(L, LUALOADER_OBJECT);
	loader->object = bpf_object__open_file(path, &opts);
	if (loader->object == NULL)
		return lualoader_fail(L, "couldn't open %s: %s", path, lualoader_strerror(errno));
	/* below 1.3.0 libbpf reads no program type from the section, and the load fails with EINVAL */
	bpf_object__for_each_program(program, loader->object)
		if (!LUALOADER_HASTCX && lualoader_istcx(program))
			return lualoader_fail(L, "tcx needs libbpf 1.3.0");
	return 1;
}

static int lualoader_gc(lua_State *L)
{
	lualoader_t *loader = luaL_checkudata(L, 1, LUALOADER_OBJECT);

	bpf_object__close(loader->object);
	return 0;
}

static int lualoader_load(lua_State *L)
{
	lualoader_t *loader = luaL_checkudata(L, 1, LUALOADER_OBJECT);
	const char *root = luaL_checkstring(L, 2);
	struct bpf_map *lines = bpf_object__find_map_by_name(loader->object, LUALOADER_PLACES);
	struct bpf_map *map;

	/* the emitter writes no pinning attribute, so pin_root_path would reach no map */
	bpf_object__for_each_map(map, loader->object) {
		const char *path;

		if (map == lines)
			path = lua_pushfstring(L, LUALOADER_LINES, root);
		/* .data, which no script opens, and whose dotted name bpffs refuses */
		else if (bpf_map__is_internal(map))
			continue;
		else
			path = lua_pushfstring(L, "%s/%s", root, bpf_map__name(map));
		if (bpf_map__set_pin_path(map, path) != 0)
			return lualoader_fail(L, "couldn't pin %s: %s", path, lualoader_strerror(errno));
		lua_pop(L, 1);
	}
	/* with a buffer and no log level, libbpf retries a failed load verbosely into the buffer */
	if (bpf_object__load(loader->object) != 0)
		return lualoader_fail(L, "%s", loader->log[0] != '\0' ? loader->log : lualoader_strerror(errno));
	lua_pushboolean(L, 1);
	return 1;
}

static int lualoader_attach(lua_State *L)
{
	lualoader_t *loader = luaL_checkudata(L, 1, LUALOADER_OBJECT);
	const char *root = luaL_checkstring(L, 2);
	const char *device = luaL_checkstring(L, 3);
	unsigned int ifindex = if_nametoindex(device);
	struct bpf_program *program;

	if (ifindex == 0)
		return lualoader_fail(L, "couldn't find device %s", device);
	bpf_object__for_each_program(program, loader->object) {
		const char *name = bpf_program__name(program);
		const char *path = lua_pushfstring(L, LUALOADER_LINK, root, name);
		struct bpf_link *link = lualoader_attachprogram(program, (int)ifindex);
		int err;

		if (link == NULL)
			return lualoader_fail(L, "couldn't attach %s: %s", name, lualoader_strerror(errno));
		err = bpf_link__pin(link, path);
		bpf_link__destroy(link); /* closes the link: its pin holds it, or the close detaches it */
		if (err != 0)
			return lualoader_fail(L, "couldn't pin %s: %s", path, lualoader_strerror(err));
		lua_pop(L, 1);
	}
	lua_pushboolean(L, 1);
	return 1;
}

/* the release an unlinked pin leaves detaches from a work item (bpf_link_put), this in the call */
static int lualoader_detach(lua_State *L)
{
	const char *path = luaL_checkstring(L, 1);
	struct bpf_link *link = bpf_link__open(path);
	int err;

	if (link == NULL)
		return lualoader_fail(L, "couldn't open %s: %s", path, lualoader_strerror(errno));
	err = bpf_link__detach(link);
	bpf_link__destroy(link);
	if (err != 0)
		return lualoader_fail(L, "couldn't detach %s: %s", path, lualoader_strerror(err));
	lua_pushboolean(L, 1);
	return 1;
}

static inline int lualoader_ispercpu(__u32 type)
{
	return type == BPF_MAP_TYPE_PERCPU_ARRAY || type == BPF_MAP_TYPE_PERCPU_HASH ||
		type == BPF_MAP_TYPE_LRU_PERCPU_HASH || type == BPF_MAP_TYPE_PERCPU_CGROUP_STORAGE;
}

/* nil, the message and the error number, as io.open answers, which tells a path that pins nothing */
static int lualoader_failerrno(lua_State *L, const char *format, const char *path, int err)
{
	lualoader_fail(L, format, path, lualoader_strerror(err));
	lua_pushinteger(L, err);
	return 3;
}

/* the bytes of the entry at the index of the map, or a sequence of each possible CPU's */
static int lualoader_entry(lua_State *L, int map, const char *path, __u32 index)
{
	struct bpf_map_info info;
	__u32 size = sizeof(info);
	int ncpus = 1, percpu, cpu;
	size_t stride;
	char *value;

	memset(&info, 0, sizeof(info));
	if (bpf_obj_get_info_by_fd(map, &info, &size) != 0)
		return lualoader_failerrno(L, "couldn't read %s: %s", path, errno);
	percpu = lualoader_ispercpu(info.type);
	if (percpu && (ncpus = libbpf_num_possible_cpus()) < 0)
		return lualoader_failerrno(L, "couldn't count the CPUs of %s: %s", path, -ncpus);
	/* round_up(value_size, 8), as bpf_map_value_size @ kernel/bpf/syscall.c spaces the CPUs' values */
	stride = percpu ? (info.value_size + 7) & ~7U : info.value_size;
	value = lua_newuserdatauv(L, stride * ncpus, 0);
	if (bpf_map_lookup_elem(map, &index, value) != 0)
		return lualoader_failerrno(L, "couldn't read %s: %s", path, errno);
	if (!percpu) {
		lua_pushlstring(L, value, info.value_size);
		return 1;
	}
	lua_createtable(L, ncpus, 0);
	for (cpu = 0; cpu < ncpus; cpu++) {
		lua_pushlstring(L, value + stride * cpu, info.value_size);
		lua_rawseti(L, -2, cpu + 1);
	}
	return 1;
}

static int lualoader_lookup(lua_State *L)
{
	const char *path = luaL_checkstring(L, 1);
	__u32 index = (__u32)luaL_checkinteger(L, 2);
	int map = bpf_obj_get(path), ret;

	if (map < 0)
		return lualoader_failerrno(L, "couldn't open %s: %s", path, errno);
	ret = lualoader_entry(L, map, path, index);
	close(map);
	return ret;
}

static const luaL_Reg lualoader_mt[] = {
	{"load", lualoader_load},
	{"attach", lualoader_attach},
	{"__gc", lualoader_gc},
	{NULL, NULL}
};

static const luaL_Reg lualoader_lib[] = {
	{"open", lualoader_open},
	{"detach", lualoader_detach},
	{"lookup", lualoader_lookup},
	{NULL, NULL}
};

int luaopen_luaebpf_loader(lua_State *L)
{
	luaL_newmetatable(L, LUALOADER_OBJECT);
	luaL_setfuncs(L, lualoader_mt, 0);
	lua_pushvalue(L, -1);
	lua_setfield(L, -2, "__index");
	lua_pop(L, 1);
	luaL_newlib(L, lualoader_lib);
	return 1;
}

