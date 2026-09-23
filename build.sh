#!/bin/bash
# Turn the Armbian RK322x Trixie 6.18 minimal image into one whose SD boot
# brings up the vendor NAND FTL (rknand.ko + nand-vendor overlay).
set -euo pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)
WORKDIR=${WORKDIR:-/tmp/rkbuild}
IMAGE_URL=${IMAGE_URL:-https://github.com/armbian/community/releases/download/26.11.0-trunk.52/Armbian_community_26.11.0-trunk.52_Rk322x-box_trixie_current_6.18.52_minimal.img.xz}
MNT=${MNT:-/mnt/rkroot}
OUT="$ROOT/out"
LOOP=""

cleanup() {
	set +e
	if mountpoint -q "$MNT"; then
		umount "$MNT/dev" "$MNT/proc" "$MNT/sys" "$MNT/run" 2>/dev/null
		umount "$MNT"
	fi
	if [ -n "$LOOP" ]; then
		losetup -d "$LOOP" 2>/dev/null
	fi
}
trap cleanup EXIT

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
	gcc-arm-linux-gnueabihf bc bison flex libssl-dev libelf-dev dwarves \
	device-tree-compiler qemu-user-static binfmt-support kmod \
	initramfs-tools ca-certificates curl xz-utils python3 u-boot-tools

rm -rf "$WORKDIR"
mkdir -p "$WORKDIR" "$OUT" "$MNT"
cd "$WORKDIR"

echo "== download base image =="
curl -fL --retry 3 -o base.img.xz "$IMAGE_URL"
xz -T0 -d base.img.xz
rm -f base.img.xz

echo "== mount =="
LOOP=$(losetup -fP --show "$WORKDIR/base.img")
udevadm settle || true
sleep 1
found=
for p in "${LOOP}"p*; do
	[ -b "$p" ] || continue
	if mount -o rw "$p" "$MNT"; then
		if [ -f "$MNT/etc/armbian-release" ]; then
			found=$p
			break
		fi
		umount "$MNT"
	fi
done
[ -n "$found" ] || { echo "no armbian rootfs"; lsblk; exit 1; }
echo "rootfs $found"
cat "$MNT/etc/armbian-release"

mapfile -t MODS < <(find "$MNT/lib/modules" -mindepth 1 -maxdepth 1 -type d -printf '%f\n')
[ "${#MODS[@]}" -eq 1 ] || { echo "expected one modules dir, got: ${MODS[*]}"; exit 1; }
KVER=${MODS[0]}
echo "KVER=$KVER"
BASEVER=${KVER%%-*}
SUFFIX=${KVER#"$BASEVER"}
case "$BASEVER" in
	6.18.*) ;;
	*) echo "refusing non-6.18 kernel $KVER"; exit 1 ;;
esac

CFG="$MNT/boot/config-$KVER"
if [ ! -f "$CFG" ]; then
	CFG="$MNT/boot/config"
fi
[ -f "$CFG" ] || { echo "no kernel config in /boot"; find "$MNT/boot" -maxdepth 1 -type f -printf '%f\n'; exit 1; }
cp "$CFG" "$WORKDIR/kernel.config"

DTB=$(find "$MNT/boot" -name rk322x-box.dtb -printf '%s %p\n' | sort -n | awk '{print $2}' | tail -1)
[ -n "$DTB" ] || { echo "no rk322x-box.dtb"; find "$MNT/boot" -name '*.dtb' | head; exit 1; }
echo "DTB=$DTB"
cp -L "$DTB" "$WORKDIR/rk322x-box.dtb"

echo "== kernel $BASEVER localversion '$SUFFIX' =="
curl -fL --retry 3 -o linux.tar.xz \
	"https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-${BASEVER}.tar.xz"
tar -xf linux.tar.xz
rm -f linux.tar.xz
KSRC="$WORKDIR/linux-$BASEVER"
cp "$WORKDIR/kernel.config" "$KSRC/.config"
cd "$KSRC"
# scripts/config --set-str treats a leading dash as awkward; write the line.
sed -i '/^CONFIG_LOCALVERSION=/d; /^# CONFIG_LOCALVERSION is not set/d' .config
printf 'CONFIG_LOCALVERSION="%s"\n' "$SUFFIX" >> .config
./scripts/config --disable LOCALVERSION_AUTO
./scripts/config --disable DEBUG_INFO_BTF
./scripts/config --disable DEBUG_INFO_BTF_MODULES
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- olddefconfig
sed -i '/^CONFIG_LOCALVERSION=/d; /^# CONFIG_LOCALVERSION is not set/d' .config
printf 'CONFIG_LOCALVERSION="%s"\n' "$SUFFIX" >> .config
./scripts/config --disable LOCALVERSION_AUTO
./scripts/config --disable DEBUG_INFO_BTF
./scripts/config --disable DEBUG_INFO_BTF_MODULES
grep -E '^CONFIG_LOCALVERSION=|^CONFIG_MODVERSIONS=|^CONFIG_MODULE_SIG' .config || true
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- -j"$(nproc)" modules_prepare
REL=$(make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- -s kernelrelease)
echo "kernelrelease=$REL"
[ "$REL" = "$KVER" ] || { echo "vermagic base mismatch: built $REL image $KVER"; exit 1; }

if grep -q '^CONFIG_MODVERSIONS=y' .config; then
	SYM=$(find "$MNT/usr" "$MNT/lib/modules/$KVER" -name Module.symvers 2>/dev/null | head -1 || true)
	if [ -z "$SYM" ]; then
		echo "CONFIG_MODVERSIONS=y but the image has no Module.symvers"
		exit 1
	fi
	cp "$SYM" "$KSRC/Module.symvers"
fi

echo "== rknand.ko =="
make -C "$KSRC" M="$ROOT/rknand-port" ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- modules
modinfo "$ROOT/rknand-port/rknand.ko"
VM=$(modinfo -F vermagic "$ROOT/rknand-port/rknand.ko" | awk '{print $1}')
[ "$VM" = "$KVER" ] || { echo "ko vermagic $VM != $KVER"; exit 1; }

echo "== overlay =="
python3 "$ROOT/gen-overlay.py" "$WORKDIR/rk322x-box.dtb" "$WORKDIR/nand-vendor.dts"
dtc -@ -I dts -O dtb -o "$WORKDIR/nand-vendor.dtbo" "$WORKDIR/nand-vendor.dts"
fdtoverlay -i "$WORKDIR/rk322x-box.dtb" -o "$WORKDIR/rk322x-box-nand.dtb" "$WORKDIR/nand-vendor.dtbo"

install -D -m 0644 "$ROOT/rknand-port/rknand.ko" "$MNT/lib/modules/$KVER/extra/rknand.ko"
install -D -m 0644 "$WORKDIR/nand-vendor.dtbo" "$MNT/boot/overlay-user/nand-vendor.dtbo"
install -m 0644 "$WORKDIR/rk322x-box-nand.dtb" "$(dirname "$DTB")/rk322x-box-nand.dtb"

ENVF="$MNT/boot/armbianEnv.txt"
touch "$ENVF"
if grep -q '^user_overlays=' "$ENVF"; then
	cur=$(sed -n 's/^user_overlays=//p' "$ENVF" | head -1)
	case " $cur " in
		*" nand-vendor "*) ;;
		*)
			if [ -z "$cur" ]; then
				sed -i 's/^user_overlays=.*/user_overlays=nand-vendor/' "$ENVF"
			else
				sed -i "s/^user_overlays=.*/user_overlays=${cur} nand-vendor/" "$ENVF"
			fi
			;;
	esac
else
	printf '\nuser_overlays=nand-vendor\n' >> "$ENVF"
fi
grep user_overlays "$ENVF"

mkdir -p "$MNT/etc/modules-load.d" "$MNT/etc/initramfs-tools"
printf 'rknand\n' > "$MNT/etc/modules-load.d/rknand.conf"
touch "$MNT/etc/modules" "$MNT/etc/initramfs-tools/modules"
grep -qx rknand "$MNT/etc/modules" || echo rknand >> "$MNT/etc/modules"
grep -qx rknand "$MNT/etc/initramfs-tools/modules" || echo rknand >> "$MNT/etc/initramfs-tools/modules"

echo "== initrd =="
mount --bind /proc "$MNT/proc"
mount --bind /sys "$MNT/sys"
mount --bind /dev "$MNT/dev"
mkdir -p "$MNT/run"
mount --bind /run "$MNT/run"
cp /usr/bin/qemu-arm-static "$MNT/usr/bin/qemu-arm-static"
chroot "$MNT" /usr/bin/qemu-arm-static /bin/bash -lc \
	"/usr/sbin/depmod -a '$KVER' && /usr/sbin/update-initramfs -u -k '$KVER'"
INITRD="$MNT/boot/initrd.img-$KVER"
UINIT="$MNT/boot/uInitrd-$KVER"
[ -f "$INITRD" ] || { echo "missing $INITRD"; ls -l "$MNT/boot"; exit 1; }
if [ ! -f "$UINIT" ] || [ "$INITRD" -nt "$UINIT" ]; then
	mkimage -A arm -O linux -T ramdisk -C gzip -n uInitrd -d "$INITRD" "$UINIT"
fi
ln -sfn "uInitrd-$KVER" "$MNT/boot/uInitrd"
ls -l "$MNT/boot/uInitrd" "$UINIT" "$INITRD"
lsinitramfs "$INITRD" | grep -E 'rknand\.ko'
umount "$MNT/run" "$MNT/dev" "$MNT/proc" "$MNT/sys"
sync
umount "$MNT"
losetup -d "$LOOP"
LOOP=""

echo "== pack =="
rm -rf "$KSRC"
NAME="Armbian_community_26.11.0-trunk.52_Rk322x-box_trixie_current_${KVER}_minimal-rknand.img.xz"
xz -T0 -6 -c "$WORKDIR/base.img" > "$OUT/$NAME"
sha256sum "$OUT/$NAME" | tee "$OUT/SHA256SUMS"
TAG="v${KVER}-rknand"
printf '%s\n' "$TAG" > "$OUT/tag.txt"
cat > "$OUT/notes.txt" <<EOF
Armbian Trixie minimal, kernel ${KVER}, com o rknand do hataketsu (rk322x-s3plus-mainline).

- rknand.ko no vermagic ${KVER}, em /lib/modules/${KVER}/extra e no initrd
- overlay nand-vendor: compatible rockchip,rk-nandc, clocks clk_nandc/hclk_nandc, pinctrl lido do DTB desta imagem, mmc@30020000 desligado
- user_overlays=nand-vendor e o modulo sobe sozinho

Imagem de cartao SD. Nao grava a NAND e nao mexe no Debian que ja esta la.

Com o miniloader de NAND no idblock, o BootROM ignora o SD. Para subir por este cartao, curto os pinos 29 e 30 na hora de ligar.
EOF
echo "OUT $OUT/$NAME"
ls -lh "$OUT"
