#!/bin/bash
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only

set -eux

IF=${1:?usage: cleanup.sh <iface>}

lunatik stop examples/sniclassify/sni
tc qdisc del dev "$IF" root 2>/dev/null || true

