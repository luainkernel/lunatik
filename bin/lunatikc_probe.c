/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/*
* luaebpf.probe: asks the running kernel for what no symbol names.
*
* The compiler runs on the machine that loads what it emits, so it can ask rather than read a
* release. A helper or a kfunc is a FUNC in the kernel's own BTF and the translator reads it
* there; may_goto is an instruction with no name anywhere, so the only question that answers it
* is a load of the instruction itself.
*/

#include <errno.h>
#include <string.h>
#include <unistd.h>
#include <sys/syscall.h>
#include <linux/bpf.h>

#include <lua.h>
#include <lauxlib.h>

/* BPF_JCOND and BPF_MAY_GOTO, which a host header below v6.9 does not carry (uapi/linux/bpf.h) */
#define LUAEBPF_JCOND		0xe0
#define LUAEBPF_MAY_GOTO	0

#define LUAEBPF_NINSNS(a)	((__u32)(sizeof(a) / sizeof((a)[0])))

/* the program type is the one whose own rules are checked after the opcode, so what a rejection
 * says is that the kernel does not know the instruction */
static int luaebpf_probe_load(struct bpf_insn *insns, __u32 n)
{
	union bpf_attr attr;

	memset(&attr, 0, sizeof(attr));
	attr.prog_type = BPF_PROG_TYPE_SOCKET_FILTER;
	attr.insn_cnt = n;
	attr.insns = (__u64)(unsigned long)insns;
	attr.license = (__u64)(unsigned long)"GPL";
	return (int)syscall(__NR_bpf, BPF_PROG_LOAD, &attr, sizeof(attr));
}

/***
* Whether the running kernel takes a `may_goto`, which is what buys a loop the verifier cannot
* count. Answers nothing where the load needed a privilege this process does not have, since an
* `EPERM` says nothing about the instruction.
* @function maygoto
* @treturn boolean|nil
*/
static int luaebpf_probe_maygoto(lua_State *L)
{
	/* the shortest program it fits in: a zero offset is refused, and the exit needs its own verdict */
	struct bpf_insn insns[] = {
		{.code = BPF_ALU64 | BPF_MOV | BPF_K, .dst_reg = BPF_REG_0},
		{.code = BPF_JMP | LUAEBPF_JCOND, .src_reg = LUAEBPF_MAY_GOTO, .off = 1},
		{.code = BPF_JMP | BPF_EXIT},
		{.code = BPF_JMP | BPF_EXIT},
	};
	int fd = luaebpf_probe_load(insns, LUAEBPF_NINSNS(insns));

	if (fd < 0 && (errno == EPERM || errno == EACCES))
		return 0;
	if (fd >= 0)
		close(fd);
	lua_pushboolean(L, fd >= 0);
	return 1;
}

static const luaL_Reg luaebpf_probe_lib[] = {
	{"maygoto", luaebpf_probe_maygoto},
	{NULL, NULL}
};

int luaopen_luaebpf_probe(lua_State *L)
{
	luaL_newlib(L, luaebpf_probe_lib);
	return 1;
}

