{
  description = "Nixos Tailscale Subnet Router";

  inputs = {
    # Package sets
    nixpkgs.url = "nixpkgs/nixos-24.05";
    nixos-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    #home-manager.url = "github:nix-community/home-manager-24.05";
    #home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

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
            tsAuthKey = "tskey-auth-kTnLC4a9mY11CNTRL-rydesjccmPSAQDUPm9JiPSzbxmkUiXmL";
            hostName = "ts-sn-test1";
          };
        in [
          ./configuration.nix
          # Pass gladstoneArgs to the subnet-router.nix config.
          #   Remember to add gladstoneArgs to the the top lib import of the module..
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

          #./services/tailscale/subnet-router.nix
          # Nixpkgs Unstable Overlay
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
          # Pass gladstoneArgs to the subnet-router.nix config.
          #   Remember to add gladstoneArgs to the the top lib import of the module..
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

          #./services/tailscale/subnet-router.nix
          # Nixpkgs Unstable Overlay
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
