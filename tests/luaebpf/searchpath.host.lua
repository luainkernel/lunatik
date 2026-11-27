--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Fails unless the host's Lua finds the module arg[1] names (see types.sh and object.sh).

assert(package.searchpath(arg[1], package.path))

