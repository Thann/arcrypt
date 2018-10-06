# Arcrypt
Easy ArchLinux install with full-disk encryption.

After you have an [Arch ISO](https://www.archlinux.org/download/)
Installed onto a [USB drive](https://wiki.archlinux.org/index.php/USB_flash_installation_media),
boot up to it and see the [Installation Guide](https://wiki.archlinux.org/index.php/installation_guide)
on how to get started.  
Utils like `wifi-menu` will probably be handy.

For the partitioning steps, use arcrypt instead. download it like this:
```bash
wget https://raw.githubusercontent.com/Thann/arcrypt/master/arcrypt.sh
chmod 777 arcrypt.sh
```

Arcrypt format will setup a device with [full-disk encryption](https://wiki.archlinux.org/index.php/Dm-crypt/Encrypting_an_entire_system#Encrypted_boot_partition_.28GRUB.29).
This erases the entire drive, so be sure to have the correct one before continuing!
Use `lsblk` to help identify the correct device,
```bash
./arcrypt.sh format /dev/sdX
```
This will also do the `mount`, `pacstrap`, `genfstab` and `arch-chroot` install-steps for you;
continue with ["Time zone"](https://wiki.archlinux.org/index.php/installation_guide#Configure_the_system).  
You can also skip installing a `bootloader` later.

If you need to mount again in the future do `./arcrypt.sh mount /dev/sdX`

This will leave you with a drive partitioned like this:
```
NAME                  MAJ:MIN RM   SIZE RO TYPE  MOUNTPOINT
sda                   8:0      0   200G  0 disk
├─sda1                8:1      0     1M  0 part
├─sda2                8:2      0   550M  0 part  /efi
├─sda3                8:3      0   200M  0 part
│ └─cryptboot         254:0    0   198M  0 crypt /boot
└─sda4                8:4      0   100G  0 part
  └─cryptlvm          254:1    0   100G  0 crypt
    ├─Arcrypt-swap    254:2    0    16G  0 lvm   [SWAP]
    └─Arcrypt-root    254:3    0    84G  0 lvm   /
```
