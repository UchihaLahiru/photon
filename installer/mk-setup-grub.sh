#!/bin/bash
#################################################
#       Title:  mk-setup-grub                   #
#        Date:  2014-11-26                      #
#     Version:  1.0                             #
#      Author:  sharathg@vmware.com             #
#     Options:                                  #
#################################################
#    Overview
#        This is a precursor for the vmware build system.
#        This assumes that an empty hard disk is attached to the build VM.
#        The path to this empty disk is specified in the HDD variable in config.inc
#    End
#

grub_efi_install()
{
    mkdir -p $BUILDROOT/boot/efi
    #
    # if it is a loop device then we should mount the dev mapped boot partition
    #
    if [[ $HDD == *"loop"* ]]
    then
         BOOT_PARTITION=/dev/mapper/`basename ${HDD}`p1
    else
         BOOT_PARTITION=${HDD}2
    fi
    mkfs.vfat $BOOT_PARTITION
    mount -t vfat $BOOT_PARTITION $BUILDROOT/boot/efi
    cp boot/unifont.pf2 /usr/share/grub/
    grub2-efi-install --target=x86_64-efi --efi-directory=$BUILDROOT/boot/efi --bootloader-id=Boot --root-directory=$BUILDROOT --recheck
    rm $BUILDROOT/boot/efi/EFI/Boot/grubx64.efi
    cp EFI/BOOT/bootx64.efi $BUILDROOT/boot/efi/EFI/Boot/bootx64.efi
    mkdir -p $BUILDROOT/boot/efi/boot/grub2
    echo "configfile (hd0,gpt1)/boot/grub2/grub.cfg" > $BUILDROOT/boot/efi/boot/grub2/grub.cfg
    umount $BUILDROOT/boot/efi
}

grub_mbr_install()
{
    $grubInstallCmd --force --boot-directory=$BUILDROOT/boot "$HDD"
}

set -o errexit        # exit if error...insurance ;)
set -o nounset        # exit if variable not initalized
set +h            # disable hashall
PRGNAME=${0##*/}    # script name minus the path
source config.inc        #    configuration parameters
source function.inc        #    commonn functions
LOGFILE=/var/log/"${PRGNAME}-${LOGFILE}"    #    set log file name
ARCH=$(uname -m)    # host architecture
[ ${EUID} -eq 0 ]    || fail "${PRGNAME}: Need to be root user: FAILURE"
> ${LOGFILE}        #    clear/initialize logfile

# Check if passing a HHD and partition
if [ $# -eq 5 ] 
    then
        BOOTMODE=$1
    HDD=$2
    ROOT_PARTITION_PATH=$3
    BOOT_PARTITION_PATH=$4
    BOOT_DIRECTORY=$5
fi

#
#    Install grub2.
#
PARTUUID=$(blkid -s PARTUUID -o value $ROOT_PARTITION_PATH)
BOOT_UUID=$(blkid -s UUID -o value $BOOT_PARTITION_PATH)

grubInstallCmd=""
mkdir -p $BUILDROOT/boot/grub2
ln -sfv grub2 $BUILDROOT/boot/grub
command -v grub-install >/dev/null 2>&1 && grubInstallCmd="grub-install" && { echo >&2 "Found grub-install"; }
command -v grub2-install >/dev/null 2>&1 && grubInstallCmd="grub2-install" && { echo >&2 "Found grub2-install"; }

if [ "$BOOTMODE" == "bios" ]; then
    if [ -z $grubInstallCmd ]; then
        echo "Unable to find grub install command"
        exit 1
    fi
    grub_mbr_install
fi
if [ "$BOOTMODE" == "efi" ]; then 
    grub_efi_install
fi

rm -rf ${BUILDROOT}/boot/grub2/fonts
cp boot/ascii.pf2 ${BUILDROOT}/boot/grub2/
mkdir -p ${BUILDROOT}/boot/grub2/themes/photon
cp boot/splash.png ${BUILDROOT}/boot/grub2/themes/photon/photon.png
cp boot/terminal_*.tga ${BUILDROOT}/boot/grub2/themes/photon/
cp boot/theme.txt ${BUILDROOT}/boot/grub2/themes/photon/
cat > $BUILDROOT/boot/grub2/grub.cfg << EOF
# Begin /boot/grub2/grub.cfg

set default=0
set timeout=5
search -n -u $BOOT_UUID -s
loadfont ${BOOT_DIRECTORY}grub2/ascii.pf2

insmod gfxterm
insmod vbe
insmod tga
insmod png
insmod ext2
insmod part_gpt

set gfxmode="640x480"
gfxpayload=keep

terminal_output gfxterm

set theme=${BOOT_DIRECTORY}grub2/themes/photon/theme.txt
load_env -f ${BOOT_DIRECTORY}photon.cfg
if [ -f  ${BOOT_DIRECTORY}systemd.cfg ]; then
    load_env -f ${BOOT_DIRECTORY}systemd.cfg
else
    set systemd_cmdline=net.ifnames=0
fi
set rootpartition=PARTUUID=$PARTUUID

menuentry "Photon" {
    linux ${BOOT_DIRECTORY}\$photon_linux root=\$rootpartition \$photon_cmdline \$systemd_cmdline
    if [ -f ${BOOT_DIRECTORY}\$photon_initrd ]; then
        initrd ${BOOT_DIRECTORY}\$photon_initrd
    fi
}
# End /boot/grub2/grub.cfg
EOF

#Cleanup the workspace directory
rm -rf "$BUILDROOT"/tools
rm -rf "$BUILDROOT"/RPMS

