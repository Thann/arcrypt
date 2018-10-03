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
This will also do the `mount`, `pacstrap`, `genfstab` and `arch-chroot` install-steps for you.

If you need to mount again in the future do `arcrypt mount /dev/sdX`

