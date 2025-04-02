# Deploying Tailscale to NixOS hosts
## SubnetRouters
### Copy a subnet router host configuration and alter the host name in ./flake.nix
Example host configuration:
```
      ts-sn-test1 = lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {inherit inputs;};
        modules = let
          gladstoneArgs = {
            # tsAuthKey should not be created as a reusable key in Tailscale
            tsAuthKey = "tskey-auth-kTnLC4a9mY11CNTRL-rydesjccmPSAQDUPm9JiPSzbxmkUiXmL";
            tsAdvertiseTags = "tag:snowflake";
            hostName = "ts-sn-test1";
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
                    system = "x86_64-linux";
                    config.allowUnfree = true;
                  };
                })
              ];
            };
          })
        ];
      };
```
### Change it-sn-test1 to the hostname of your sytem
### alter tsAvertiseTags to match the tag used for you new location
Note: you must create a tag in tailscale console prior to deploying this flake
### Replace tsAuthKey with a tailscale Auth Key
Note: Create a TS auth key and set the expire time to 1 day
### Change the system to match the system you are installing this flake. I.e. x86_64-linux, aarch64-linux or the likes
### Save the changes to the flake.nix file
### Deploy the flake replacing the host name below with your host name
`nixos-rebuild switch --flake .#ts-sn-test1`

## Add a system to you TS network
### Create a Tailscale Auth Key
Note: set expire to 1 day and add a tag to the key for your system
### Export the Tailscale Auth Key as and env var
`export TS_AUTH_KEY=<Place Key here>`
### run the flake on the new TS node
Note: You need to pass impure to the command below because this flake will not always be the same due to the env var being passed
`nixos-rebuild switch --flake .#tsNode --impure`

