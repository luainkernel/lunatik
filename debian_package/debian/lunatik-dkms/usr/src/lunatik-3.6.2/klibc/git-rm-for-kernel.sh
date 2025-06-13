#!/bin/sh
if [ -z "$RM" ]; then
  export RM='git rm -rf'
fi

nuke () {
    find "$@" -print | sort -r | xargs -rt $RM
}

nuke README Kbuild Makefile defconfig klibc.spec.in *.sh
nuke contrib klcc

# These files are either not needed or provided from the
# kernel tree
nuke scripts/Kbuild.include scripts/Kbuild.install
nuke scripts/Makefile.*
nuke scripts/basic
