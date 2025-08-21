{ config, pkgs, lib, inputs, gladstoneArgs, ... }:

{
  imports = [
    inputs.agenix.nixosModules.default
  ];

  age.identityPaths = [
    "/root/.config/age/"
    "/root/.ssh/"
  ];

  age.secrets.tsKeyAge = {
    file = ../. + "/${gladstoneArgs.tsKeyAgeFile}";
    owner = "root";
    group = "root";
    mode = "0400";
  };
}