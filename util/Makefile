obj-y += modti3.o

# In 3.12 and later the kernel provides div64_u64_rem, so we don't need to
# provide our own.
ifeq ($(shell { [ $(VERSION) -lt 3 ] || { [ $(VERSION) -eq 2 ] && [ $(PATCHLEVEL) -lt 12 ] ;} ;} && echo y),y)
obj-y += div64.o
endif
