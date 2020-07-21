#
# Copyright (C) 2017-2019  CUJO LLC
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
#

CC = gcc
CFLAGS = -fPIC -Wall -Wextra -O2 -g -I../src
LDFLAGS = -shared
RM = rm -f

LIBS = libnflua.so
OBJS = $(patsubst %.c,%.o,$(wildcard *.c))
DEPS = $(OBJS:.o=.d)

.PHONY: all
all: $(LIBS)

%.so:
	$(CC) -o $@ $^ $(LDFLAGS)

%.o: %.c
	$(CC) $(CFLAGS) -MMD -c -o $@ $<

-include $(DEPS)

.PHONY: clean
clean:
	$(RM) $(LIBS) $(OBJS) $(DEPS)

$(LIBS): $(OBJS)
