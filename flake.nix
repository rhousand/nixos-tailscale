{
  description = "Nixos Tailscale Subnet Router";
  /*
  The input section tell nix what repos to use when building code.
    When changing nixos release branch remember to update system.stateVersion variable in configuration.nix.
  */
  inputs = {
    # Package sets
    nixpkgs.url = "nixpkgs/nixos-24.05";
    nixos-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    #home-manager.url = "github:nix-community/home-manager-24.05";
    #home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };
  /*
  Outputs pass the input repos to the code being built.
    Note self is added for the following reasons:

      Modularity: self allows you to build outputs that depend on other outputs within the same flake. This makes it easier to manage complex configurations by splitting them into smaller, reusable components.

      Self-referencing: When you want to reference an attribute of the flake within its own outputs. For example, if you have multiple packages or apps defined within the same flake and one depends on another, you can use self to reference the dependencies.

      Consistency: Using self ensures that all references within the flake are consistent and always point to the current state of the flake. This is particularly useful for ensuring that all outputs are built from the same version of the source code.

  The Let binding is the same as most functional programming languages in nix. It allows you to set vars that will be passed to code.
    Note:
      I the Nix lanaguage Variables are static and can not be altered within the code.
  */
  outputs = {
    self,
    nixpkgs,
    nixos-unstable,
    ...
  }: let
    lib = nixpkgs.lib;
  in {
    nixosConfigurations = {
      ts-sn-test1 = lib.nixosSystem {
        system = "x86_64-linux";
        modules = let
          gladstoneArgs = {
            # tsAuthKey should not be created as a reusable key in Tailscale
            tsAuthKey = "tskey-auth-kTnLC4a9mY11CNTRL-rydesjccmPSAQDUPm9JiPSzbxmkUiXmL";
            hostName = "ts-sn-test1";
          };
        in [
          ./configuration.nix
          /*
          Pass gladstoneArgs to the subnet-router.nix config.
            Remember to add gladstoneArgs to the the top lib import of the module.
          To use the viriable for gladstoneArgs use gladstoneArgs.VAR_NAME
          */
          ({
            config,
            pkgs,
            lib,
            ...
          }: {
            imports = [
              (import ./services/tailscale/subnet-router.nix {inherit config pkgs lib gladstoneArgs;})
            ];
          })

          # Nixpkgs Unstable Overlay allows some packages to be built using the unstable branch on nix packages.
          ({
            pkgs,
            config,
            ...
          }: {
            nixpkgs = {
              overlays = [
                (self: super: {
                  unstable = import nixos-unstable {
                    system = "x86_64-linux";
                    config.allowUnfree = true;
                  };
                })
              ];
            };
          })
        ];
      };
      ts-sn-test2 = lib.nixosSystem {
        system = "x86_64-linux";
        modules = let
          gladstoneArgs = {
            tsAuthKey = "tskey-auth-kDhHtSrqTn11CNTRL-ZhpWoi6KCe51A1ZqTBo8e5eisT83iEbz";
            hostName = "ts-sn-test2";
          };
        in [
          ./configuration.nix
          ({
            config,
            pkgs,
            lib,
            ...
          }: {
            imports = [
              (import ./services/tailscale/subnet-router.nix {inherit config pkgs lib gladstoneArgs;})
            ];
          })

          ({
            pkgs,
            config,
            ...
          }: {
            nixpkgs = {
              overlays = [
                (self: super: {
                  unstable = import nixos-unstable {
                    system = "x86_64-linux";
                    config.allowUnfree = true;
                  };
                })
              ];
            };
          })
        ];
      };
    };
  };
}
