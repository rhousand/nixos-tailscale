{ config, pkgs, lib, gladstoneArgs, ... }:
let
  # ---- Fill in your Snowflake connection details ----
  account = "uiyvowa-tryon";            # account identifier, e.g. xy12345.us-east-1
  username = "SRVC_PROMETHEUS_EXPORTER";       # the dedicated monitoring user
  warehouse = "TF-WH_USER_SRVC_PROMETHEUS_EXPORTER";            # small XS warehouse for the queries
  role = "TF-WH_USER_SRVC_PROMETHEUS_EXPORTER";      # least-priv role (IMPORTED PRIVILEGES on SNOWFLAKE)
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
  snowflakeAlerts = pkgs.fetchurl {
    url = "${mixinBase}/prometheus_alerts.yaml";
    hash = "sha256-nT01rlmerOeXk/dyuFs8U36sl5yDSd7EpS7Fk3hrRsk=";
  };
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
  services.prometheus.scrapeConfigs = [{
    job_name = "snowflake";
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
