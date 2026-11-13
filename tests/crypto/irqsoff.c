/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/*
* A HID transport, which irqsoff.sh builds and loads for a softirq runtime's raw_event to run with IRQs
* off: it adds one device and hands it one input report from hardirq context, as an HCD without HCD_BH,
* OHCI's, completes a URB, and no test host carries such a controller.
*/

#include <linux/hid.h>
#include <linux/irq_work.h>
#include <linux/module.h>

#define IRQSOFF_VENDOR	0xf055
#define IRQSOFF_PRODUCT	0x2379

static u8 irqsoff_rdesc[] = {
	0x06, 0x00, 0xff,	/* Usage Page (Vendor Defined 0xff00) */
	0x09, 0x01,		/* Usage (0x01) */
	0xa1, 0x01,		/* Collection (Application) */
	0x09, 0x02,		/* Usage (0x02) */
	0x15, 0x00,		/* Logical Minimum (0) */
	0x26, 0xff, 0x00,	/* Logical Maximum (255) */
	0x75, 0x08,		/* Report Size (8) */
	0x95, 0x02,		/* Report Count (2) */
	0x81, 0x02,		/* Input (Data, Variable, Absolute) */
	0xc0,			/* End Collection */
};

static u8 irqsoff_report[2];
static struct hid_device *irqsoff_hdev;

static int status;
module_param(status, int, 0444);
MODULE_PARM_DESC(status, "what hid_input_report returned for the report");

/* as usbhid's hid_irq_in hands a completed URB on */
static void irqsoff_deliver(struct irq_work *work)
{
	status = hid_input_report(irqsoff_hdev, HID_INPUT_REPORT, irqsoff_report, sizeof(irqsoff_report), 1);
}

static struct irq_work irqsoff_work = IRQ_WORK_INIT_HARD(irqsoff_deliver);

static int irqsoff_parse(struct hid_device *hdev)
{
	return hid_parse_report(hdev, irqsoff_rdesc, sizeof(irqsoff_rdesc));
}

/* nothing to start or open: the one report comes from the irq_work */
static int irqsoff_open(struct hid_device *hdev)
{
	return 0;
}

static void irqsoff_close(struct hid_device *hdev)
{
}

static int irqsoff_raw_request(struct hid_device *hdev, unsigned char reportnum, __u8 *buf, size_t len,
	unsigned char rtype, int reqtype)
{
	return -EIO;
}

static const struct hid_ll_driver irqsoff_driver = {
	.start = irqsoff_open,
	.stop = irqsoff_close,
	.open = irqsoff_open,
	.close = irqsoff_close,
	.parse = irqsoff_parse,
	.raw_request = irqsoff_raw_request,
};

static int __init irqsoff_init(void)
{
	int ret;

	irqsoff_hdev = hid_allocate_device();
	if (IS_ERR(irqsoff_hdev))
		return PTR_ERR(irqsoff_hdev);

	irqsoff_hdev->ll_driver = &irqsoff_driver;
	irqsoff_hdev->bus = BUS_VIRTUAL;
	irqsoff_hdev->vendor = IRQSOFF_VENDOR;
	irqsoff_hdev->product = IRQSOFF_PRODUCT;
	strscpy(irqsoff_hdev->name, "lunatik-irqsoff", sizeof(irqsoff_hdev->name));

	/* binds a driver that asks for no asynchronous probe before it returns */
	if ((ret = hid_add_device(irqsoff_hdev)) != 0) {
		hid_destroy_device(irqsoff_hdev);
		return ret;
	}

	irq_work_queue(&irqsoff_work);
	irq_work_sync(&irqsoff_work);
	return 0;
}

static void __exit irqsoff_exit(void)
{
	hid_destroy_device(irqsoff_hdev);
}

module_init(irqsoff_init);
module_exit(irqsoff_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_DESCRIPTION("A HID transport the crypto suite's irqsoff test reports from hardirq context through");

