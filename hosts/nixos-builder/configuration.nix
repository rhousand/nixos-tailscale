{
  pkgs,
  modulesPath,
  ...
}: {
  imports = ["${modulesPath}/virtualisation/amazon-image.nix"];

  # Emulate aarch64 so this x86_64 builder can build for the ARM subnet routers.
  boot.binfmt.emulatedSystems = ["aarch64-linux"];

  networking.hostName = "nixos-builder-x84-64-linux";

  services.openssh = {
    enable = true;
    ports = [8022];
  };

  environment.systemPackages = with pkgs; [
    vim-full
    tailscale
    git
    openssl
    awscli2
    screen
    bottom
    btop
  ];

  nix.settings.experimental-features = ["nix-command" "flakes"];

  # Advertise features so clients can offload NixOS VM tests here. `uid-range`
  # is required by the container/VM test driver and isn't in the default set.
  nix.settings.system-features = [
    "nixos-test"
    "benchmark"
    "big-parallel"
    "kvm"
    "uid-range"
  ];

  # Larger download buffer for pulling big closures during remote builds.
  nix.extraOptions = ''
    download-buffer-size = 10485760
  '';

  # Remote build user. Clients ssh in as `builder` to offload builds.
  users.users.builder = {
    isNormalUser = true;
    extraGroups = ["wheel"];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKMy12iR2O/22EiOtbeiUaM4sXANT3ui+p4LINDeMBKs root@aiNode"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDG7FSnX3EUaGTuUIXRRShv0H5z9nnMzxTWKmDLY3kzh"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILEwR5cCd9w3xIcdVfOrISCnsdeIW1tPlPAv1bE/z/On"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOYi9veCs4pw1pSkzKZBj6n+wHL+muZJnmr+nqsY5v+h root@tryon-etl-python"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHu2zDv8fKYjIOQCmFLMjct621bWuvqdvKqrHUBhNjdo root@graylogserver"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHlqxg6xLWiuR4w+sZ0+6vPulQq0GBKExjZnTvnxkTcM root@ts-sn-test1"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIODrG5WxerELKvcX3K3NNnc5z0r6t9+Nb+ayMf04c10o root@ts-sn-stage1"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJZNU40s+Q5p6/UeRkbk1sUv+RQmE9hBdK7wnKXXRIKz root@ts-mon1"
    ];
  };

  nix.settings.trusted-users = ["root" "builder"];

  system.stateVersion = "24.11";
}
