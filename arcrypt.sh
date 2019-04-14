#!/bin/bash
# Easy ArchLinux install with full-disk encryption.

DRIVE="$2"
SWAP_SIZE="${SWAP_SIZE-16G}"
VOL_GROUP="${VOL_GROUP-Arcrypt}"

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

    echo -n " == Shred iterations [1]: "
    read SHRED_ITERATIONS
    SHRED_ITERATIONS="${SHRED_ITERATIONS:-1}"

    # Collect Setup params
    PASSWORD=""
    while [ -z "$PASSWORD" ]; do
        echo -n " == Set DISK Password:"
        read -s -r _TEMP_PWORD; echo
        echo -n " == Confirm DISK Password:"
        read -s -r _TEMP_PWORD_2; echo
        if [ "$_TEMP_PWORD" == "$_TEMP_PWORD_2" ]; then PASSWORD="$_TEMP_PWORD"; fi
    done
    ROOT_PASSWORD=""
    while [ -z "$ROOT_PASSWORD" ]; do
        echo -n " == Set ROOT password: "
        read -s -r _TEMP_PWORD; echo
        echo -n " == Confirm ROOT password: "
        read -s -r _TEMP_PWORD_2; echo
        if [ "$_TEMP_PWORD" == "$_TEMP_PWORD_2" ]; then ROOT_PASSWORD="$_TEMP_PWORD"; fi
    done
    echo -n " == Set username: "
    read _USERNAME
    USER_PASSWORD=""
    while [ -z "$USER_PASSWORD" ]; do
        echo -n " == Set USER password: "
        read -s -r _TEMP_PWORD; echo
        echo -n " == Confirm USER password: "
        read -s -r _TEMP_PWORD_2; echo
        if [ "$_TEMP_PWORD" == "$_TEMP_PWORD_2" ]; then USER_PASSWORD="$_TEMP_PWORD"; fi
    done
    echo -n " == Set hostname: "
    read _HOSTNAME
    echo -n " == Set locale [en_US.UTF-8]: "
    read _LOCALE
    _LOCALE="${_LOCALE:-en_US.UTF-8}"
    echo -n " == Set timezone [America/Los_Angeles]: "
    read _TIMEZONE
    _TIMEZONE="${_TIMEZONE:-America/Los_Angeles}"
    #TODO: keymap?
    echo -n " == Install Gnome desktop? (Y/n): "
    read INSTALL_GNOME
    echo " ---- Running ... ----"

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
    sed -i '6i Server = http://mirrors.kernel.org/archlinux/$repo/os/$arch' /etc/pacman.d/mirrorlist
    timedatectl set-ntp true
    pacman -Sy archlinux-keyring --noconfirm
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
    sed -i "s|^GRUB_TIMEOUT=.*|GRUB_TIMEOUT=1|" /mnt/etc/default/grub
    sed -i "s|^GRUB_CMDLINE_LINUX=.*|$GRUB_CMD|" /mnt/etc/default/grub
    sed -i "s|^#GRUB_ENABLE_CRYPTODISK=.*|$GRUB_CRYPTO|" /mnt/etc/default/grub
    echo "cryptboot ${DRIVE_}3 /crypto_keyfile.bin luks" >> /mnt/etc/crypttab

    #HACK: to fix issue w/ LVM
    mkdir /mnt/hostlvm
    mount --bind /run/lvm /mnt/hostlvm

    arch-chroot /mnt <<- EOF
        set -o errexit
        ln -s /hostlvm /run/lvm
        hwclock --systohc
        echo "root:$ROOT_PASSWORD" | /usr/sbin/chpasswd
        useradd -m -g users "$_USERNAME"
        echo "$_USERNAME:$USER_PASSWORD" | /usr/sbin/chpasswd
        echo "root:$ROOT_PASSWORD" | /usr/sbin/chpasswd
        echo "$_HOSTNAME" >> /etc/hostname
        echo "127.0.0.1 $_HOSTNAME" >> /etc/hosts
        echo "::1 $_HOSTNAME" >> /etc/hosts
        echo "127.0.1.1 $_HOSTNAME.localdomain $_HOSTNAME" >> /etc/hosts
        sed -i "s|#\($_LOCALE.*\)\$|\1|" /etc/locale.gen
        locale-gen
        echo "LANG=$_LOCALE" >> /etc/locale.conf
        ln -sf "/usr/share/zoneinfo/$_TIMEZONE" /etc/localtime
        # Install microcode updates
        cat /proc/cpuinfo | grep -q GenuineIntel && pacman -S intel-ucode --noconfirm
        cat /proc/cpuinfo | grep -q AuthenticAMD && pacman -S amd-ucode --noconfirm
        # Install bootloaders
        mkdir /boot/grub
        grub-mkconfig -o /boot/grub/grub.cfg
        grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=ARCH --recheck
        grub-install --target=i386-pc --recheck "$DRIVE"
        mkinitcpio -p linux
        chmod 600 /boot/initramfs-linux*
        if [ "${INSTALL_GNOME:-y}" == "y" ]; then
            pacman -S gnome gdm --noconfirm
            systemctl enable NetworkManager gdm
        fi
EOF
    echo ' ---- Arcrypt setup complete!  ----  type "reboot" to finish'
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
