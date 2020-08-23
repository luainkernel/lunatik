# User Space API documentation

## Introduction

This document provides the documentation of the user space API of Lunatik. This API is divided in two main features, being the control API and the data API, the first one is responsible to send messages to Lunatik kernel module to perform some operations, whereas the data API is responsible to exchange data between the kernel module and this user space API.

## Constants

#### `lunatik.datamaxsize`

Integer that represents the maximum amount of data that a state can receive or send each time.

#### `lunatik.defaultmaxallocbytes`

The default amount of memory that a state will be able to use if no value is passed on creation.

#### `lunatik.maxstates`

The maximum number of states that the lunatik module is able to store.

#### `lunatik.scriptnamemaxsize`

The maximum length of a script name, this name is used on debug porpuses, for example, show a name for the script on the callback stack trace.

#### `lunatik.statenamemaxsize`

The maximum length of a state name.

## Control API

Responsable to send messages to Lunatik kernel module perform some operations, these are:
 * States creations
 * States deletion
 * States listing
 * Code execution

To use this API, first you must to include the lunatik module on your lua code, you can do this as follow:

```lua
local lunatik = require'lunatik'
```

After that, you have to create a lunatik session. This session represents a connection between kernel and user space API. To do it, simple store the return of the function `lunatik.session()` for example:

```lua
local lunatik = require'lunatik'
local session = lunatik.session()
```

Now you can use the variable `session` to do all operations related to control API. These operations will be showed next.

#### `session:newstate(name [, maxalloc])`

Tells the lunatik kernel module to create a state with the name `name`. If some value is passed to `maxalloc` that you be the maximum amount of memory that the state `name` can use during it execution, if no value is passed, a state with a default `maxalloc` will be created. If the state is succesfully created, the function returns a userdata, such userdata is used to perform all needed operations on that state. You can imagine this userdata as your user space representation of the state created on the kernel side. If the state creation fails, this function returns a `nil` value alongside with a error message.

#### `session:list()`

Returns a table with all states present on kernel. Each entry of that table is another table containing the following informations about the state: `name`, `curralloc` and `maxalloc`. `name` represents the state name, `curralloc` the amount of memory that the state `name` is using in that given moment (when the function `session:list()` was called) and `maxalloc` has the same meaning showed at [`session:new`](#sessionnewname--maxalloc).

#### `session:close()`

Closes the connection with the kernel, after that, all references for the states will be lost, so it's important to check if you don't have any states in use before close the connection with the kernel to avoid memory leaks.

#### `session:getstate(name)`

Gets a user representation of the state with the name `name` which was created on kernel. Returns a userdata as described on [`session:new`](#sessionnewname--maxalloc) if such state is found and `nil` otherwise.

#### `session:getfd()`

Returns the session file descriptor of the control socket.

### State related operations

As mentioned at [`session:new`](#sessionnewname--maxalloc) function, when you call that function, if the state is succesfully created, it  will be returned a userdata. That userdata is used to perform all operations related to that state, for example:

```lua
local mystate = session:newstate'somename'
```

This code will create a state named `somename` on kernel and store the userdata to perform all operations related to the state `somename` on the variable `mystate`.  From now on, it will be used `mystate` to explain all operations that can be done at that state.

#### `mystate:dostring(code [, codename])`

Runs on the kernel, the code given by `code`, you can give a name for that code, this can be used for debug purposes, if something get wrong on the execution of the code, then the name present on `codename` will be showed at the stack trace. If no value is passed, the default value `'lua in kernel'` will be showed for all states that loaded code without a `codename`.

#### `mystate:close()`

Closes on the kernel the state that `mystate` represents.

#### `mystate:getname()`

Returns the name of state `mystate` as it is in the kernel.

#### `mystate:getmaxalloc()`

Return the maximum amount of memory that `mystate` can use in the kernel.

#### `mystate:getcurralloc()`

Return the current memory usage in the kernel of the state represent by `mystate`.

## Data API

To transmit data from kernel to user space (and vice versa), we use lua memory (see [lua memory](https://github.com/luainkernel/lua-memory)).

#### `mystate:send(memory)`

Sends a [memory](https://github.com/luainkernel/lua-memory/blob/master/doc/manual.md#writable-byte-sequences) `memory` to the kernel state represented by `mystate`.

In order to receive this memory on the kernel side you must to define a global function called `receive_callback` with one parameter which represents the memory which was sent from the user space. For example:

```lua
function receive_callback(mem)
	-- Here I can do whatever I want with mem
end
```

This callback will be called every time that a memory is received by the kernel. It's important to say that the module `memory` from lua memory is loaded by default in this version of Lunatik, thus you can do all supported operations with memory that Lua Memory offers.

#### `mystate:receive()`

Receives from the state represented by `mystate` the data sent from kernel and return a [memory](https://github.com/luainkernel/lua-memory/blob/master/doc/manual.md#writable-byte-sequences) to manipulate the data sent by kernel. If no data is available to be received, this function blocks until receive some data.
