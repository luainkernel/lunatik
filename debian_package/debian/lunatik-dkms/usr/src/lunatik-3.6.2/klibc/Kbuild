#
# Kbuild file for klibc
#
.PHONY: $(obj)/all
always := all

$(obj)/all:
	$(Q)$(MAKE) $(klibc)=scripts/basic
	$(Q)$(MAKE) $(klibc)=usr/klibc
	$(Q)$(MAKE) $(klibc)=usr/kinit
	$(Q)$(MAKE) $(klibc)=usr/dash
	$(Q)$(MAKE) $(klibc)=usr/utils
	$(Q)$(MAKE) $(klibc)=usr/gzip


# Directories to visit during clean and install
subdir- := scripts/basic klcc usr/klibc usr/dash usr/utils usr/gzip \
	   usr/kinit usr/klibc/tests
