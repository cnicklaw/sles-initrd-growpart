#!/bin/bash
# Modifies the initrd to resize the root partition to the whole disk
# 2013, Alexander von Gluck IV
#
# Original idea by Robert Plestenjak, robert.plestenjak@xlab.si
# Redesigned for SUSE
#
# depends:
# cloud-init from SUSE-Cloud repo (SLES)
#
# what it does:
# - installs itself in '/usr/libexec/suse-image-mod' directory, change
#   '${install_dir}' to change install path
# - automatic partition resize and filesystem increase of root partition
#   during boot
#
install_dir=/usr/libexec/suse-image-mod
growpart_bin=$(which growpart)
#
#

function deps () {
	for file in ${@}; do
		[ ! -z $(echo $file | grep -o "$lib") ] &&
			cp -v ${file} ${lib}/
	done
}

function modify-initrd () {
	echo "--- copying tools and dependencies ..."
	cp -v ${install_dir}/51-growpart.sh boot/
	cp -v ${growpart_bin} sbin/
	cp -v /sbin/sfdisk sbin/
	cp -v /usr/bin/awk bin/
	cp -v /usr/bin/readlink bin/
	cp -v /sbin/e2fsck sbin/
	cp -v /sbin/resize2fs sbin/
	deps "($(ldd sbin/sfdisk))"
	deps "($(ldd bin/awk))"
	deps "($(ldd bin/readlink))"
	deps "($(ldd sbin/e2fsck))"
	deps "($(ldd sbin/resize2fs))"
	echo "--- adding initrd task to resize '/'"
	chmod 755 boot/51-growpart.sh
	mv run_all.sh run_all.sh.old
	sed '/preping 81-resume.userspace.sh/i\
[ "$debug" ] && echo running 51-growpart.sh\nsource boot/51-growpart.sh' run_all.sh.old > run_all.sh
	echo "--- done"
}

# exit if not root
if [ "$USER" != "root" ]; then
	echo "Run as root!"
	exit 1
fi

# exit if no growpart tool
if [ ! -f ${growpart_bin} ]; then
	echo "Growpart tool not found in path!!"
	echo "Get growpart at https://launchpad.net/cloud-utils"
	exit 1
fi

echo "Starting SUSE initrd modification process ..."

# collect system and partitions info
kernel_version=$(uname -r)
root_dev=$(cat /etc/fstab |grep "\/dev\/.*\/ .*" |awk '{print $1}')

# create suse-mod dir and copy scripts
[ ! -d ${install_dir} ] && mkdir -p ${install_dir}
cp suse-image-mod.sh 51-growpart.sh ${install_dir}/

# create backup of important files
echo "- backing up menu.lst >> ${install_dir}/menu.lst.$(date +%Y%m%d-%H%M)"
cp /boot/grub/menu.lst ${install_dir}/menu.lst.$(date +%Y%m%d-%H%M)

# prepare initamfs copy
echo -n "- extracting initrd /boot/initramfs-${kernel_version}, size: "
[ "$(uname -m)" == "x86_64" ] && \
	lib=lib64 || \
	lib=lib
[ -d /tmp/initrd-${kernel_version} ] && \
	rm -rf /tmp/initrd-${kernel_version}
mkdir /tmp/initrd-${kernel_version}
cd /tmp/initrd-${kernel_version}
gunzip -c /boot/initrd-${kernel_version} | cpio -i --make-directories

# modify initrd
echo "- modify initrd copy /tmp/initramfs-${kernel_version}"
modify-initrd

# remove existing initramf mods
echo "- removing all previous mod setups"
rm -fv /boot/initrd-mod-*

# create new initrd
echo -n "- new initrams /boot/initrd-mod-${kernel_version}, size: "
find ./ | cpio -H newc -o > /tmp/initrd.cpio
gzip -c /tmp/initrd.cpio > /boot/initrd-mod-${kernel_version}

# set grub root
root_grub=$(cat /boot/grub/menu.lst |grep -v "^#" |grep -m1 -o "root (hd[0-9],[0-9])")

# modify grub menu
echo "- setting up menu.lst"
grub_entry_title="title SLE 11 mod ${kernel_version}"
grub_entry_root="	${root_grub}"
grub_entry_kernel="	kernel /boot/vmlinuz-${kernel_version} root=${root_dev} splash=silent crashkernel=256M-:128M showopts vga=0x314"
grub_entry_initrd="	initrd /boot/initrd-mod-${kernel_version}"
# remove existing production entry
grub_entry_start="title SLE 11 mod ${kernel_version}"
grub_entry_end="\tinitrd \/boot\/initrd-mod-${kernel_version}"
sed -i "/${grub_entry_start}/,/${grub_entry_end}/d" /boot/grub/menu.lst
# insert new entry
echo "${grub_entry_title}" >> /boot/grub/menu.lst
echo "${grub_entry_root}" >> /boot/grub/menu.lst
echo "${grub_entry_kernel}" >> /boot/grub/menu.lst
echo "${grub_entry_initrd}" >> /boot/grub/menu.lst

# cleanup
#echo "- clean up"
#rm -rf /tmp/initrd-${kernel_version}
#rm -f /tmp/initrd.cpio
#rm -f /tmp/root_part.tmp

echo
echo "Reboot, choose 'title SLE 11 mod ${kernel_version}' in grub"
echo
