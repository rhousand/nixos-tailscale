{ config, pkgs, lib, inputs, gladstoneArgs, ... }:

{
  imports = [
    inputs.agenix.nixosModules.default
  ];

  age.identityPaths = [
    "/etc/ssh/ssh_host_ed25519_key"
    "/root/.ssh/id_ed25519"
  ];

  age.secrets.tsKeyAge = {
    file = ../. + "/${gladstoneArgs.tsKeyAgeFile}";
    owner = "root";
    group = "root";
    mode = "0400";
  };
}