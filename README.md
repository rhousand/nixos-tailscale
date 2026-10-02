# NixOS Flake for Tailscale Deployment

This repository contains NixOS configurations for deploying Tailscale nodes: subnet
routers, a shared build server with a binary cache, a monitoring host running
Prometheus and Grafana, and a Graylog logging server.

## Hosts

| Host | Role |
|---|---|
| `ts-sn-test11`, `ts-sn-test12`, `ts-sn-stage11` | Tailscale subnet routers, advertising routes and tags |
| `nixos-builder-x84-64-linux` | shared remote build server and Harmonia binary cache |
| `ts-mon1` | Prometheus, Grafana, Alertmanager |
| `graylog-server` | Graylog, MongoDB, OpenSearch |
| `tsNode` | plain Tailscale node |

Secrets are managed with [agenix](https://github.com/ryantm/agenix): Tailscale auth
keys and credentials live encrypted in `secrets/*.age` and are decrypted at
activation using each host's SSH host key. Never put a `tskey-auth-…` in `flake.nix`.

## Build server and binary cache

The subnet routers set `max-jobs = 0` and `distributedBuilds = true`, so they
evaluate locally and ship every derivation to `nixos-builder-x84-64-linux` over SSH,
pulling results back from its Harmonia cache. Two consequences worth knowing:

- If the builder is down or mid-change, **client rebuilds fail** — they cannot build
  locally. Deploy builder changes first and verify the cache still serves.
- Each host's `system.autoUpgrade.flake` must be a **remote git ref**, not
  `inputs.self.outPath`. The latter bakes a `/nix/store` path in at build time, so
  the host rebuilds the same frozen snapshot forever while reporting success — a
  failure that is invisible to exit codes and took two months to notice on the
  builder.

## Monitoring and observability

`ts-mon1` scrapes the fleet over the tailnet and is reachable at
`https://ts-mon1.tail21a653.ts.net/` (Grafana, behind Entra ID SSO; TLS terminated by
`tailscale serve`). Prometheus and Alertmanager stay bound to loopback — neither has
authentication — so reach them with an SSH tunnel:

```bash
ssh -N -L 9090:127.0.0.1:9090 -L 9093:127.0.0.1:9093 root@ts-mon1.tail21a653.ts.net
```

### Exporters and scrape jobs

| Module | What it provides |
|---|---|
| `services/monitoring/node-exporter.nix` | node_exporter on `:9100`, tailnet-only, with the `systemd` and `textfile` collectors |
| `services/monitoring/build-metrics.nix` | `nixos_upgrade_*` and `nixos_generation_*` via the textfile collector |
| `services/monitoring/prometheus-grafana.nix` | Prometheus + Grafana, and every scrape job |
| `services/monitoring/cloudwatch-yace.nix` | CloudWatch metrics (EC2 CPU credits, EBS burst) |
| `services/monitoring/tailscale-exporter.nix` | tailnet device and route metrics |
| `services/monitoring/snowflake-exporter.nix` | Snowflake usage — **currently disabled** pending a credit-spend review |
| `services/monitoring/alertmanager-slack.nix` | Alertmanager → Slack, plus `amtool` on PATH |

Hosts are discovered either by EC2 service discovery (tag the instance
`monitoring=true`; its EC2 `Name` tag **must** equal its Tailscale device name) or by
being listed statically. See the onboarding guide below.

### Build metrics

`build-metrics.nix` hooks `nixos-upgrade.service` and emits:

| Metric | Meaning |
|---|---|
| `nixos_upgrade_last_exit_code` | exit status of the last run, 0 = success |
| `nixos_upgrade_duration_seconds` | wall-clock duration of that run |
| `nixos_upgrade_last_run_timestamp_seconds` | when it finished |
| `nixos_upgrade_last_success_timestamp_seconds` | preserved across failures, so "time since a good build" keeps counting |
| `nixos_generation_number` | current system generation |
| `nixos_generation_build_timestamp_seconds` | when that generation was activated |

Generation age is the metric that matters most: an exit code only says the run
finished, not that the system actually moved. The metric-writing hooks are prefixed
with `-` so a failure to emit metrics can never fail the upgrade itself —
observability must not be able to break the thing it observes.

### Dashboards and alerts

- `dashboards/nixos-builds.json` — build outcomes, durations, generation ages,
  builder saturation, binary-cache hit rate, and a coverage table of NixOS hosts
  emitting no build metrics.
- Node Exporter Full (grafana.com 1860) is fetched and provisioned by
  `services/monitoring/build-dashboards.nix`, which rewrites its datasource
  placeholder and **fails the build** if that rewrite stops matching — otherwise an
  upstream change silently yields a dashboard where every panel is blank.
- `services/monitoring/build-alerts.nix` — rules for upgrade failures, stale
  upgrades, stale generations, builder availability and disk, binary-cache errors,
  and two coverage rules so a host going *quiet* is as visible as one going wrong.

Both dashboards land in `/etc/grafana-dashboards`, which Grafana watches — no restart
needed to pick up a change.

## Documentation

- [Onboarding a host into Prometheus](docs/prometheus-host-onboarding.md) — the
  order of operations that avoids paging yourself, how to verify a host landed, which
  alerts to expect and when, and how to decommission a host without stale alerts.

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
# run all commands as root or u
mkdir -p /root/.config/sops/age
# Deploy to the target host
nixos-rebuild switch --flake .#ts-sn-test1
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

- `services/maintenance.nix` configures the remote builder, binary-cache
  substituters, automatic garbage collection and store optimisation, and
  `system.autoUpgrade`.
- Subnet routers upgrade at 02:00 UTC and the builder at 12:00, both with up to 45
  minutes of jitter, so the builder is idle while its clients need it.
- To deploy by hand, prefer running the unit detached rather than in your SSH
  session:

  ```bash
  systemd-run --unit=nxup --setenv=HOME=/root \
    --setenv=PATH=/run/current-system/sw/bin \
    /run/current-system/sw/bin/systemctl start nixos-upgrade.service
  ```

  A `nixos-rebuild switch` run directly from an interactive session restarts `sshd`
  and tears down root's per-user systemd manager mid-activation, which makes
  `switch-to-configuration` exit 4 even when the system switched correctly.

## Security Notes

- Always use temporary auth keys with limited permissions
- Configure appropriate firewall rules for production use
- Consider enabling authentication for MongoDB in production environments
- Rotate auth keys regularly and use the minimum required permissions
- Exporters listen on the tailnet only — `openFirewall` stays `false` and ports are
  opened explicitly on `tailscale0`. The public firewall allows only SSH and the
  Tailscale UDP port.
- Prometheus, Alertmanager and the builder's Caddy metrics endpoint have no
  authentication. Prometheus and Alertmanager are bound to loopback; the metrics
  endpoint is tailnet-only and deliberately separate from Caddy's admin API on
  `127.0.0.1:2019`, which can rewrite the running config unauthenticated and must
  never be exposed.
