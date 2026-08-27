{
  description = "Nixos Tailscale Subnet Router";
  /*
  The input section tell nix what repos to use when building code.
    When changing nixos release branch remember to update system.stateVersion variable in configuration.nix.
  */
  inputs = {
    # Package sets
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixos-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";
    harmonia.url = "github:nix-community/harmonia";
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
    agenix,
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
            #tsAuthKey = "tskey-auth-kLUkmDsK8r11CNTRL-BhmE6jstFW42VxKLxe9kV4vEiCTiApKU4";
            tsAdvertiseTags = "tag:snowflake";
            hostName = "ts-sn-test11";
            tsKeyAgeFile = "secrets/ts-sn-test11-tskey.age";
          };
        in [
          ./configuration.nix
          ./services/maintenance.nix
          # See the note in boot-efi-split.nix: this host needs the one-time
          # manual remount of the ESP to /boot/efi before its first rebuild
          # that includes this module.
          ./boot-efi-split.nix
          ({
            config,
            pkgs,
            lib,
            ...
          }: {
            imports = [
              (import ./security/agenix.nix { inherit config pkgs lib inputs gladstoneArgs; })
            ];
          })
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
              (import ./services/monitoring/node-exporter.nix {inherit config pkgs lib gladstoneArgs;})
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
            #tsAuthKey = "tskey-auth-kSM7o3jbzx11CNTRL-xfsxNThM6h3Tg4NtsaMKg3TVGzKaLh9M";
            tsAdvertiseTags = "tag:rds-nonprod";
            hostName = "ts-sn-test12";
            tsKeyAgeFile = "secrets/ts-sn-test12-tskey.age";
          };
        in [
          ./configuration.nix
          ./services/maintenance.nix
          # ESP relocation (/boot -> /boot/efi). Verified on this host by
          # reboot 2026-08-26. Rolling out host by host -- each needs the
          # one-time manual remount documented in boot-efi-split.nix before
          # its first rebuild -- then this moves into configuration.nix.
          ./boot-efi-split.nix
          ({
            config,
            pkgs,
            lib,
            ...
          }: {
            imports = [
              (import ./security/agenix.nix { inherit config pkgs lib inputs gladstoneArgs; })
            ];
          })
          ({
            config,
            pkgs,
            lib,
            ...
          }: {
            imports = [
              (import ./services/tailscale/subnet-router.nix {inherit config pkgs lib gladstoneArgs;})
              (import ./services/monitoring/node-exporter.nix {inherit config pkgs lib gladstoneArgs;})
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
      ts-sn-stage1 = lib.nixosSystem {
        system = "aarch64-linux";
        specialArgs = {inherit inputs;};
        modules = let
          gladstoneArgs = {
            tsAdvertiseTags = "tag:snowflake,tag:rds-stage";
            hostName = "ts-sn-stage1";
            tsKeyAgeFile = "secrets/ts-sn-stage1-tskey.age";
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
              (import ./security/agenix.nix { inherit config pkgs lib inputs gladstoneArgs; })
            ];
          })
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
            tsAdvertiseTags = "tag:snowflake,tag:rds-stage";
            hostName = "ts-sn-stage11";
            tsKeyAgeFile = "secrets/ts-sn-stage11-tskey.age";
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
              (import ./security/agenix.nix { inherit config pkgs lib inputs gladstoneArgs; })
            ];
          })
          ({
            config,
            pkgs,
            lib,
            ...
          }: {
            imports = [
              (import ./services/tailscale/subnet-router.nix {inherit config pkgs lib gladstoneArgs;})
              (import ./services/monitoring/node-exporter.nix {inherit config pkgs lib gladstoneArgs;})
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

          # node.nix does not set a hostname, so without this the host comes up
          # as "nixos" and no longer matches its flake attribute -- which
          # autoUpgrade needs, since it pins the flake ref to
          # `#${config.networking.hostName}`.
          {networking.hostName = "tsNode";}

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
      #  __  __             _ _
      # |  \/  | ___  _ __ (_) |_ ___  _ __
      # | |\/| |/ _ \| '_ \| | __/ _ \| '__|
      # | |  | | (_) | | | | | || (_) | |
      # |_|  |_|\___/|_| |_|_|\__\___/|_|
      #
      # Prometheus + Grafana monitor host (t4g.small, aarch64). Scrapes the fleet's
      # node_exporters over the tailnet. Auth key via agenix like the subnet routers.
      # Device name ts-mon1 → Grafana at ts-mon1.tail21a653.ts.net:3000.
      ts-mon1 = lib.nixosSystem {
        system = "aarch64-linux";
        specialArgs = {inherit inputs;};
        modules = let
          gladstoneArgs = {
            tsAdvertiseTags = "tag:monitoring";
            hostName = "ts-mon1";
            tsKeyAgeFile = "secrets/ts-mon1-tskey.age";
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
              (import ./security/agenix.nix { inherit config pkgs lib inputs gladstoneArgs; })
            ];
          })
          ({
            config,
            pkgs,
            lib,
            ...
          }: {
            imports = [
              (import ./services/tailscale/monitor.nix {inherit config pkgs lib gladstoneArgs;})
              (import ./services/monitoring/node-exporter.nix {inherit config pkgs lib gladstoneArgs;})
              (import ./services/monitoring/prometheus-grafana.nix {inherit config pkgs lib gladstoneArgs;})
              (import ./services/monitoring/grafana-sso.nix {inherit config pkgs lib gladstoneArgs;})
              (import ./services/monitoring/alertmanager-slack.nix {inherit config pkgs lib gladstoneArgs;})
              (import ./services/monitoring/cloudwatch-yace.nix {inherit config pkgs lib gladstoneArgs;})
              (import ./services/monitoring/snowflake-exporter.nix {inherit config pkgs lib gladstoneArgs;})
              (import ./services/monitoring/tailscale-exporter.nix {inherit config pkgs lib gladstoneArgs;})
            ];
          })
          # ts-mon1 only: 2 GiB t4g.small runs Nix eval locally each night. zram gives a
          # compressed in-RAM swap and the 2 GiB disk swapfile is a backstop so an eval
          # memory spike spills to swap instead of OOM-killing the rebuild.
          ({ ... }: {
            zramSwap.enable = true;
            swapDevices = [
              {
                device = "/swapfile";
                size = 2048; # MiB
              }
            ];
          })

          ({
            pkgs,
            config,
            ...
          }: {
            # Reuse nixos-unstable's already-evaluated package set instead of a second
            # `import nixos-unstable {...}`, which instantiates a full second nixpkgs and
            # roughly doubles nightly eval memory. ts-mon1 is a 2 GiB t4g.small that evals
            # locally, so eval must stay lean. legacyPackages is pre-evaluated with
            # allowUnfree = false; ts-mon1 only pulls free unstable pkgs (tailscale,
            # buildGoModule), so no unfree flag is needed here.
            nixpkgs = {
              overlays = [
                (self: super: {
                  unstable = nixos-unstable.legacyPackages.${super.system};
                })
              ];
            };
          })
        ];
      };
      # Attribute name must equal networking.hostName -- "graylog-server", set in
      # services/graylog/server.nix:7. autoUpgrade pins its flake ref to
      # `#${config.networking.hostName}`, so a mismatch here means the upgrade
      # unit asks for a nixosConfigurations attribute that does not exist.
      # Deploy with `nixos-rebuild switch --flake .#graylog-server`.
      graylog-server = lib.nixosSystem {
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
      #  ____        _ _     _
      # | __ ) _   _(_) | __| | ___ _ __
      # |  _ \| | | | | |/ _` |/ _ \ '__|
      # | |_) | |_| | | | (_| |  __/ |
      # |____/ \__,_|_|_|\__,_|\___|_|
      #
      # x86_64 remote builder + harmonia binary cache. Built from nixos-unstable to
      # mirror its existing base; stateVersion pinned to 24.11 in configuration.nix.
      nixos-builder-x84-64-linux = nixos-unstable.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {
          inherit inputs;
          tryonArgs = {
            tsAdvertiseTags = "tag:x86-builder";
          };
        };
        modules = [
          ./hosts/nixos-builder/configuration.nix
          ./hosts/nixos-builder/nixos.nix
          ./hosts/nixos-builder/tailscale.nix
          ./hosts/nixos-builder/aws-monitoring.nix
          ./hosts/nixos-builder/harmonia.nix
        ];
      };
    };
  };
}
