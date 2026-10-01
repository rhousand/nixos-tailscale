{ pkgs, ... }: {
  # Alert rules for the build pipeline: nixos-upgrade outcome, generation age,
  # builder health, binary-cache errors, plus coverage checks that catch a host
  # going quiet rather than going wrong.
  #
  # Its own ruleFiles entry, not services.prometheus.rules: the latter would be
  # concatenated with the node/yace rules into one YAML document with two
  # `groups:` keys, which Prometheus rejects. Same reasoning as
  # cloudwatch-yace.nix.
  #
  # Routing to Slack is already handled by alertmanager-slack.nix.
  services.prometheus.ruleFiles = [
    (pkgs.writeText "build-rules.yml" ''
      groups:
        - name: NixBuilds
          rules:
            # --- did the rebuild work? ---------------------------------------
            - alert: NixosUpgradeFailed
              expr: nixos_upgrade_last_exit_code != 0
              for: 10m
              labels:
                severity: warning
              annotations:
                summary: 'nixos-upgrade failed on {{ $labels.instance }}'
                description: 'Last run exited {{ $value }}. Check: journalctl -u nixos-upgrade -n 200'

            - alert: NixosUpgradeStale
              # Clients run at 02:00, the builder at 12:00, both with up to 45m
              # jitter. 36h means a host missed two of its own windows.
              expr: time() - nixos_upgrade_last_success_timestamp_seconds > 129600
              for: 30m
              labels:
                severity: warning
              annotations:
                summary: 'No successful nixos-upgrade on {{ $labels.instance }} for 36h'
                description: 'The unit may not be running at all. Check: systemctl list-timers nixos-upgrade'

            - alert: NixosGenerationStale
              # The check that would have caught the build server sitting frozen on
              # a July generation for two months while reporting success in 1.7s
              # per run. Exit code cannot see a no-op rebuild; generation age can.
              # Flake inputs move weekly, so 14d on one generation is wrong.
              expr: time() - nixos_generation_build_timestamp_seconds > 1209600
              for: 1h
              labels:
                severity: warning
              annotations:
                summary: '{{ $labels.instance }} has not built a new generation in 14 days'
                description: 'nixos-upgrade may be succeeding while rebuilding a frozen snapshot. Check the flake ref it actually uses: systemctl cat nixos-upgrade.service | grep -- --flake'

            # --- the builder everything else depends on ----------------------
            - alert: BuilderDown
              # Scoped to the node_exporter job on purpose. Two jobs now carry
              # instance="nixos-builder-x84-64-linux" -- tailnet-static (:9100) and
              # builder-cache (:9180) -- so an unscoped up{instance=...} == 0 also
              # matches the metrics port and would page critical for "build server
              # unreachable" when only its Caddy metrics endpoint is blocked.
              expr: up{instance="nixos-builder-x84-64-linux",job="tailnet-static"} == 0
              for: 10m
              labels:
                severity: critical
              annotations:
                summary: 'Build server unreachable'
                description: 'Clients set max-jobs = 0, so every host nightly rebuild depends on this one. Their upgrades will fail while it is down.'

            - alert: BuilderCacheMetricsDown
              # The cache metrics endpoint being unreachable says nothing about the
              # cache itself: Harmonia serves on :5000 behind Caddy on 80/443, while
              # this is the separate :9180 metrics site. Blind panels, not an outage.
              expr: up{job="builder-cache"} == 0
              for: 30m
              labels:
                severity: warning
              annotations:
                summary: 'Builder Caddy metrics endpoint unreachable — cache hit-rate panels are blind'
                description: 'The cache may be serving fine. Check the Tailscale ACL permits tag:monitoring -> tag:x86-builder on tcp:9180, and that caddy is listening: ss -ltnp | grep 9180'

            - alert: BuilderStoreLow
              expr: node_filesystem_avail_bytes{instance="nixos-builder-x84-64-linux",mountpoint="/"} < 15e9
              for: 15m
              labels:
                severity: warning
              annotations:
                summary: 'Builder root below 15 GB — builds will start failing'
                description: 'Currently {{ $value | humanize1024 }}B free. nix.gc runs daily at 00:01 with --delete-older-than 10d.'

            - alert: CacheErrorRate
              # caddy_http_responses_total does NOT exist in Caddy 2.11.4; the code
              # label lives on the request-duration histogram's _count series.
              expr: |
                sum(rate(caddy_http_request_duration_seconds_count{job="builder-cache",code=~"5.."}[10m]))
                  / sum(rate(caddy_http_request_duration_seconds_count{job="builder-cache"}[10m])) > 0.05
              for: 15m
              labels:
                severity: warning
              annotations:
                summary: 'Harmonia serving over 5% 5xx — clients falling back to rebuilding'
                description: 'Cache misses are normal (404); 5xx means the cache itself is broken.'

            # --- coverage: catch a host going quiet, not just going wrong -----
            - alert: NixosUpgradeUnitFailed
              # Reads the systemd collector rather than our textfile, so it also
              # covers NixOS hosts this repo does not manage. Coarser than the
              # metrics above: no duration, no exit code, no generation age. It
              # would NOT have caught the builder freeze, which reported success.
              expr: node_systemd_unit_state{name="nixos-upgrade.service",state="failed"} == 1
              for: 10m
              labels:
                severity: warning
              annotations:
                summary: 'nixos-upgrade.service is in failed state on {{ $labels.instance }}'
                description: 'Fires even where build-metrics.nix is not deployed. Check: journalctl -u nixos-upgrade -n 200'

            - alert: NixosBuildMetricsMissing
              # A scraped NixOS host emitting no build metrics is invisible to every
              # rule above -- an absent series never satisfies a comparison. Info,
              # not warning: this is a configuration gap, not an incident.
              expr: |
                count by (instance) (node_os_info{id="nixos"})
                  unless count by (instance) (nixos_generation_number)
              for: 2h
              labels:
                severity: info
              annotations:
                summary: '{{ $labels.instance }} is NixOS but reports no build metrics'
                description: 'Import services/monitoring/build-metrics.nix on it, or accept NixosUpgradeUnitFailed as its only coverage.'

            # --- monitor the monitor -----------------------------------------
            - alert: MonitorDiskLow
              # ts-mon1 holds the TSDB. Root was grown to 59 GB on 2026-09-25 and
              # sits near 39 GB free; retention should plateau around 7.5 GB of
              # TSDB. 4 GB is a floor, not a forecast.
              expr: node_filesystem_avail_bytes{instance="ts-mon1",mountpoint="/"} < 4e9
              for: 30m
              labels:
                severity: warning
              annotations:
                summary: 'ts-mon1 root below 4 GB — Prometheus will stop writing'
                description: 'Growth outran retention. Find the cardinality: topk(10, count by (job) ({__name__=~".+"}))'

            - alert: TsdbGrowthUnbounded
              # Retention should flatten the TSDB from about 2026-11-01. Firing
              # after that means series count is still climbing. Needs the
              # prometheus-self scrape job in prometheus-grafana.nix.
              expr: predict_linear(prometheus_tsdb_storage_blocks_bytes[7d], 30 * 86400) > 12e9
              for: 6h
              labels:
                severity: warning
              annotations:
                summary: 'Prometheus TSDB projected above 12 GB within 30 days'
                description: 'Currently {{ $value | humanize1024 }}B projected. Expected plateau is about 7.5 GB.'
    '')
  ];
}
