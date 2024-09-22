#!/usr/bin/env bash
# SPDX-FileCopyrightText: (c) 2024 jperon
# SPDX-License-Identifier: MIT OR GPL-2.0-only

KERNEL_RELEASE=$(uname -r)
# This ugly hack is needed because Ubuntu has a weird kernel package versionning.
KERNEL_VERSION=$( (grep -o '[0-9.]*$' /proc/version_signature 2>/dev/null) || (uname -r | grep -o '^[0-9.]*') )
KERNEL_VERSION_MAJOR=$(echo "${KERNEL_VERSION}" | grep -o '^[0-9]*')
CPU_CORES=$( grep -m1 'cpu cores' /proc/cpuinfo | grep -o '[0-9]*$')
LUNATIK_DIR="/opt/lunatik"

echo "Checking linux-headers-${KERNEL_RELEASE}, linux-tools-generic, lua5.4 and pahole are installed..."
dpkg --get-selections | grep "linux-headers-${KERNEL_RELEASE}\s" | grep install &&\
dpkg --get-selections | grep 'linux-tools-generic\s' | grep install &&\
dpkg --get-selections | grep 'lua5.4\s' | grep install &&\
dpkg --get-selections | grep 'pahole\s' | grep install || exit 1
cp /sys/kernel/btf/vmlinux "/usr/lib/modules/${KERNEL_RELEASE}/build/" &&\

echo "Compiling and installing resolve_btfids from kernel sources"
cd /usr/local/src &&\
wget -O- "https://cdn.kernel.org/pub/linux/kernel/v${KERNEL_VERSION_MAJOR}.x/linux-${KERNEL_VERSION}.tar.xz" | tar xJf - &&\
cd "linux-${KERNEL_VERSION}"/tools/bpf/resolve_btfids/ &&\
make -j"${CPU_CORES}" &&\
mkdir -p "/usr/src/linux-headers-${KERNEL_RELEASE}/tools/bpf/resolve_btfids/" &&\
cp resolve_btfids /usr/src/linux-headers-`uname -r`/tools/bpf/resolve_btfids/ &&\

echo "Compiling and installing Lunatik"
cd "${LUNATIK_DIR}" &&\
make clean &&\
make -j"${CPU_CORES}" && make install && rm -r /usr/local/src/"linux-${KERNEL_VERSION}"
