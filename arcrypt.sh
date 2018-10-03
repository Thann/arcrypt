#!/bin/bash

VOL_GROUP?=MyVolGroup
LVM_BLKID=`lsblk "$2"4 -o UUID |grep "$2"4 | awk '{print $NF}'`

print_usage () {
	echo "Usage: "
	echo "   arcrypt.sh format /dev/sdX"
	echo "   arcrypt.sh mount  /dev/sdX"
}
mount_drive () {
 	echo " ---- Mounting $2 --"
	cryptsetup open "$2"4 cryptlvm
	mount /dev/MyVolGroup/root /mnt
	swapon /dev/MyVolGroup/swap
	cryptsetup open "$2"4 cryptboot --key-file /mnt/crypto_keyfile.bin
	mount /dev/mapper/cryptboot /mnt/boot
	mount "$2"2 /mnt/efi
}
format_drive () {
	#TODO: explode if files in /mnt
	echo " ---- Formatting $2 --"
	echo `lsblk | grep $2`;
	echo " ---- Are you sure????"
	#TODO: confirm
	#TODO: gdisk
	# Prepare main partition
	echo "Set your crypto disk password"
	cryptsetup luksFormat --type luks2 "$2"4
	cryptsetup open "$2"4 cryptlvm
	pvcreate /dev/mapper/cryptlvm
	vgcreate MyVolGroup /dev/mapper/cryptlvm
	lvcreate -L 16G MyVolGroup -n swap
	lvcreate -l 100%FREE MyVolGroup -n swap
	mkfs.ext4 /dev/MyVolGroup/root
	mkswap /dev/MyVolGroup/swap
	mount /dev/MyVolGroup/root /mnt
	swapon /dev/MyVolGroup/swap

	# Prepare boot partition
	dd bs=512 count=4 if=/dev/urandom of=/mnt/crypto_keyfile.bin
	chmod 000 /crypto_keyfile.bin
	cryptsetup luksAddKey "$2"4 /mnt/crypto_keyfile.bin
	cryptsetup luksFormat "$2"3 --key-file /mnt/crypto_keyfile.bin
	cryptsetup open "$2"3 cryptboot --key-file /mnt/crypto_keyfile.bin
	mkfs.ext4 /dev/mapper/cryptboot
	mkdir /mnt/boot
	mount /dev/mapper/cryptboot /mnt/boot

	# Preare efi partition
	mkfs.fat -F32 "$2"2
	mkdir /mnt/efi
	mount "$2"2 /mnt/efi

	# Prepare bootloader
	genfstab -U /mnt >> /mnt/etc/fstab
	pacstrap /mnt base grub efibootmgr
	#TODO: /etc/mkinicpio.conf
	# HOOKS=(base udev autodetect keyboard keymap consolefont modconf block encrypt lvm2 resume filesystems fsck)
	# FILES=(/crypto_keyfile.bin)
	#TODO: /etc/default/grub
	# GRUB_CMDLINE_LINUX="cryptdevice=UUID=$LVM_BLKID:cryptlvm resume=/dev/MyVolGroup/swap"
	# GRUB_ENABLE_CRYPTODISK=y
	echo "cryptboot ${2}3 /crypto_keyfile.bin luks" >> /mnt/etc/crypttab

	# Install bootloader
	arch-chroot /mnt
	grub-mkconfig -o /boot/grub/grub.cfg
	grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=ARCH --recheck
	grub-install --target=i386-pc --recheck /dev/sda
	mkinicpio -p linux
	chmod 600 /boot/initramfs-linux*
	# exit #chroot
}

##
if [ "$1" == "format" ]; then
	format_drive "$2"
elif [ "$1" == "mount" ]; then
	mount_drive "$2"
else
	print_usage
	exit 1
fi
