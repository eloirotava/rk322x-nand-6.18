# SPDX-License-Identifier: GPL-2.0
#
# Rockchip rknand: the vendor MLC NAND block driver, over the closed
# Rockchip FTL, for a current kernel (armv7, RK322x).
#
#   make KDIR=<kernel build dir> [CROSS_COMPILE=arm-linux-gnueabihf-]

obj-m := rknand.o
rknand-y := rk_nand_base.o rk_nand_blk.o rknand_shims.o

# The FTL itself: Rockchip's precompiled objects, kept as assembler source.
# rk_zftl exports the Ftl* API and calls into the FTL v5 core.  Do not edit.
ifdef CONFIG_THUMB2_KERNEL
rknand-y += rk_ftl_arm_v7_thumb.o
else
rknand-y += rk_zftl_arm32.o rk_ftlv5_arm32.o
endif

KDIR ?= /lib/modules/$(shell uname -r)/build
ARCH ?= arm
CROSS_COMPILE ?=

all:
	$(MAKE) -C $(KDIR) M=$(CURDIR) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) modules

clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) clean
