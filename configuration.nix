{
  pkgs,
  modulesPath,
  ...
}: {
  imports = ["${modulesPath}/virtualisation/amazon-image.nix"];

  # By nix purests flakes are experimental however they have been stable for years. To make nix commands shorter we tell nix to allow flakes below:
  nix.settings.experimental-features = ["nix-command" "flakes"];

  # Install vim from nixpkgs an tailscale from nixpkgs-unstable.
  environment.systemPackages = with pkgs; [
    vim-full
    unstable.tailscale
    git
  ];
  system.stateVersion = "25.05";
}
