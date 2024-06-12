/*
* Copyright (c) 2024 Mohammad Shehar Yaar Tausif <sheharyaar48@gmail.com>
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

#include <xtables.h>
#include <linux/netfilter.h>

#include "luaxtable.h"

static void ipaddr_mt_help(void)
{
}

static void ipaddr_mt_init(struct xt_entry_match *match)
{
}

static int ipaddr_mt_parse(int c, char **argv, int invert,
    unsigned int *flags, const void *entry, struct xt_entry_match **match)
{
	return true;
}

static void ipaddr_mt_check(unsigned int flags)
{
}

static void ipaddr_mt_print(const void *entry,
    const struct xt_entry_match *match, int numeric)
{
}

static void ipaddr_mt_save(const void *entry,
    const struct xt_entry_match *match)
{
}

static struct xtables_match ipaddr_mt_reg = {
	.version       = XTABLES_VERSION,
	.name          = "luaxtabletest",
	.revision      = 1,
	.family        = NFPROTO_UNSPEC,
	.size          = XT_ALIGN(sizeof(luaxtable_info_t)),
	.userspacesize = 0,
	/* called when user execs "iptables -m ipaddr -h" */
	.help          = ipaddr_mt_help,
	/* populates the xt_ipaddr_mtinfo before parse (eg. to set defaults). */
	.init          = ipaddr_mt_init,
	/* called when user enters new rule; it validates the args (--ipsrc). */
	.parse         = ipaddr_mt_parse,
	/* last chance for sanity checks after parse. */
	.final_check   = ipaddr_mt_check,
	/* called when user execs "iptables -L" */
	.print         = ipaddr_mt_print,
	/* called when user execs "iptables-save" */
	.save          = ipaddr_mt_save,
};

static void __attribute__((constructor)) _init(void)
{
	xtables_register_match(&ipaddr_mt_reg);
}
