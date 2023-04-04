#!/bin/bash
#
# Copyright (c) 2023 ring-0 Ltda.
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
# CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
# TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#

LUNATIK_LIBS=(device linux)
LUNATIK_PATH=/lib/modules/lua

load() {
	insmod $1.ko
}

start() {
	load lunatik
	for lib in ${LUNATIK_LIBS[@]}
	do
		load lib/lua${lib}
	done
	load lunatik_run
}

isloaded() {
	grep -wq $1 /proc/modules
}

unload() {
	if isloaded $1; then
		rmmod $1
	fi
}

stop() {
	unload lunatik_run
	for lib in ${LUNATIK_LIBS[@]}
	do
		unload lua${lib}
	done
	unload lunatik
}

modstat() {
	if isloaded $1; then
		echo "$1 is loaded"
	fi
}

status() {
	modstat lunatik
	for lib in ${LUNATIK_LIBS[@]}
	do
		modstat lua${lib}
	done
	modstat lunatik_run
}

run() {
	if isloaded lunatik_run; then
		sbin/lunatik
	else
		echo "lunatik_run is not loaded"
	fi
}

case "$1" in
	start)
		start
		;;
	stop)
		stop
		;;
	restart)
		stop
		start
		;;
	status)
		status
		;;
	install)
		mkdir -p ${LUNATIK_PATH}
		cp lunatik.lua ${LUNATIK_PATH}
		chown -R root.root ${LUNATIK_PATH}
		chmod -R 644 ${LUNATIK_PATH}
		;;
	run)
		run
		;;
	*)
		echo "usage: $0 {start|stop|restart|status|install|run}"
esac
exit 0

