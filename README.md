# NixOS Flake for Tailscale Deployment

This repository contains NixOS configurations for deploying Tailscale nodes, including subnet routers and a Graylog logging server.

## Prerequisites

- NixOS system with Flakes enabled
- Tailscale account and access to the admin console
- Appropriate permissions to create API keys in Tailscale

## Deployment Options

### 1. Subnet Router

A subnet router allows Tailscale nodes to access devices on your local network.

#### Configuration

1. Add a new host configuration in `flake.nix`:

```nix
# In flake.nix outputs

# Replace "ts-sn-test1" with your desired hostname
ts-sn-test1 = lib.nixosSystem {
  system = "x86_64-linux";  # Update for your system architecture
  specialArgs = { inherit inputs; };
  modules = let
    gladstoneArgs = {
      # Generate a new auth key in Tailscale console (set to expire in 1 day)
      tsAuthKey = "tskey-auth-xxxxxxxxxxxxxxxxxxxxxxxx";
      # Set your desired tags (must be created in Tailscale console first)
      tsAdvertiseTags = "tag:your-tag";
      hostName = "ts-sn-test1";  # Match this with your hostname
    };
  in [
    ./configuration.nix
    ./services/maintenance.nix
    
    # Subnet router configuration
    ({ config, pkgs, lib, ... }: {
      imports = [
        (import ./services/tailscale/subnet-router.nix { inherit config pkgs lib gladstoneArgs; })
      ];
    })
  ];
};
```

#### Deployment

```bash
# Deploy to the target host
sudo nixos-rebuild switch --flake .#ts-sn-test1
```

### 2. Graylog Logging Server

Centralized logging server with Graylog, MongoDB, and OpenSearch.

#### Configuration

1. Add a Graylog server configuration in `flake.nix`:

```nix
# In flake.nix outputs
graylog-server = lib.nixosSystem {
  system = "x86_64-linux";  # Update for your system architecture
  specialArgs = { inherit inputs; };
  modules = [
    ./configuration.nix
    ./services/maintenance.nix
    ./services/graylog/server.nix
    
    # Required for MongoDB and OpenSearch
    ({ pkgs, ... }: {
      # Enable required services
      services.mongodb.enable = true;
      services.opensearch.enable = true;
      
      # Open necessary firewall ports
      networking.firewall.allowedTCPPorts = [
        9000   # Graylog web interface
        9200   # OpenSearch
        27017  # MongoDB
      ];
    })
  ];
};
```

#### Deployment

```bash
# Deploy the Graylog server
sudo nixos-rebuild switch --flake .#graylog-server
```

After deployment, access the Graylog web interface at `http://<server-ip>:9000`.

### 3. Standard Tailscale Node

For adding a regular Tailscale node to your network:

1. Create a Tailscale auth key in the admin console
2. Set it as an environment variable:
   ```bash
   export TS_AUTH_KEY=tskey-auth-xxxxxxxxxxxxxxxx
   ```
3. Deploy the node:
   ```bash
   sudo nixos-rebuild switch --flake .#tsNode --impure
   ```

## Maintenance

- The `services/maintenance.nix` module includes common maintenance tasks and configurations
- Regular system updates can be performed with `nixos-rebuild switch --upgrade`

## Security Notes

- Always use temporary auth keys with limited permissions
- Configure appropriate firewall rules for production use
- Consider enabling authentication for MongoDB in production environments
- Rotate auth keys regularly and use the minimum required permissions
