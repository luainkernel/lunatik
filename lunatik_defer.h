/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#ifndef lunatik_defer_h
#define lunatik_defer_h

extern struct workqueue_struct *lunatik_wq;
void lunatik_defer(lunatik_defer_t *defer, lunatik_finalize_t finalize);
int lunatik_setupdefer(void);
void lunatik_cleanupdefer(void);

#endif

