/*
 * Copyright (c) 2020 Matheus Rodrigues <matheussr61@gmail.com>
 * Copyright (C) 2017-2019  CUJO LLC
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

#ifndef LUNATIK_CONF_H
#define LUNATIK_CONF_H

#define LUNATIK_NAME_MAXSIZE	(64) /* Max length of Lua state name */

#define LUNATIK_SCRIPTNAME_MAXSIZE	(255) /* Max length of script name */

#define LUNATIK_DEFAULT_NS	(get_net_ns_by_pid(1))

#define LUNATIK_MIN_ALLOC_BYTES	(32 * 1024UL)

#define LUNATIK_HASH_BUCKETS	(32)

#endif /* LUNATIK_CONF_H */
