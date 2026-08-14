{ config, pkgs, lib, gladstoneArgs, ... }:
let
  # ---- Fill in your Snowflake connection details ----
  account = "LDB66807";                 # account LOCATOR (from SELECT CURRENT_ACCOUNT()).
                                        # Key-pair JWT auth keys off the locator, not the
                                        # org-account name. AWS_US_WEST_2 = no region suffix.
  username = "SRVC_PROMETHOUT_EXPORTER";       # the dedicated monitoring user
  warehouse = "TF-WH_USER_SRVC_PROMETHEUS_EXPORTER";            # small XS warehouse for the queries
  role = "TF-ROLE_USER_SRVC_PROMETHEUS_EXPORTER";    # least-priv role (IMPORTED PRIVILEGES on SNOWFLAKE)
  # ---------------------------------------------------

  # Grafana dashboards + Prometheus alerts from the upstream monitoring mixin,
  # pinned to the same rev the package was built from so metric names stay in
  # sync. Bump `mixinRev` + re-prefetch the hashes to update.
  mixinRev = "d9447d3401aa81b26c091775606c502bf8e2d7cd";
  mixinBase = "https://raw.githubusercontent.com/grafana/snowflake-prometheus-exporter/${mixinRev}/mixin";
  dashOverview = pkgs.fetchurl {
    url = "${mixinBase}/dashboards_out/snowflake-overview.json";
    hash = "sha256-tKEqKnvl4dL6zAHkc7dXM08pkxxZPwsaXVFzmVtxMcM=";
  };
  dashOwnership = pkgs.fetchurl {
    url = "${mixinBase}/dashboards_out/snowflake-data-ownership.json";
    hash = "sha256-+bYYKnRiMKiGG3mNJPI2Wz7x/RPkLVxb0tnDtUU+6ew=";
  };
  # Alert rules: adapted from the upstream mixin (mixin/prometheus_alerts.yaml)
  # but with credit thresholds tuned to ts-mon1's observed burn (~10 compute
  # credits/hr, ~0.26 cloud-services credits/hr as of 2026-08). The upstream
  # defaults (4/5 compute, 0.8/1 services) sit below our normal usage and would
  # alert constantly. Metrics are 24h trailing averages of credits/hr, so these
  # catch sustained overspend, not single-query spikes. Re-tune after a couple
  # weeks of data + a Snowsight cost cross-check. Also fixes the upstream
  # copy-paste bug where the critical services alert was labelled "Compute".
  snowflakeAlerts = pkgs.writeText "snowflake-alerts.yml" ''
    groups:
      - name: SnowflakeAlerts
        rules:
          - alert: SnowflakeWarnHighLoginFailures
            annotations:
              description: '{{ printf "%.2f" $value }}% of logins have failed on {{$labels.instance}}, above the 30% threshold.'
              summary: Large Snowflake login failure rate.
            expr: |
              100 * sum by (job, instance) (last_over_time(snowflake_failed_login_rate{job="integrations/snowflake"}[1h])) / sum by (job, instance) (last_over_time(snowflake_login_rate{job="integrations/snowflake"}[1h]))
              > 30
            for: 5m
            labels:
              severity: warning
          - alert: SnowflakeWarnHighComputeCreditUsage
            annotations:
              description: Compute credit usage is {{ printf "%.2f" $value }} credits/hr (24h avg) for {{$labels.instance}}, above the 15 credits/hr warning threshold.
              summary: Snowflake compute credit usage is high.
            expr: |
              sum by (job, instance) (last_over_time(snowflake_used_compute_credits{job="integrations/snowflake"}[1h]))
              > 15
            for: 15m
            labels:
              severity: warning
          - alert: SnowflakeCriticalHighComputeCreditUsage
            annotations:
              description: Compute credit usage is {{ printf "%.2f" $value }} credits/hr (24h avg) for {{$labels.instance}}, above the 20 credits/hr critical threshold.
              summary: Snowflake compute credit usage is critically high.
            expr: |
              sum by (job, instance) (last_over_time(snowflake_used_compute_credits{job="integrations/snowflake"}[1h]))
              > 20
            for: 15m
            labels:
              severity: critical
          - alert: SnowflakeWarnHighServiceCreditUsage
            annotations:
              description: Cloud services credit usage is {{ printf "%.2f" $value }} credits/hr (24h avg) for {{$labels.instance}}, above the 1 credit/hr warning threshold.
              summary: Snowflake cloud services credit usage is high.
            expr: |
              sum by (job, instance) (last_over_time(snowflake_used_cloud_services_credits{job="integrations/snowflake"}[1h]))
              > 1
            for: 15m
            labels:
              severity: warning
          - alert: SnowflakeCriticalHighServiceCreditUsage
            annotations:
              description: Cloud services credit usage is {{ printf "%.2f" $value }} credits/hr (24h avg) for {{$labels.instance}}, above the 2 credits/hr critical threshold.
              summary: Snowflake cloud services credit usage is critically high.
            expr: |
              sum by (job, instance) (last_over_time(snowflake_used_cloud_services_credits{job="integrations/snowflake"}[1h]))
              > 2
            for: 15m
            labels:
              severity: critical
          - alert: SnowflakeDown
            annotations:
              description: The Snowflake exporter failed to scrape one or more metrics for instance {{$labels.instance}}.
              summary: Snowflake exporter failed to scrape.
            expr: last_over_time(snowflake_up{job="integrations/snowflake"}[1h]) == 0
            for: 5m
            labels:
              severity: warning
  '';
in {
  # RSA private key (unencrypted p8) for key-pair auth. Handed to the service via
  # systemd credentials below, so it stays readable only by the exporter even
  # under DynamicUser. Encrypt it with:
  #   agenix -e secrets/ts-mon1-snowflake-key.age
  age.secrets.snowflake-key.file = ../../secrets/ts-mon1-snowflake-key.age;

  # Local-only exporter (loopback, never on the tailnet). Package comes from the
  # unstable overlay already present on ts-mon1 (needs the nixos-unstable input
  # updated past 2026-08 so it includes prometheus-snowflake-exporter).
  systemd.services.snowflake-exporter = {
    description = "Snowflake Prometheus exporter";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      DynamicUser = true;
      # systemd reads the agenix key as root and exposes it in the per-service
      # credentials dir (%d), readable by the DynamicUser.
      LoadCredential = [ "snowflake-private-key:${config.age.secrets.snowflake-key.path}" ];
      ExecStart = lib.concatStringsSep " " [
        "${pkgs.unstable.prometheus-snowflake-exporter}/bin/snowflake-exporter"
        "--web.listen-address=127.0.0.1:9975"
        "--account=${account}"
        "--username=${username}"
        "--warehouse=${warehouse}"
        "--role=${role}"
        "--private-key-path=%d/snowflake-private-key"
      ];
      Restart = "on-failure";
      RestartSec = 30;
    };
  };

  # Prometheus scrapes it over loopback. IMPORTANT: the collector queries
  # Snowflake synchronously on each scrape (tens of seconds), so scrape slowly
  # with a generous timeout. Merges with scrapeConfigs in prometheus-grafana.nix.
  # Job name must be "integrations/snowflake": the upstream mixin dashboards +
  # alerts hard-filter every query on job="integrations/snowflake" (Grafana Cloud
  # integration convention). A different job name leaves the dashboards empty.
  services.prometheus.scrapeConfigs = [{
    job_name = "integrations/snowflake";
    scrape_interval = "300s";
    scrape_timeout = "60s";
    static_configs = [{ targets = [ "127.0.0.1:9975" ]; }];
  }];

  # Dashboards drop into the dir the existing "yace" Grafana provider already
  # watches (/etc/grafana-dashboards) — no new provider needed.
  environment.etc."grafana-dashboards/snowflake-overview.json".source = dashOverview;
  environment.etc."grafana-dashboards/snowflake-data-ownership.json".source = dashOwnership;

  # Alert rules routed through the existing Alertmanager -> Slack. Own ruleFile
  # so it isn't concatenated with the node/yace rules.
  services.prometheus.ruleFiles = [ snowflakeAlerts ];
}
