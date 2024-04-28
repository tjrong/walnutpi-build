# DO NOT EDIT THIS FILE

gpio clear 77

# default values
setenv load_addr "0x45000000"
setenv overlay_error "false"
setenv rootdev "/dev/mmcblk1p2"
setenv rootfstype "ext4"
setenv console "both"
setenv docker_optimizations "on"
setenv bootlogo "false"

# Print boot source
itest.b *0x10028 == 0x00 && echo "U-boot loaded from SD"
itest.b *0x10028 == 0x02 && echo "U-boot loaded from eMMC or secondary SD"
itest.b *0x10028 == 0x03 && echo "U-boot loaded from SPI"

echo "Boot script loaded from ${devtype}"

if test -e ${devtype} ${devnum} ${prefix}config.txt; then
	load ${devtype} ${devnum} ${load_addr} ${prefix}config.txt
	env import -t ${load_addr} ${filesize}
fi
if test "${display_bootinfo}" = "enable"; then setenv consoleargs_diplay "console=tty0"; fi

if test "${console_uart}" = "uart0"; then setenv consoleargs "console=ttyS0,115200"; fi
if test "${console_uart}" = "uart1"; then setenv consoleargs "console=ttyS1,115200"; fi
if test "${console_uart}" = "uart2"; then setenv consoleargs "console=ttyS2,115200"; fi
if test "${console_uart}" = "uart3"; then setenv consoleargs "console=ttyS3,115200"; fi
if test "${console_uart}" = "uart4"; then setenv consoleargs "console=ttyS4,115200"; fi
if test "${console_uart}" = "null"; then setenv consoleargs "console=/dev/null"; fi

if test "${bootlogo}" = "true"; then
	setenv consoleargs "splash plymouth.ignore-serial-consoles ${consoleargs}"
else
	setenv consoleargs "splash=verbose ${consoleargs}"
fi

# get PARTUUID of first partition on SD/eMMC it was loaded from
# mmc 0 is always mapped to device u-boot (2016.09+) was loaded from
if test "${devtype}" = "mmc"; then part uuid mmc 0:1 partuuid; fi

setenv bootargs "root=${rootdev} rootwait rw rootfstype=${rootfstype} net.ifnames=0 ${consoleargs} ${consoleargs_diplay}, consoleblank=0 loglevel=${printk_level} ubootpart=${partuuid} usb-storage.quirks=${usbstoragequirks} ${extraargs} ${extraboardargs}"

if test "${docker_optimizations}" = "on"; then setenv bootargs "${bootargs} cgroup_enable=memory swapaccount=1"; fi

load ${devtype} ${devnum} ${fdt_addr_r} ${prefix}${fdtfile}.dtb
fdt addr ${fdt_addr_r}
fdt resize 65536
for overlay_file in ${overlays}; do
	if load ${devtype} ${devnum} ${load_addr} ${prefix}overlays/${overlay_prefix}-${overlay_file}.dtbo; then
		echo "Applying kernel provided DT overlay ${overlay_prefix}-${overlay_file}.dtbo"
		fdt apply ${load_addr} || setenv overlay_error "true"
	fi
done
for overlay_file in ${user_overlays}; do
	if load ${devtype} ${devnum} ${load_addr} ${prefix}overlay-user/${overlay_file}.dtbo; then
		echo "Applying user provided DT overlay ${overlay_file}.dtbo"
		fdt apply ${load_addr} || setenv overlay_error "true"
	fi
done
if test "${overlay_error}" = "true"; then
	echo "Error applying DT overlays, restoring original DT"
	load ${devtype} ${devnum} ${fdt_addr_r} ${prefix}${fdtfile}.dtb
else
	if load ${devtype} ${devnum} ${load_addr} ${prefix}overlays/${overlay_prefix}-fixup.scr; then
		echo "Applying kernel provided DT fixup script (${overlay_prefix}-fixup.scr)"
		source ${load_addr}
	fi
	if test -e ${devtype} ${devnum} ${prefix}fixup.scr; then
		load ${devtype} ${devnum} ${load_addr} ${prefix}fixup.scr
		echo "Applying user provided fixup script (fixup.scr)"
		source ${load_addr}
	fi
fi

load ${devtype} ${devnum} ${kernel_addr_r} ${prefix}Image

if test ${bootlogo} = true; then
	if test -e ${devtype} ${devnum} ${prefix}uInitrd; then
		load ${devtype} ${devnum} ${ramdisk_addr_r} ${prefix}uInitrd
		booti ${kernel_addr_r} ${ramdisk_addr_r} ${fdt_addr_r}
	else
		booti ${kernel_addr_r} - ${fdt_addr_r}
	fi
else
    booti ${kernel_addr_r} - ${fdt_addr_r}
fi


# Recompile with:
# mkimage -C none -A arm -T script -d boot.cmd boot.scr