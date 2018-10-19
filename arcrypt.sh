#!/bin/bash
# Easy ArchLinux install with full-disk encryption.

DRIVE="$2"
SWAP_SIZE="${SWAP_SIZE-16G}"
VOL_GROUP="${VOL_GROUP-Arcrypt}"
SHRED_ITERATIONS="${SHRED_ITERATIONS-1}"

# Exit on any error
set -o errexit

print_usage () {
	echo "Usage: "
	echo "   arcrypt.sh format /dev/sdX"
	echo "   arcrypt.sh mount  /dev/sdX"
}
mount_drive () {
	echo " ---- Mounting $DRIVE ----"
	cryptsetup open "$DRIVE_"4 cryptlvm
	sleep 1
	mount /dev/$VOL_GROUP/root /mnt
	swapon /dev/$VOL_GROUP/swap
	cryptsetup open "$DRIVE_"3 cryptboot --key-file /mnt/crypto_keyfile.bin
	mount /dev/mapper/cryptboot /mnt/boot
	mount "$DRIVE_"2 /mnt/efi
}
format_drive () {
	#TODO: explode if files in /mnt
	echo " ---- Formatting $DRIVE ----"
	gdisk -l "$DRIVE"
	echo -n ' ---- Are you sure????   type "YES" to confirm: '
	_CONFIRM=""
	read _CONFIRM
	if [ "$_CONFIRM" != "YES" ]; then exit 1; fi

	PASSWORD=""
	# Set password
	while [ -z "$PASSWORD" ]; do
		echo -n " == Set Password:"
		read -s -r _TEMP_PWORD; echo
		echo -n " == Confirm Password:"
		read -s -r _TEMP_PWORD_2; echo
		if [ "$_TEMP_PWORD" == "$_TEMP_PWORD_2" ]; then PASSWORD="$_TEMP_PWORD"; fi
	done

	# Wipe and format drive
	shred -v -n$SHRED_ITERATIONS "$DRIVE"
	sgdisk -o "$DRIVE"
	sgdisk -n 1:0:+1M -t 1:ef02 -c 1:"BIOS Boot Partition" "$DRIVE"
	sgdisk -n 2:0:+550M -t 2:ef00 -c 2:"EFI System Partition" "$DRIVE"
	sgdisk -n 3:0:+200M -t 3:8300 -c 3:"Boot partition" "$DRIVE"
	sgdisk -n 4:0:0 -t 4:8e00 -c 4:"$VOL_GROUP LVM" "$DRIVE"
	sgdisk -p "$DRIVE"

	# Prepare main partition
	dd bs=512 count=4 if=/dev/urandom of=/tmp/crypto_keyfile.bin
	cryptsetup luksFormat --type luks2 "$DRIVE_"4 -q --key-file /tmp/crypto_keyfile.bin
	cryptsetup luksAddKey "$DRIVE_"4 -q --key-file /tmp/crypto_keyfile.bin <<< "$PASSWORD"
	cryptsetup open "$DRIVE_"4 cryptlvm --key-file /tmp/crypto_keyfile.bin
	pvcreate /dev/mapper/cryptlvm
	vgcreate $VOL_GROUP /dev/mapper/cryptlvm
	lvcreate -L $SWAP_SIZE $VOL_GROUP -n swap
	lvcreate -l 100%FREE $VOL_GROUP -n root
	mkfs.ext4 /dev/$VOL_GROUP/root
	mkswap /dev/$VOL_GROUP/swap
	mount /dev/$VOL_GROUP/root /mnt
	swapon /dev/$VOL_GROUP/swap
	mv /tmp/crypto_keyfile.bin /mnt/

	# Prepare boot partition
	chmod 000 /mnt/crypto_keyfile.bin
	cryptsetup luksFormat "$DRIVE_"3 -q --key-file /mnt/crypto_keyfile.bin
	cryptsetup luksAddKey "$DRIVE_"3 -q --key-file /mnt/crypto_keyfile.bin <<< "$PASSWORD"
	cryptsetup open "$DRIVE_"3 cryptboot --key-file /mnt/crypto_keyfile.bin
	mkfs.ext4 /dev/mapper/cryptboot
	mkdir /mnt/boot
	mount /dev/mapper/cryptboot /mnt/boot

	# Preare efi partition
	mkfs.fat -F32 "$DRIVE_"2
	mkdir /mnt/efi
	mount "$DRIVE_"2 /mnt/efi

	# Prepare bootloader
	pacstrap /mnt base grub efibootmgr
	genfstab -U /mnt >> /mnt/etc/fstab
	# Edit /etc/mkinitcpio.conf
	INIT_HOOKS="HOOKS=(base udev autodetect keyboard keymap consolefont modconf block encrypt lvm2 resume filesystems fsck)"
	INIT_FILE="FILES=(/crypto_keyfile.bin)"
	sed -i "s|^HOOKS=.*|$INIT_HOOKS|" /mnt/etc/mkinitcpio.conf
	sed -i "s|^FILES=.*|$INIT_FILE|" /mnt/etc/mkinitcpio.conf
	# Edit /etc/default/grub
	LVM_BLKID=`blkid "$DRIVE_"4 | sed -n 's/.* UUID=\"\([^\"]*\)\".*/\1/p'`
	GRUB_CMD="GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=$LVM_BLKID:cryptlvm resume=/dev/$VOL_GROUP/swap\""
	GRUB_CRYPTO="GRUB_ENABLE_CRYPTODISK=y"
	sed -i "s|^GRUB_CMDLINE_LINUX=.*|$GRUB_CMD|" /mnt/etc/default/grub
	sed -i "s|^#GRUB_ENABLE_CRYPTODISK=.*|$GRUB_CRYPTO|" /mnt/etc/default/grub
	echo "cryptboot ${DRIVE_}3 /crypto_keyfile.bin luks" >> /mnt/etc/crypttab

	arch-chroot /mnt <<EOF
	# Install microcode updates
	cat /proc/cpuinfo | grep -q GenuineIntel && pacman -S intel-ucode --noconfirm
	cat /proc/cpuinfo | grep -q AuthenticAMD && pacman -S amd-ucode --noconfirm
	# Install bootloaders
	grub-mkconfig -o /boot/grub/grub.cfg
	grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=ARCH --recheck
	grub-install --target=i386-pc --recheck "$DRIVE"
	mkinitcpio -p linux
	chmod 600 /boot/initramfs-linux*
EOF
	echo " == Dropping off into arch-chroot so you can finish installing  =]"
	arch-chroot /mnt
}

# Support nvme drives
DRIVE_="$DRIVE" # Partition Prefix
if [[ "$2" =~ ^/dev/nvme ]]; then DRIVE_="${DRIVE}p"; fi

##
if [ "$1" == "format" ]; then
	format_drive
elif [ "$1" == "mount" ]; then
	mount_drive
else
	print_usage
	exit 1
fi
