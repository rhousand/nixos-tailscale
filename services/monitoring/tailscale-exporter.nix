{ config, pkgs, lib, gladstoneArgs, ... }:
let
  # Grafana dashboards from the upstream tailscale-mixin, pinned to the same
  # release the nixpkgs package (v0.6.1) is built from. Bump mixinRev + re-
  # prefetch hashes when updating the exporter package.
  mixinRev = "2f2d78ebcf40e0b7d150225a366e6a157c9e7495";
  mixinBase = "https://raw.githubusercontent.com/adinhodovic/tailscale-exporter/${mixinRev}/tailscale-mixin/dashboards_out";

  dashOverview = pkgs.fetchurl {
    url = "${mixinBase}/tailscale-overview.json";
    hash = "sha256-WgZrRS4gy48x2Jpb1ZvxPfw1ZSUX1bR7FNXH5j5xbl4=";
  };

  # Prometheus alert rules from the upstream mixin, adapted for single-host
  # (no cluster/namespace labels). Only the Tailscale tailnet alerts are kept;
  # Headscale and tailscaled-machine alerts are dropped (we don't run Headscale
  # and the machine dashboard uses recording rules we don't ship yet).
  tailscaleAlerts = pkgs.writeText "tailscale-alerts.yml" ''
    groups:
      - name: TailscaleAlerts
        rules:
          - alert: TailscaleCollectorFailed
            annotations:
              description: 'Tailscale collector {{ $labels.collector }} for tailnet {{ $labels.tailnet }} has been failing for longer than 5m.'
              summary: Tailscale collector failed.
            expr: |
              min(tailscale_scrape_collector_success{}) by (job, collector, tailnet) == 0
            for: 5m
            labels:
              severity: critical
          - alert: TailscaleDeviceUnauthorized
            annotations:
              description: 'Tailscale device {{ $labels.name }} (ID: {{ $labels.id }}) in tailnet {{ $labels.tailnet }} is unauthorized.'
              summary: Tailscale device is unauthorized.
            expr: |
              sum(tailscale_devices_authorized{}) by (job, tailnet, name, id) == 0
            for: 15m
            labels:
              severity: warning
          - alert: TailscaleDeviceUnapprovedRoutes
            annotations:
              description: 'Tailscale device {{ $labels.name }} (ID: {{ $labels.id }}) in tailnet {{ $labels.tailnet }} has >10% unapproved routes.'
              summary: Tailscale device has unapproved routes.
            expr: |
              100 - (
                (
                  sum(tailscale_devices_routes_enabled{}) by (job, tailnet, name, id)
                  /
                  sum(tailscale_devices_routes_advertised{}) by (job, tailnet, name, id)
                ) * 100
              ) > 10
            for: 15m
            labels:
              severity: warning
          - alert: TailscaleExporterDown
            annotations:
              description: 'The Tailscale exporter has been unreachable for 5 minutes.'
              summary: Tailscale exporter is down.
            expr: up{job="tailscale"} == 0
            for: 5m
            labels:
              severity: critical
  '';
in {
  # Encrypted environment file containing OAuth credentials. Create with:
  #   agenix -e secrets/ts-mon1-tailscale-env.age
  # File contents (three lines, no quotes):
  #   TAILSCALE_TAILNET=tail21a653.ts.net
  #   TAILSCALE_OAUTH_CLIENT_ID=k...
  #   TAILSCALE_OAUTH_CLIENT_SECRET=tskey-client-...
  #
  # Generate the OAuth client at:
  #   Tailscale admin console -> Settings -> OAuth clients -> Generate OAuth client
  # Required scopes: devices:core:read, devices:posture_attributes:read,
  #   devices:routes:read, services:read, users:read, dns:read, auth_keys:read,
  #   feature_settings:read, policy_file:read
  age.secrets.tailscale-env = {
    file = ../../secrets/ts-mon1-tailscale-env.age;
    # The NixOS exporter module runs under DynamicUser; systemd's
    # EnvironmentFile reads this as root before dropping privileges.
  };

  services.prometheus.exporters.tailscale = {
    enable = true;
    package = pkgs.unstable.prometheus-tailscale-exporter;
    listenAddress = "127.0.0.1";
    port = 9250;
    environmentFile = config.age.secrets.tailscale-env.path;
  };

  # The exporter needs to resolve api.tailscale.com via MagicDNS. Wait for
  # tailscaled to be fully up so DNS is available at startup.
  systemd.services.prometheus-tailscale-exporter = {
    after = [ "tailscaled.service" ];
    wants = [ "tailscaled.service" ];
    serviceConfig.ExecStartPre = "${pkgs.coreutils}/bin/sleep 5";
  };

  # Prometheus scrape config (merges with scrapeConfigs in prometheus-grafana.nix).
  services.prometheus.scrapeConfigs = [{
    job_name = "tailscale";
    scrape_interval = "60s";
    scrape_timeout = "30s";
    static_configs = [{ targets = [ "127.0.0.1:9250" ]; }];
  }];

  # Dashboards drop into the dir the existing "yace" Grafana provider already
  # watches (/etc/grafana-dashboards) — no new provider needed.
  environment.etc."grafana-dashboards/tailscale-overview.json".source = dashOverview;

  # Alert rules routed through the existing Alertmanager -> Slack pipeline.
  services.prometheus.ruleFiles = [ tailscaleAlerts ];
}
