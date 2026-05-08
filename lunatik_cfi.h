/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/*
* Indirect calls under hardware Control-Flow Integrity (x86 IBT).
*/

#ifndef lunatik_cfi_h
#define lunatik_cfi_h

#ifdef CONFIG_X86_KERNEL_IBT
#include <asm/ibt.h>
#include <asm/msr.h>
#include <asm/cpufeature.h>
#include <linux/irqflags.h>
#include <linux/version.h>

#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 15, 0)
#define is_endbr	__is_endbr
#endif

static inline void *lunatik_cfi_entry(void *addr)
{
	u32 *prefix = (u32 *)((unsigned long)addr - ENDBR_INSN_SIZE);
	return is_endbr(*prefix) ? (void *)prefix : addr;
}

/* MSR_IA32_S_CET is per-CPU; caller must pin the task. */
static inline u64 lunatik_cfi_disable(void)
{
	u64 msr;

	if (!cpu_feature_enabled(X86_FEATURE_IBT))
		return 0;
	rdmsrl(MSR_IA32_S_CET, msr);
	wrmsrl(MSR_IA32_S_CET, msr & ~CET_ENDBR_EN);
	return msr;
}

static inline void lunatik_cfi_restore(u64 saved)
{
	u64 msr;

	if (!cpu_feature_enabled(X86_FEATURE_IBT))
		return;
	rdmsrl(MSR_IA32_S_CET, msr);
	wrmsrl(MSR_IA32_S_CET, (msr & ~CET_ENDBR_EN) | (saved & CET_ENDBR_EN));
}

#define lunatik_cfi_call(expr) ({					\
	unsigned long __flags;						\
	u64 __cfi;							\
	typeof(expr) __ret;						\
									\
	local_irq_save(__flags);					\
	__cfi = lunatik_cfi_disable();					\
	__ret = (expr);							\
	lunatik_cfi_restore(__cfi);					\
	local_irq_restore(__flags);					\
	__ret;								\
})
#else
#define lunatik_cfi_entry(addr)	(addr)
#define lunatik_cfi_call(expr)		(expr)
#endif

#endif

