#!/bin/bash
# Build the pieces of the RK322x NAND boot chain:
#   idblock.bin    DDR init + miniloader, for the BootROM
#   parameter.bin  RK partition table (sector 0 of the FTL device)
#   uboot.img      Rockchip U-Boot 2017.09 with hataketsu's two patches
#   trust.img      OP-TEE from rkbin
#
# Rockchip's make.sh wants the Linaro 6.3.1 toolchain, which Linaro no longer
# hosts, and U-Boot 2017.09 does not build with GCC 9+ (-march=armv5 is gone).
# Bootlin's GCC 7.3 is old enough.
set -euo pipefail

KIT=$(cd "$(dirname "$0")" && pwd)
WORK=${WORK:-/tmp/rkuboot}
OUT=${1:-$KIT/out}

UBOOT_REPO=https://github.com/rockchip-linux/u-boot.git
UBOOT_BRANCH=next-dev
RKBIN_REPO=https://github.com/rockchip-linux/rkbin.git
TOOLCHAIN_URL=https://toolchains.bootlin.com/downloads/releases/toolchains/armv7-eabihf/tarballs/armv7-eabihf--glibc--stable-2018.11-1.tar.bz2

rm -rf "$WORK"
mkdir -p "$WORK" "$OUT"
cd "$WORK"

git clone -q --depth 1 -b "$UBOOT_BRANCH" "$UBOOT_REPO" u-boot
git clone -q --depth 1 "$RKBIN_REPO" rkbin
curl -fsSL --retry 3 -o tc.tar.bz2 "$TOOLCHAIN_URL"
tar -xf tc.tar.bz2
rm tc.tar.bz2
TC=$(ls -d "$WORK"/armv7-eabihf--glibc--*/bin)
CC_PREFIX=$(ls "$TC"/*-gcc | grep -v -- '-gcc-' | head -1)
CC_PREFIX=${CC_PREFIX%gcc}
"${CC_PREFIX}gcc" --version | head -1

cd u-boot
echo "u-boot $(git rev-parse --short HEAD), rkbin $(git -C ../rkbin rev-parse --short HEAD)" \
	> "$OUT/versions.txt"
patch -p0 configs/rk322x_defconfig < "$KIT/uboot/rk322x_defconfig.patch"
patch -p0 include/configs/evb_rk3229.h < "$KIT/uboot/evb_rk3229.h.patch"
./make.sh rk322x CROSS_COMPILE="$CC_PREFIX"

ls -l ./*.img ./*.bin
cp uboot.img trust.img "$OUT/"
LOADER=$(ls rk322x_loader_*.bin | head -1)
cp "$LOADER" "$OUT/"

python3 "$KIT/tools/mk-idblock.py" "$LOADER" -o "$OUT/idblock.bin"
python3 "$KIT/tools/mk-idblock.py" --inspect "$OUT/idblock.bin"
python3 "$KIT/tools/mk-rkparam.py" -o "$OUT/parameter.bin"
python3 "$KIT/tools/mk-rkparam.py" --inspect "$OUT/parameter.bin"

# the magic the FTL's loader hook looks for at LBA 64
head -c 4 "$OUT/idblock.bin" | od -An -tx1 | grep -q '3b 8c dc fc'
# U-Boot must carry the extlinux-on-rknand boot command
strings "$OUT/uboot.img" | grep -q 'sysboot rknand 0:3'

cat "$OUT/versions.txt"
ls -l "$OUT"
