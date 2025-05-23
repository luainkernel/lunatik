/*
* SPDX-FileCopyrightText: (c) 2024 Mohammad Shehar Yaar Tausif <sheharyaar48@gmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#include <xtables.h>
#include <linux/netfilter.h>

#include "luaxtable.h"

static void dnsblock_mt_help(void)
{
}

static void dnsblock_mt_init(struct xt_entry_match *match)
{
}

static int dnsblock_mt_parse(int c, char **argv, int invert,
		unsigned int *flags, const void *entry, struct xt_entry_match **match)
{
	return true;
}

static void dnsblock_mt_check(unsigned int flags)
{
}

static void dnsblock_mt_print(const void *entry,
		const struct xt_entry_match *match, int numeric)
{
}

static void dnsblock_mt_save(const void *entry,
		const struct xt_entry_match *match)
{
}

static struct xtables_match dnsblock_mt_reg = {
	.version       = XTABLES_VERSION,
	.name          = "dnsblock",
	.revision      = 1,
	.family        = NFPROTO_UNSPEC,
	.size          = XT_ALIGN(sizeof(luaxtable_info_t)),
	.userspacesize = 0,
	.help          = dnsblock_mt_help,
	.init          = dnsblock_mt_init,
	.parse         = dnsblock_mt_parse,
	.final_check   = dnsblock_mt_check,
	.print         = dnsblock_mt_print,
	.save          = dnsblock_mt_save,
};

static void __attribute__((constructor)) _init(void)
{
	xtables_register_match(&dnsblock_mt_reg);
}

