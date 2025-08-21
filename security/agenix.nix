{ config, pkgs, ... }:

let
  gladstoneArgs = config._module.args.gladstoneArgs;
in {
  age = {
    age.identityPaths = [ 
        "/root/.config/age/"
        "/root/.ssh/"
        ];
    secrets = {
      tsKeyAge = {
        file = gladstoneArgs.tsKeyAgeFile;
        owner = "root";
        group = "root";
        permissions = "0400";
      };
    };
  };
}