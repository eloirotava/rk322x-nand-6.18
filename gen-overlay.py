#!/usr/bin/env python3
"""Build nand-vendor.dts from the phandles in an image's rk322x-box.dtb."""
import re
import subprocess
import sys

PIN_ORDER = ("ale", "bus8", "cle", "cs0", "dqs", "rdn", "rdy", "wrn", "wp")


def decompile(dtb):
    proc = subprocess.run(
        ["dtc", "-I", "dtb", "-O", "dts", dtb],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    return proc.stdout


def parse(dts):
    stack = [""]
    phandles = {}
    node_re = re.compile(
        r"^\s*(?:[A-Za-z_][A-Za-z0-9_]*:\s*)?([A-Za-z0-9,._+@-]+)\s*\{\s*$"
    )
    ph_re = re.compile(
        r"(?:linux,)?phandle\s*=\s*<\s*(0x[0-9a-fA-F]+|\d+)\s*>\s*;"
    )
    for line in dts.splitlines():
        m = node_re.match(line)
        if m:
            stack.append(stack[-1] + "/" + m.group(1))
            continue
        if line.strip() == "};":
            if len(stack) > 1:
                stack.pop()
            continue
        m = ph_re.search(line)
        if m and len(stack) > 1:
            raw = m.group(1)
            phandles[stack[-1]] = int(raw, 16) if raw.startswith(("0x", "0X")) else int(raw)
    return phandles


def shortest(paths):
    return min(paths, key=len)


def find_unit(phandles, unit):
    hits = [p for p in phandles if p.endswith("@" + unit)]
    if not hits:
        raise SystemExit("no node @%s in the dtb" % unit)
    return shortest(hits)


def pin_phandle(phandles, pin):
    names = ("flash-" + pin, "flash_" + pin, pin)
    hits = []
    for path in phandles:
        base = path.rsplit("/", 1)[-1]
        parent = path.rsplit("/", 1)[0].rsplit("/", 1)[-1]
        if base in ("flash-" + pin, "flash_" + pin):
            hits.append(path)
        elif base == pin and parent in ("flash", "flash0"):
            hits.append(path)
    if not hits:
        known = [p for p in phandles if "flash" in p]
        raise SystemExit(
            "missing pinctrl %s; flash nodes: %s" % (pin, " ".join(known))
        )
    return phandles[shortest(hits)]


def main():
    if len(sys.argv) != 3:
        raise SystemExit("usage: gen-overlay.py <dtb> <dts-out>")
    phandles = parse(decompile(sys.argv[1]))
    nand = find_unit(phandles, "30030000")
    emmc = find_unit(phandles, "30020000")
    pins = [pin_phandle(phandles, p) for p in PIN_ORDER]
    cells = " ".join("0x%x" % n for n in pins)
    print("nand", nand)
    print("emmc", emmc)
    print("pinctrl", cells)
    dts = """/dts-v1/;
/plugin/;

/ {
	fragment@0 {
		target-path = "%s";
		__overlay__ {
			compatible = "rockchip,rk-nandc";
			clock-names = "clk_nandc", "hclk_nandc";
			nandc_id = <0>;
			status = "okay";
			pinctrl-names = "default";
			pinctrl-0 = <%s>;
		};
	};

	fragment@1 {
		target-path = "%s";
		__overlay__ {
			status = "disabled";
		};
	};
};
""" % (nand, cells, emmc)
    with open(sys.argv[2], "w") as fh:
        fh.write(dts)


if __name__ == "__main__":
    main()
