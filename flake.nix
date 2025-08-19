{
  description = "Nixos Tailscale Subnet Router";
  /*
  The input section tell nix what repos to use when building code.
    When changing nixos release branch remember to update system.stateVersion variable in configuration.nix.
  */
  inputs = {
    # Package sets
    nixpkgs.url = "nixpkgs/nixos-25.05";
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
  } @ inputs: let
    lib = nixpkgs.lib;
  in {
    nixosConfigurations = {
      #   ____        _                _
      #  / ___| _   _| |__  _ __   ___| |_
      #  \___ \| | | | '_ \| '_ \ / _ \ __|
      #   ___) | |_| | |_) | | | |  __/ |_
      #  |____/ \__,_|_.__/|_| |_|\___|\__|
      #
      #   ____             _               ____             __ _
      #  |  _ \ ___  _   _| |_ ___ _ __   / ___|___  _ __  / _(_) __ _ ___
      #  | |_) / _ \| | | | __/ _ \ '__| | |   / _ \| '_ \| |_| |/ _` / __|
      #  |  _ < (_) | |_| | ||  __/ |    | |__| (_) | | | |  _| | (_| \__ \
      #  |_| \_\___/ \__,_|\__\___|_|     \____\___/|_| |_|_| |_|\__, |___/
      #                                                          |___/
      ts-sn-test11 = lib.nixosSystem {
        #system = "x86_64-linux";
        system = "aarch64-linux";
        specialArgs = {inherit inputs;};
        modules = let
          gladstoneArgs = {
            # tsAuthKey should not be created as a reusable key in Tailscale
            tsAuthKey = "tskey-auth-kTnLC4a9mY11CNTRL-rydesjccmPSAQDUPm9JiPSzbxmkUiXmL";
            tsAdvertiseTags = "tag:snowflake";
            hostName = "ts-sn-test11";
          };
        in [
          ./configuration.nix
          ./services/maintenance.nix
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
                    system = "aarch64-linux";
                    config.allowUnfree = true;
                  };
                })
              ];
            };
          })
        ];
      };
      ts-sn-test12 = lib.nixosSystem {
        system = "aarch64-linux";
        specialArgs = {inherit inputs;};
        modules = let
          gladstoneArgs = {
            tsAuthKey = "tskey-auth-kDhHtSrqTn11CNTRL-ZhpWoi6KCe51A1ZqTBo8e5eisT83iEbz";
            tsAdvertiseTags = "tag:rds-nonprod";
            hostName = "ts-sn-test12";
          };
        in [
          ./configuration.nix
          ./services/maintenance.nix
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
                    system = "aarch64-linux";
                    config.allowUnfree = true;
                  };
                })
              ];
            };
          })
        ];
      };
      ts-sn-stage11 = lib.nixosSystem {
        system = "aarch64-linux";
        specialArgs = {inherit inputs;};
        modules = let
          gladstoneArgs = {
            tsAuthKey = "tskey-auth-krviUjVvbQ11CNTRL-9p9YANcX7BQKnvXMnZm8BQQA6UZKUWo7P";
            tsAdvertiseTags = "tag:snowflake,tag:rds-stage";
            hostName = "ts-sn-stage11";
          };
        in [
          ./configuration.nix
          ./services/maintenance.nix
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
                    system = "aarch64-linux";
                    config.allowUnfree = true;
                  };
                })
              ];
            };
          })
        ];
      };
#      #    ___  _     _   _____                       ____  _               _      ____             __ _       
#      #  / _ \| | __| | |_   _| __ _   _  ___  _ __ |  _ \(_)_ __ ___  ___| |_   / ___|___  _ __  / _(_) __ _ 
#      # | | | | |/ _` |   | || '__| | | |/ _ \| '_ \| | | | | '__/ _ \/ __| __| | |   / _ \| '_ \| |_| |/ _` |
#      # | |_| | | (_| |   | || |  | |_| | (_) | | | | |_| | | | |  __/ (__| |_  | |__| (_) | | | |  _| | (_| |
#      #  \___/|_|\__,_|   |_||_|   \__, |\___/|_| |_|____/|_|_|  \___|\___|\__|  \____\___/|_| |_|_| |_|\__, |
#      #                            |___/                                                                |___/ 
#      #
#      #   ____        _                _
#      #  / ___| _   _| |__  _ __   ___| |_
#      #  \___ \| | | | '_ \| '_ \ / _ \ __|
#      #   ___) | |_| | |_) | | | |  __/ |_
#      #  |____/ \__,_|_.__/|_| |_|\___|\__|
#      #
#      #   ____             _               ____             __ _
#      #  |  _ \ ___  _   _| |_ ___ _ __   / ___|___  _ __  / _(_) __ _ ___
#      #  | |_) / _ \| | | | __/ _ \ '__| | |   / _ \| '_ \| |_| |/ _` / __|
#      #  |  _ < (_) | |_| | ||  __/ |    | |__| (_) | | | |  _| | (_| \__ \
#      #  |_| \_\___/ \__,_|\__\___|_|     \____\___/|_| |_|_| |_|\__, |___/
#      #                                                          |___/
#      ts-sn-test1 = lib.nixosSystem {
#        system = "x86_64-linux";
#        specialArgs = {inherit inputs;};
#        modules = let
#          gladstoneArgs = {
#            # tsAuthKey should not be created as a reusable key in Tailscale
#            tsAuthKey = "tskey-auth-kTnLC4a9mY11CNTRL-rydesjccmPSAQDUPm9JiPSzbxmkUiXmL";
#            tsAdvertiseTags = "tag:snowflake";
#            hostName = "ts-sn-test1";
#          };
#        in [
#          ./configuration.nix
#          ./services/maintenance.nix
#          /*
#          Pass gladstoneArgs to the subnet-router.nix config.
#            Remember to add gladstoneArgs to the the top lib import of the module.
#          To use the viriable for gladstoneArgs use gladstoneArgs.VAR_NAME
#          */
#          ({
#            config,
#            pkgs,
#            lib,
#            ...
#          }: {
#            imports = [
#              (import ./services/tailscale/subnet-router.nix {inherit config pkgs lib gladstoneArgs;})
#            ];
#          })
#
#          # Nixpkgs Unstable Overlay allows some packages to be built using the unstable branch on nix packages.
#          ({
#            pkgs,
#            config,
#            ...
#          }: {
#            nixpkgs = {
#              overlays = [
#                (self: super: {
#                  unstable = import nixos-unstable {
#                    system = "x86_64-linux";
#                    config.allowUnfree = true;
#                  };
#                })
#              ];
#            };
#          })
#        ];
#      };
#      ts-sn-test2 = lib.nixosSystem {
#        system = "x86_64-linux";
#        specialArgs = {inherit inputs;};
#        modules = let
#          gladstoneArgs = {
#            tsAuthKey = "tskey-auth-kDhHtSrqTn11CNTRL-ZhpWoi6KCe51A1ZqTBo8e5eisT83iEbz";
#            tsAdvertiseTags = "tag:rds-nonprod";
#            hostName = "ts-sn-test2";
#          };
#        in [
#          ./configuration.nix
#          ./services/maintenance.nix
#          ({
#            config,
#            pkgs,
#            lib,
#            ...
#          }: {
#            imports = [
#              (import ./services/tailscale/subnet-router.nix {inherit config pkgs lib gladstoneArgs;})
#            ];
#          })
#
#          ({
#            pkgs,
#            config,
#            ...
#          }: {
#            nixpkgs = {
#              overlays = [
#                (self: super: {
#                  unstable = import nixos-unstable {
#                    system = "x86_64-linux";
#                    config.allowUnfree = true;
#                  };
#                })
#              ];
#            };
#          })
#        ];
#      };
#      ts-sn-stage1 = lib.nixosSystem {
#        system = "x86_64-linux";
#        specialArgs = {inherit inputs;};
#        modules = let
#          gladstoneArgs = {
#            tsAuthKey = "tskey-auth-krviUjVvbQ11CNTRL-9p9YANcX7BQKnvXMnZm8BQQA6UZKUWo7P";
#            tsAdvertiseTags = "tag:snowflake,tag:rds-stage";
#            hostName = "ts-sn-stage1";
#          };
#        in [
#          ./configuration.nix
#          ./services/maintenance.nix
#          ({
#            config,
#            pkgs,
#            lib,
#            ...
#          }: {
#            imports = [
#              (import ./services/tailscale/subnet-router.nix {inherit config pkgs lib gladstoneArgs;})
#            ];
#          })
#
#          ({
#            pkgs,
#            config,
#            ...
#          }: {
#            nixpkgs = {
#              overlays = [
#                (self: super: {
#                  unstable = import nixos-unstable {
#                    system = "x86_64-linux";
#                    config.allowUnfree = true;
#                  };
#                })
#              ];
#            };
#          })
#        ];
#      };
      # _____     _ _ ____            _         ___        _
      #|_   _|_ _(_) / ___|  ___ __ _| | ___   / _ \ _ __ | |_   _
      #  | |/ _` | | \___ \ / __/ _` | |/ _ \ | | | | '_ \| | | | |
      #  | | (_| | | |___) | (_| (_| | |  __/ | |_| | | | | | |_| |
      #  |_|\__,_|_|_|____/ \___\__,_|_|\___|  \___/|_| |_|_|\__, |
      #                                                      |___/
      #  ____             __ _
      # / ___|___  _ __  / _(_) __ _ ___
      #| |   / _ \| '_ \| |_| |/ _` / __|
      #| |__| (_) | | | |  _| | (_| \__ \
      # \____\___/|_| |_|_| |_|\__, |___/
      #                        |___/
      tsNode = lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {inherit inputs;};
        modules = let
          gladstoneArgs = {
            tsAuthKey = builtins.getEnv "TS_AUTH_KEY";
          };
        in [
          ./configuration.nix
          ./services/maintenance.nix
          ({
            config,
            pkgs,
            lib,
            ...
          }: {
            imports = [
              (import ./services/tailscale/node.nix {inherit config pkgs lib gladstoneArgs;})
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
      graylog = lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {inherit inputs;};
        modules = let
          gladstoneArgs = {
            tsAuthKey = builtins.getEnv "TS_AUTH_KEY";
          };
        in [
          ./configuration.nix
          ./services/maintenance.nix
          ./services/graylog/server.nix
          ({
            config,
            pkgs,
            lib,
            ...
          }: {
            imports = [
              (import ./services/tailscale/node.nix {inherit config pkgs lib gladstoneArgs;})
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
