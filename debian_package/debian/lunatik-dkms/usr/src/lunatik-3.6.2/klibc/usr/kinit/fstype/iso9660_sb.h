#ifndef __ISO9660_SB_H
#define __ISO9660_SB_H

#define ISO_MAGIC_L	5
#define ISO_MAGIC	"CD001"
#define ISO_HS_MAGIC_L	5
#define ISO_HS_MAGIC	"CDROM"

/* ISO9660 Volume Descriptor */
struct iso_volume_descriptor {
	__u8 type;
	char id[ISO_MAGIC_L];
	__u8 version;
};

/* High Sierra Volume Descriptor */
struct iso_hs_volume_descriptor {
	char foo[8];
	__u8 type;
	char id[ISO_HS_MAGIC_L];
	__u8 version;
};

#endif
