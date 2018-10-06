#!/bin/bash
# Easy ArchLinux install with full-disk encryption.

DRIVE="$2"
SWAP_SIZE?=16G
VOL_GROUP?=Arcrypt
SHRED_ITERATIONS?=1

# Exit on any error
set -o errexit

print_usage () {
	echo "Usage: "
	echo "   arcrypt.sh format /dev/sdX"
	echo "   arcrypt.sh mount  /dev/sdX"
}
mount_drive () {
	echo " ---- Mounting $DRIVE --"
	cryptsetup open "$DRIVE"4 cryptlvm
	mount /dev/$VOL_GROUP/root /mnt
	swapon /dev/$VOL_GROUP/swap
	cryptsetup open "$DRIVE"4 cryptboot --key-file /mnt/crypto_keyfile.bin
	mount /dev/mapper/cryptboot /mnt/boot
	mount "$DRIVE"2 /mnt/efi
}
format_drive () {
	#TODO: explode if files in /mnt
	echo " ---- Formatting $DRIVE --"
	gdisk -l "$DRIVE"
	echo -n ' ---- Are you sure????   type "YES" to confirm: '
	_CONFIRM=""
	read _CONFIRM
	if [ "$_CONFIRM" != "YES" ]; then exit 1; fi

	# Wipe and format drive
	shred -v -n$SHRED_ITERATIONS -z "$DRIVE"
	sgdisk -o "$DRIVE"
	sgdisk -n 1:0:+1M -t 1:ef02 -c 1:"BIOS Boot Partition" "$DRIVE"
	sgdisk -n 2:0:+550M -t 2:ef00 -c 2:"EFI System Partition" "$DRIVE"
	sgdisk -n 3:0:+200M -t 3:8300 -c 3:"Boot partition" "$DRIVE"
	sgdisk -n 4:0:0 -t 4:8e00 -c 4:"$VOL_GROUP LVM" "$DRIVE"
	sgdisk -p "$DRIVE"

	# Prepare main partition
	echo "Set your crypto disk password"
	cryptsetup luksFormat --type luks2 "$DRIVE"4
	cryptsetup open "$DRIVE"4 cryptlvm
	pvcreate /dev/mapper/cryptlvm
	vgcreate $VOL_GROUP /dev/mapper/cryptlvm
	lvcreate -L $SWAP_SIZE $VOL_GROUP -n swap
	lvcreate -l 100%FREE $VOL_GROUP -n swap
	mkfs.ext4 /dev/$VOL_GROUP/root
	mkswap /dev/$VOL_GROUP/swap
	mount /dev/$VOL_GROUP/root /mnt
	swapon /dev/$VOL_GROUP/swap

	# Prepare boot partition
	dd bs=512 count=4 if=/dev/urandom of=/mnt/crypto_keyfile.bin
	chmod 000 /crypto_keyfile.bin
	cryptsetup luksAddKey "$DRIVE"4 /mnt/crypto_keyfile.bin
	cryptsetup luksFormat "$DRIVE"3 --key-file /mnt/crypto_keyfile.bin
	cryptsetup open "$DRIVE"3 cryptboot --key-file /mnt/crypto_keyfile.bin
	mkfs.ext4 /dev/mapper/cryptboot
	mkdir /mnt/boot
	mount /dev/mapper/cryptboot /mnt/boot

	# Preare efi partition
	mkfs.fat -F32 "$DRIVE"2
	mkdir /mnt/efi
	mount "$DRIVE"2 /mnt/efi

	# Prepare bootloader
	pacstrap /mnt base grub efibootmgr
	genfstab -U /mnt >> /mnt/etc/fstab
	# Edit /etc/mkinitcpio.conf
	InitHooks="HOOKS=(base udev autodetect keyboard keymap consolefont modconf block encrypt lvm2 resume filesystems fsck)"
	InitFile="FILES=(/crypto_keyfile.bin)"
	sed -i "s/^HOOKS=.*/$InitHooks/" /mnt/etc/mkinitcpio.conf
	sed -i "s/^FILES=.*/$InitFile/" /mnt/etc/mkinitcpio.conf
	# Edit /etc/default/grub
	LVM_BLKID=`lsblk "$DRIVE"4 -o UUID |grep "$DRIVE"4 | awk '{print $NF}'`
	GRUB_CMD="GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=$LVM_BLKID:cryptlvm resume=/dev/$VOL_GROUP/swap\""
	GRUB_CRYPTO="GRUB_ENABLE_CRYPTODISK=y"
	sed -i "s/^GRUB_CMDLINE_LINUX=.*/$GRUB_CMD/" /mnt/etc/default/grub
	sed -i "s/^#GRUB_ENABLE_CRYPTODISK=.*/$GRUB_CRYPTO/" /mnt/etc/default/grub
	echo "cryptboot ${2}3 /crypto_keyfile.bin luks" >> /mnt/etc/crypttab

	arch-chroot /mnt
	# Install microcode updates
	cat /proc/cpuinfo | grep -q GenuineIntel && pacman -Syu intel-ucode
	cat /proc/cpuinfo | grep -q AuthenticAMD && pacman -Syu amd-ucode
	# Install bootloaders
	grub-mkconfig -o /boot/grub/grub.cfg
	grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=ARCH --recheck
	grub-install --target=i386-pc --recheck "$DRIVE"
	mkinitcpio -p linux
	chmod 600 /boot/initramfs-linux*
}

##
if [ "$1" == "format" ]; then
	format_drive
elif [ "$1" == "mount" ]; then
	mount_drive
else
	print_usage
	exit 1
fi
