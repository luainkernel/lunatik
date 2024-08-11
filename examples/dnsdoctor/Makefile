# SPDX-FileCopyrightText: (c) 2024 Mohammad Shehar Yaar Tausif <sheharyaar48@gmail.com>
# SPDX-License-Identifier: MIT OR GPL-2.0-only

all:
	LUAXTABLE_MODULE=dnsdoctor $(MAKE) -C ../../usr/lib/xtable

install:
	sudo LUAXTABLE_MODULE=dnsdoctor $(MAKE) -C ../../usr/lib/xtable install

uninstall:
	sudo rm -f ${XTABLES_SO_DIR}/libxt_${LUAXTABLE_MODULE}.so

clean:
	LUAXTABLE_MODULE=dnsdoctor $(MAKE) -C ../../usr/lib/xtable clean

