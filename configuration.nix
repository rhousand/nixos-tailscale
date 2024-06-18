{
  pkgs,
  modulesPath,
  ...
}: {
  imports = ["${modulesPath}/virtualisation/amazon-image.nix"];

  nix.settings.experimental-features = ["nix-command" "flakes"];

  environment.systemPackages = with pkgs; [
    vim-full
    unstable.tailscale
  ];
  system.stateVersion = "24.05";
}
