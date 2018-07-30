**Overview:**

Lunatik is a programming environment based on the Lua language for kernel scripting. By allowing kernel scripting, a user may create scripts in Lua to customize their kernel to suit their needs. Modern day kernels, such as Linux, work on a highly concurrent environment, and therefore must use robust synchronization APIs to ensure data consistency, with each API having their own use cases.

The Read-copy-update (RCU) is one of those APIs, made specifically for scenarios where data reading is much more common than writing. RCU allows concurrent readers to access protected data in a non-blocking way even during updates or removals. RCU, as with the rest of the Linux Kernel, is written in C.

This project idea is a binding of RCU for use in Lunatik, thus allowing synchronization of Lua data via RCU.

**Installation:**

Lunatik is presented as an in-tree kernel module, meaning we'll have to compile our own custom kernel with Lunatik alongside it. This instructions are based on the Debian distro and it is the environment I've used during the gsoc 2018 period.

First, you'll need to install the linux headers for your running kernel. These files are needed to develop kernel modules. To see which kernel you're running, type:
```bash
$ uname -r
```

After that, install the appropriate headers package. The package names may change from each distro.
```bash
$ sudo apt install linux-headers-$(uname -r)
```

Also install:
```bash
$ sudo apt install build-essential libncurses-dev linux-source
```

libncurses is a package that allows us to us a gui when configuring the kernel, and linux-source is a debian package that contains the kernel source. This package creates a linux-source-xx.tar.xz (where xx is your running kernel version) in /usr/src. Extract this file.
```bash
$ sudo tar -xf linux-source-xx.tar.xz
```

You should now have a directory /usr/src/linux-source-xx.

Now, we have to add the Lunatik files to the kernel source. Download the Lunatik source files (https://github.com/luainkernel/lunatik) and copy it to the linux source drivers directory, located in /usr/src/linux-source-xx/drivers.

Edit the Kconfig file located in the drivers directory and add "source lunatik/Kconfig" at the end of it.
In that same directory, also edit the makefile and add "obj-$(CONFIG_LUNATIK) += lunatik/" at the end.

Go back to /usr/src/linux-source-xx and run $ sudo make menuconfig
A gui will appear with various kernel configurations. Go to device drivers options and at the end of that list, find Lunatik and enable it with module support.
Also go to "Processor type and features", then "Preemption Model" and choose preemptible Kernel.
A preemptible kernel will allow for multiple lua scripts to execute and interact with the rcu hash table concurrently.

With Lunatik now enabled, we now have to compile the entire kernel. Fortunately, debian offers us a simple and quick approach.
```bash
$ make -j4 bindeb-pkg ARCH=x86_64
```
This command will create a .deb file that can be normally installed like any other package.
-j flag sets the number of cores used during the compilation, notice that this is a process that can take quite some time.

The result will be a file named linux-image-xx.deb. Install it as a normal package and reboot the system.
```bash
$ dpkg -i linux-image-xx.deb
```

Now Lunatik can be used as a normal module. Use 
```bash 
$ sudo modprobe -v lunatik
``` 
to install it and
```bash
$ sudo modprobe -r lunatik
```
to remove it

To see if it's currently running, type:
```bash
$ lsmod | grep lunatik
```

Since it's a kernel module, Lunatik will not print messages to a normal terminal. To see them, use either dmesg or journalctl to have access to the kernel and driver messages.
```bash
$ sudo dmesg
$ sudo journalctl -k
```

When Lunatik is loaded, a new driver is also loaded, called luadrv and located in /dev/luadrv. This driver expects lua scripts to execute them in kernel space. If your file is in user space, you can redirect it using
```bash
$ cat script.lua > /dev/luadrv
```
and the file will copied to kernel space and then executed.

**API:**

The functions of the API were implemented with the LUA-C interface in mind, meaning we can use functions written in C inside lua. These function were also exported to lua in the form of metamethods, meaning they are called automatically by using the rcu table.

The main functions of the api are:
```C
rcu_add_element(lua_State *L, const char *key, struct tvalue value, int idx);
rcu_delete_element(struct element *e, int idx);
rcu_replace_element(lua_State *L, struct element *e, struct tvalue new_value, int idx);
rcu_search_element(const char *key, int idx);
```
These functions are exported to lua via de __newindex and __index metamethods. This way, whenever a element is to be accessed, the __index function will call rcu_search_element, and whenever a element is to be added or modified, __newindex will call the appropriate function to add, delete or replace the element.

For example, to add an element to the rcu protected hash table from lua, just write
```lua
rcu["somekey"] = some_value
```
Since the keys are strings, we can also use the usual lua dot notation 'table.key' to acess an element.

To update:
```lua
rcu.somekey = another_value
```

And to delete:
```lua
rcu.somekey = nil
```

To access an element, you can simply use
```lua
print(rcu.somekey)
```

These will automatically call the C functions rcu_add_element, rcu_replace_element and rcu_delete_element of the API. Notice that, in the lua code, you don't need to take care of the locks and mutexes manually, as these are handled in the C side and that by utilizing RCU we can guarantee that readers will never be blocked and the data will always be accessible.

**Implementation:**

The RCU binding for this project is all contained in the rcu.c file, and some modifications were made to the luadev.c file to allow for concurrent execution. In the rcu/rcu.c file, we define a hash table using the kernel own macros. This results in an array where each element is the head of a linked list (a bucket). We can change the size of this array at compile time, adding more buckets and reducing collision if needed. Each of these buckets is a linked list protected by RCU independently, meaning that each bucket has their own lock, and elements from different buckets can be modified at the same time. RCU allows any number of readers and up to one writer in the same bucket.

Each element in the hash table contains a unique string key. For the values, each element can hold either an int, a bool or a string.

In the poc-driver/luadev.c file, we define an array of of lua_exec struct. This struct contains a pointer to a script, a lua state where the code will executed and a kthread to allow concurrent execution. The size of this array can also be changed, thus allowing for more states to run code concurrently.
