# Deploy TailScale 
  
    [TOC]

## New Node Connector / Subnet Router
### Edit the flake.nix file and copy the last host in the nixosConfiguration section of a host. 
A host block will look something like this:

```
ts-sn-test2 = lib.nixosSystem {
        system = "x86_64-linux";
        modules = let
          gladstoneArgs = {
            tsAuthKey = "tskey-auth-...";
            tsAdvertiseTags = ["rds-nonprod"]
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
```
### Update the gladstoneArgs to match the requirements for the Node
  * gladstoneArgs.tsAuthKey: the install key created from the Tailscale web console.
  * tsAdvertisedTags: list of tags used by tailscale to attach the node to a Application.
  * hostName:  This sets the hostname of the EC2 instance.
  * Refer to the first node configuration for documentation of each variables. 
Note: When adding new variables use Lower Camel Case styling.
* Save and commit your changes.


... More to come..