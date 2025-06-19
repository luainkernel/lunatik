#
# This is a hack to generate the .intrp section, which then
# ld turns into an PT_INTERP header.
#
# NOTE: The .interp section needs to be "a", or it doesnt work...
#

        .section ".interp","a"
        .ascii LIBDIR
	.ascii "/klibc-"
        .ascii SOHASH
        .ascii ".so"
        .byte 0

#
# Ensure that every executable includes some static data, as
# ELF loaders tend to assume this - see
# <https://bugs.debian.org/919921>, <https://bugs.debian.org/1016718>.
#

	.section ".data"
	.byte 0
