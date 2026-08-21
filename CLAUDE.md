# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a NixOS Flakes-based repository for deploying Tailscale infrastructure, primarily subnet routers for connecting AWS EC2 instances to a Tailscale network. The repository uses agenix for secret management and supports multiple deployment configurations.

## Architecture

### Flake Structure

The `flake.nix` is the entry point that defines multiple NixOS system configurations. Each configuration represents a different deployment target:

- **Subnet Routers** (ts-sn-test11, ts-sn-test12, ts-sn-stage1, ts-sn-stage11): Full-featured Tailscale subnet routers with connector advertising and routing capabilities
- **Standard Node** (tsNode): Basic Tailscale node without routing features
- **Graylog Server** (graylog-server): Logging infrastructure with Tailscale connectivity

### Module System

Each configuration is composed of modules imported in the following pattern:

1. `configuration.nix` - Base system configuration for EC2 instances
2. `services/maintenance.nix` - Automatic updates, garbage collection, and optimization
3. `security/agenix.nix` - Secret management setup
4. `services/tailscale/subnet-router.nix` OR `services/tailscale/node.nix` - Tailscale service configuration

### gladstoneArgs Pattern

The repository uses a custom argument passing pattern called `gladstoneArgs` to inject configuration into modules. This is passed through module imports:

```nix
gladstoneArgs = {
  tsAdvertiseTags = "tag:snowflake";
  hostName = "ts-sn-test11";
  tsKeyAgeFile = "secrets/ts-sn-test11-tskey.age";
};
```

These args are then used in imported modules via `inherit` statements.

### Secret Management

Uses agenix for encrypting Tailscale auth keys:
- Encrypted secrets stored in `secrets/*.age` files
- Public keys defined in `secrets/secrets.nix`
- Each host has its own encrypted tskey file
- Secrets decrypted at runtime using SSH host keys in `/etc/ssh/ssh_host_ed25519_key` or `/root/.ssh/id_ed25519`

### Subnet Router Configuration

The `services/tailscale/subnet-router.nix` module configures:
- `useRoutingFeatures = "server"` for subnet routing
- `authKeyFile` pointing to decrypted agenix secret
- `extraUpFlags` for SSH, connector advertising, and tag assignment
- Network dispatcher rules for UDP GRO optimization
- Firewall rules trusting the tailscale0 interface

### System Architecture

All configurations target EC2 instances:
- Import `amazon-image.nix` module
- Enable EFI boot
- Support both x86_64-linux and aarch64-linux (newer deployments use ARM)
- Uses nixos-unstable overlay for latest Tailscale package

## Common Commands

### Building Configurations

Build a specific configuration without switching:
```bash
nix build .#nixosConfigurations.ts-sn-test11.config.system.build.toplevel
```

### Deploying to Current System

Deploy a configuration on the target machine:
```bash
nixos-rebuild switch --flake .#ts-sn-test11
```

For configurations using environment variables (like tsNode):
```bash
export TS_AUTH_KEY=tskey-auth-xxxxxxxxxx
nixos-rebuild switch --flake .#tsNode --impure
```

### Secret Management

Create a new encrypted secret for a host:
```bash
# First, ensure the host's public key is in secrets/secrets.nix
# Then encrypt a secret
agenix -e secrets/ts-sn-newhost-tskey.age
```

Re-key all secrets after adding new public keys:
```bash
cd secrets
agenix --rekey
```

### Flake Operations

Update flake inputs:
```bash
nix flake update
```

Update specific input:
```bash
nix flake lock --update-input nixpkgs
```

Check flake:
```bash
nix flake check
```

## Adding New Subnet Router

When adding a new subnet router configuration:

1. Generate the host's SSH key on the target system (or obtain its public key)
2. Add the public key to `secrets/secrets.nix` in both the `systems` list and the secret definition
3. Create an encrypted age file for the Tailscale auth key: `agenix -e secrets/ts-sn-newhost-tskey.age`
4. Add a new configuration block in `flake.nix` following the existing pattern
5. Set appropriate `gladstoneArgs` with hostname, tags, and tsKeyAgeFile path
6. Deploy with `nixos-rebuild switch --flake .#ts-sn-newhost`

## Important Notes

- Tailscale auth keys are managed via agenix, never hardcode them in the flake
- The system.stateVersion should match the nixpkgs input version (currently 25.05)
- Automatic updates run daily at 02:00 with randomized 45min delay
- Garbage collection runs daily at 00:01, deleting generations older than 10 days
- Network optimization for UDP GRO forwarding is critical for subnet router performance
