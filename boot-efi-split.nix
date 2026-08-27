# Move the EFI System Partition off /boot and onto /boot/efi.
#
# Importing this module is only half the change: it does not move a mount on
# an already-running host. Each host also needs a one-time manual remount
# before the rebuild that first picks this up --
#   umount /boot && mkdir -p /boot/efi && mount /dev/disk/by-label/ESP /boot/efi
# -- otherwise grub-install writes into an empty directory on the root
# filesystem, leaves the real ESP untouched, and the next boot silently comes
# up on the previous generation.
#
# The amazon-image layout gives us a 249M ESP mounted at /boot, and every
# system generation costs ~90M there (64M kernel Image + 26M initrd on
# aarch64). At boot.loader.grub.configurationLimit = 2 the installer peaks at
# three generations on disk -- it copies the new one *before* pruning the old
# ones -- which is 270M and does not fit. /boot fills, grub-install fails
# halfway, and nixos-upgrade.service dies leaving a partial *.initrd.tmp
# behind.
#
# Lowering configurationLimit only delays this, and the ESP cannot be grown:
# it is nvme0n1p1, ahead of the root partition, so there is no free space
# after it to expand into.
#
# The real fix is to stop copying kernels at all. install-grub.pl does:
#
#   if (stat($bootPath)->dev != stat("/nix/store")->dev) { $copyKernels = 1; }
#
# so setting boot.loader.grub.copyKernels = false is ignored for as long as
# the ESP is mounted at /boot. Once /boot is a plain directory on the root
# filesystem -- same device as /nix/store -- copyKernels stays 0 and grub.cfg
# references kernels in /nix/store directly via `search --fs-uuid`. The ESP
# then holds only EFI/BOOT/BOOTAA64.EFI (~2M), /boot/grub moves to the root
# filesystem (~13M, and root has 42G free), and generation count stops
# mattering entirely.
#
# ec2.efi is disabled because it is the only switch that drops
# amazon-image.nix's `fileSystems."/boot"` -- there is no way to un-declare a
# mountpoint that a module has already defined. As of nixpkgs f4f6986 that
# option has exactly four effects: the /boot mount, and the three grub
# settings re-asserted below. If a future nixpkgs adds more uses of cfg.efi,
# revisit this file.
{ lib, ... }:
{
  # mkForce, not a plain `false`: configuration.nix sets `ec2.efi = true` at
  # the same priority, and the option merges its definitions by OR rather than
  # erroring on the conflict -- a plain `false` is silently swallowed and
  # fileSystems."/boot" stays. Verify with:
  #   nix eval .#nixosConfigurations.<host>.config.fileSystems
  # which must show "/" and "/boot/efi", with no "/boot".
  ec2.efi = lib.mkForce false;

  # Re-assert verbatim what ec2.efi = true would have set. mkForce because
  # amazon-image.nix assigns these at normal priority in the efi = false
  # branch, so a plain definition would collide rather than override.
  boot.loader.grub.device = lib.mkForce "nodev";
  boot.loader.grub.efiSupport = lib.mkForce true;
  boot.loader.grub.efiInstallAsRemovable = lib.mkForce true;

  boot.loader.efi.efiSysMountPoint = "/boot/efi";

  fileSystems."/boot/efi" = {
    device = "/dev/disk/by-label/ESP";
    fsType = "vfat";
  };

  # Kernels are no longer copied to the ESP, so the menu length is only a
  # question of how many /nix/store generations GRUB lists. Keep a real
  # rollback window.
  boot.loader.grub.configurationLimit = lib.mkForce 10;
}
