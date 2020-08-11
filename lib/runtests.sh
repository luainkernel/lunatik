#!/bin/bash

set -e

for file in tests/*; do
    echo "Running $file"
    LD_LIBRARY_PATH=../deps/lua-memory/src LUA_CPATH='../deps/lua-memory/src/?.so;;' lua $file
    echo "$file executed with no errors!"
done
