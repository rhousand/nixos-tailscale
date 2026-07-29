{ config, pkgs, lib, gladstoneArgs, ... }:
{
  # --- Alert rules, evaluated by Prometheus ---
  services.prometheus.rules = [ ''
    groups:
      - name: node-resources
        rules:
          # ---- Disk ----
          - alert: DiskSpaceLow
            expr: 100 * (node_filesystem_avail_bytes{fstype!~"tmpfs|overlay|squashfs"}
                         / node_filesystem_size_bytes) < 95
            for: 10m
            labels: { severity: warning }
            annotations:
              summary: "Low disk on {{ $labels.instance }} ({{ $labels.mountpoint }})"
              description: "{{ $value | printf \"%.1f\" }}% free"
          - alert: DiskSpaceCritical
            expr: 100 * (node_filesystem_avail_bytes{fstype!~"tmpfs|overlay|squashfs"}
                         / node_filesystem_size_bytes) < 5
            for: 5m
            labels: { severity: critical }
            annotations:
              summary: "CRITICAL disk on {{ $labels.instance }} ({{ $labels.mountpoint }})"
              description: "{{ $value | printf \"%.1f\" }}% free"

          # ---- Memory ----
          - alert: HighMemory
            expr: 100 * (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) > 90
            for: 10m
            labels: { severity: warning }
            annotations:
              summary: "High memory on {{ $labels.instance }}"
              description: "{{ $value | printf \"%.1f\" }}% used"

          # ---- CPU ----
          - alert: HighCPU
            expr: 100 * (1 - avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m]))) > 90
            for: 15m
            labels: { severity: warning }
            annotations:
              summary: "High CPU on {{ $labels.instance }}"
              description: "{{ $value | printf \"%.1f\" }}% busy (5m avg)"

          # ---- Host down ----
          - alert: InstanceDown
            expr: up == 0
            for: 5m
            labels: { severity: critical }
            annotations:
              summary: "{{ $labels.instance }} is down"
              description: "No scrape for 5m"
  '' ];

  # Prometheus -> Alertmanager (same host, loopback).
  services.prometheus.alertmanagers = [{
    static_configs = [{ targets = [ "localhost:9093" ]; }];
  }];

  # Slack webhook URL kept out of the Nix store (agenix). Alertmanager runs as a
  # systemd DynamicUser, so we hand the secret in via LoadCredential rather than
  # chowning it: systemd copies it into $CREDENTIALS_DIRECTORY owned by the
  # transient user. The path below is deterministic for the alertmanager unit.
  age.secrets.slackWebhook.file = ../../secrets/slack-webhook-url.age;
  systemd.services.alertmanager.serviceConfig.LoadCredential =
    [ "slack-webhook:${config.age.secrets.slackWebhook.path}" ];

  services.prometheus.alertmanager = {
    enable = true;
    listenAddress = "127.0.0.1"; # local-only, never on the tailnet
    port = 9093;
    # amtool check-config can't read the runtime-only secret path at build time
    # (see the option docs), so skip the sandboxed check. Config is static/reviewed.
    checkConfig = false;
    configuration = {
      global.slack_api_url_file = "/run/credentials/alertmanager.service/slack-webhook";
      route = {
        receiver = "slack";
        group_by = [ "alertname" "instance" ];
        group_wait = "30s";
        group_interval = "5m";
        repeat_interval = "4h"; # re-nag every 4h while still firing
      };
      receivers = [{
        name = "slack";
        slack_configs = [{
          channel = "#grafana-alerts";
          send_resolved = true; # also post when it recovers
          title = "{{ .CommonLabels.severity | toUpper }}: {{ .CommonLabels.alertname }}";
          text = ''{{ range .Alerts }}{{ .Annotations.summary }}
{{ .Annotations.description }}
{{ end }}'';
        }];
      }];
    };
  };
}
