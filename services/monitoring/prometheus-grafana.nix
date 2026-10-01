{ config, pkgs, lib, gladstoneArgs, ... }: {
  # Monitor host: Prometheus (TSDB) + Grafana (dashboards).
  # Domain/region are repo constants (see services/maintenance.nix, aws-monitoring.nix).

  services.prometheus = {
    enable = true;
    retentionTime = "90d";
    globalConfig.scrape_interval = "15s";

    # Local-only. Even though tailscale0 is a trusted firewall interface (which
    # would otherwise expose 9090 across the tailnet), Prometheus has no auth, so
    # we bind it to loopback. Reach it with an SSH tunnel for /targets, /alerts.
    listenAddress = "127.0.0.1";
    port = 9090;

    scrapeConfigs = [
      # Monitor scrapes its own node_exporter. This is the only live target
      # until node_exporter is deployed to the clients.
      {
        job_name = "monitor-self";
        static_configs = [{
          targets = [ "localhost:9100" ];
          labels.instance = gladstoneArgs.hostName;
        }];
      }

      # Static tailnet targets addressed by MagicDNS name. Add a host here once
      # it runs node_exporter and the ACL permits tag:monitoring -> it on tcp:9100.
      {
        job_name = "tailnet-static";
        static_configs = [{
          targets = [
            "nixos-builder-x84-64-linux.tail21a653.ts.net:9100"
            "ts-sn-test11.tail21a653.ts.net:9100"
            "ts-sn-test12.tail21a653.ts.net:9100"
          ];
        }];
        relabel_configs = [
          # strip the domain so Grafana shows a short instance name
          { source_labels = [ "__address__" ];
            regex = "([^.]+)\\..*";
            replacement = "\${1}";
            target_label = "instance"; }
        ];
      }

      # EC2 auto-discovery, gated to instances tagged monitoring=true. Needs the
      # IAM role (ec2:DescribeInstances) on this host. Resolves each target over
      # the tailnet by MagicDNS, so the instance's EC2 Name tag must equal its
      # Tailscale device name (e.g. Name=ts-sn-stage11) and it must run
      # node_exporter with the ACL permitting tag:monitoring -> it on tcp:9100.
      {
        job_name = "ec2-nodes";
        ec2_sd_configs = [{ region = "us-east-1"; port = 9100; }];
        relabel_configs = [
          # Only running instances that opted in with tag monitoring=true.
          { source_labels = [ "__meta_ec2_instance_state" ]; regex = "running"; action = "keep"; }
          { source_labels = [ "__meta_ec2_tag_monitoring" ]; regex = "true"; action = "keep"; }
          # Labels shown in Grafana.
          { source_labels = [ "__meta_ec2_tag_Name" ]; target_label = "instance"; }
          { source_labels = [ "__meta_ec2_instance_id" ]; target_label = "instance_id"; }
          # Scrape over the tailnet (EC2 SD only exposes AWS IPs).
          { source_labels = [ "__meta_ec2_tag_Name" ];
            replacement = "\${1}.tail21a653.ts.net:9100";
            target_label = "__address__"; }
        ];
      }
      # Prometheus' own metrics: TSDB size, ingest rate, head series, scrape
      # health. Without this job every prometheus_* series is absent, so TSDB
      # growth can only be measured by hand on the box and TsdbGrowthUnbounded
      # in build-alerts.nix cannot evaluate.
      #
      # 60s, not the 15s global: these are slow-moving gauges, and Prometheus
      # exports a few thousand series about itself. A quarter of the sample rate
      # is a quarter of the disk for no loss of signal here.
      {
        job_name = "prometheus-self";
        scrape_interval = "60s";
        static_configs = [{
          targets = [ "localhost:9090" ];
          labels.instance = gladstoneArgs.hostName;
        }];
      }

      # Binary-cache serve stats from the builder's Caddy (hosts/nixos-builder/
      # harmonia.nix). 200 on /nar/* means a client pulled from the cache, 404 on
      # a .narinfo means a miss it will rebuild -- i.e. whether the build server
      # is earning its keep. Needs the Tailscale ACL to permit
      # tag:monitoring -> tag:x86-builder on tcp:9180.
      {
        job_name = "builder-cache";
        scrape_interval = "30s";
        static_configs = [{
          targets = [ "nixos-builder-x84-64-linux.tail21a653.ts.net:9180" ];
          labels.instance = "nixos-builder-x84-64-linux";
        }];
      }
      # ------------------------------------------------------------------------
    ];
  };

  age.secrets.grafana-secret-key = {
    file = ../../secrets/grafana-secret-key.age;
    owner = "grafana";
    group = "grafana";
    mode = "0400";
  };

  services.grafana = {
    enable = true;
    settings.security.secret_key = "$__file{${config.age.secrets.grafana-secret-key.path}}";
    settings.server = {
      # Loopback only — Tailscale serve (grafana-sso.nix) terminates TLS and
      # proxies to this. Nothing reaches :3000 directly over the tailnet.
      http_addr = "127.0.0.1";
      http_port = 3000;
      domain = "${gladstoneArgs.hostName}.tail21a653.ts.net";
      root_url = "https://${gladstoneArgs.hostName}.tail21a653.ts.net/";
    };

    # Render times in the viewer's browser timezone (server + Prometheus stay UTC).
    settings.date_formats.default_timezone = "browser";

    # Auto-provision the Prometheus datasource.
    provision.datasources.settings.datasources = [{
      name = "Prometheus";
      type = "prometheus";
      uid = "prometheus"; # stable uid so provisioned dashboards can reference it
      access = "proxy";
      url = "http://127.0.0.1:9090";
      isDefault = true;
    }];
  };
}
