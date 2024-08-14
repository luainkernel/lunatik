/*
* SPDX-FileCopyrightText: (c) 2024 Mohammad Shehar Yaar Tausif <sheharyaar48@gmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#include <xtables.h>
#include <linux/netfilter.h>

#include "luaxtable.h"

static void mt_help(void)
{
}

static void mt_init(struct xt_entry_match *match)
{
}

static int mt_parse(int c, char **argv, int invert,
    unsigned int *flags, const void *entry, struct xt_entry_match **match)
{
	return true;
}

static void mt_check(unsigned int flags)
{
}

static void mt_print(const void *entry,
    const struct xt_entry_match *match, int numeric)
{
}

static void mt_save(const void *entry,
    const struct xt_entry_match *match)
{
}

static struct xtables_match mt_reg = {
	.version       = XTABLES_VERSION,
	.name          = "sniblock",
	.revision      = 1,
	.family        = NFPROTO_UNSPEC,
	.size          = XT_ALIGN(sizeof(luaxtable_info_t)),
	.userspacesize = 0,
	.help          = mt_help,
	.init          = mt_init,
	.parse         = mt_parse,
	.final_check   = mt_check,
	.print         = mt_print,
	.save          = mt_save,
};

static void __attribute__((constructor)) _init(void)
{
	xtables_register_match(&mt_reg);
}

