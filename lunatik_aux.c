/*
* SPDX-FileCopyrightText: (c) 2023-2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#include <linux/slab.h>
#include <linux/fs.h>
#include <linux/version.h>
#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 7, 0)
#include <linux/errname.h>
#endif

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

	if (unlikely(lunatik_cannotsleep(L, lunatik_isready(lunatik_toruntime(L))))) {
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

void lunatik_pusherrname(lua_State *L, int err)
{
    err = abs(err);
#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 7, 0)
    const char *name = errname(err);
    lua_pushstring(L, name ? name : "unknown");
#else
    char buf[LUAL_BUFFERSIZE];
    snprintf(buf, sizeof(buf), "%pE", ERR_PTR(-err));
    lua_pushstring(L, buf);
#endif
}
EXPORT_SYMBOL(lunatik_pusherrname);

#ifdef MODULE /* see https://lwn.net/Articles/813350/ */
#include <linux/kprobes.h>
#include <linux/irqflags.h>
#ifdef CONFIG_X86_KERNEL_IBT
#include <asm/ibt.h>
#include <asm/msr.h>
#include <asm/cpufeature.h>
/*
 * Detect ENDBR64 (f3 0f 1e fa) or ENDBR poison (0f 1f 40 d6).
 * __is_endbr() is only a static inline from Linux 7.0; use raw opcodes so
 * that we remain compatible with older kernels (e.g. 6.11).
 */
static inline bool lunatik_is_endbr(u32 val)
{
	/* ENDBR64 little-endian */
	if (val == 0xfa1e0ff3U)
		return true;
	/* ENDBR poison: nopl -42(%rax), used to seal indirect-call targets */
	if (val == 0xd6401f0fU)
		return true;
	return false;
}

/*
 * On IBT kernels kprobes places kp.addr past the ENDBR/ENDBR-poison prefix
 * (+4 bytes); step back only when confirmed, so that functions without any
 * ENDBR prefix are handled correctly too.
 */
static inline void *lunatik_kprobe_addr(void *addr)
{
	u32 *start = (u32 *)((unsigned long)addr - ENDBR_INSN_SIZE);

	return lunatik_is_endbr(*start) ? (void *)start : addr;
}

/*
 * kallsyms_lookup_name has been sealed in kernel 7.0: its ENDBR64 was replaced
 * with ENDBR poison, making it an invalid indirect-call target under hardware
 * IBT.  Temporarily disable ENDBR enforcement (CET_ENDBR_EN in MSR_IA32_S_CET)
 * around the indirect call.  ibt_save()/ibt_restore() are not exported to
 * modules, so we replicate their logic directly.
 */
static inline u64 lunatik_ibt_save(void)
{
	u64 msr = 0;

	if (cpu_feature_enabled(X86_FEATURE_IBT)) {
		rdmsrl(MSR_IA32_S_CET, msr);
		wrmsrl(MSR_IA32_S_CET, msr & ~CET_ENDBR_EN);
	}
	return msr;
}

static inline void lunatik_ibt_restore(u64 save)
{
	if (cpu_feature_enabled(X86_FEATURE_IBT)) {
		u64 msr;

		rdmsrl(MSR_IA32_S_CET, msr);
		/* Only restore CET_ENDBR_EN; avoid clobbering other CET state */
		wrmsrl(MSR_IA32_S_CET, (msr & ~CET_ENDBR_EN) | (save & CET_ENDBR_EN));
	}
}
#else /* !CONFIG_X86_KERNEL_IBT */
static inline void *lunatik_kprobe_addr(void *addr) { return addr; }
static inline u64 lunatik_ibt_save(void) { return 0; }
static inline void lunatik_ibt_restore(u64 save) { (void)save; }
#endif /* CONFIG_X86_KERNEL_IBT */

#ifdef CONFIG_KPROBES
static unsigned long (*__lunatik_lookup)(const char *) = NULL;
#endif /* CONFIG_KPROBES */

void *lunatik_lookup(const char *symbol)
{
#ifdef CONFIG_KPROBES
	unsigned long result;
	unsigned long flags;
	u64 ibt_state;

	if (__lunatik_lookup == NULL) {
		struct kprobe kp = {.symbol_name = "kallsyms_lookup_name"};

		if (register_kprobe(&kp) != 0)
			return NULL;

		__lunatik_lookup = (unsigned long (*)(const char *))lunatik_kprobe_addr(kp.addr);
		unregister_kprobe(&kp);

		BUG_ON(__lunatik_lookup == NULL);
	}

	/*
	 * Disable IRQs to pin execution to this CPU while MSR_IA32_S_CET is
	 * modified (per-CPU MSR); also prevents interrupt handlers from running
	 * with IBT temporarily disabled.
	 */
	local_irq_save(flags);
	ibt_state = lunatik_ibt_save();
	result = __lunatik_lookup(symbol);
	lunatik_ibt_restore(ibt_state);
	local_irq_restore(flags);

	return (void *)result;
#else /* CONFIG_KPROBES */
	return NULL;
#endif /* CONFIG_KPROBES */
}
EXPORT_SYMBOL(lunatik_lookup);
#endif /* MODULE */

#if BITS_PER_LONG == 32
/* require by lib/lualinux.c */
EXPORT_SYMBOL(__moddi3);
#endif /* BITS_PER_LONG == 32 */

