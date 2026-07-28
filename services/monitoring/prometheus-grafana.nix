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
            # "ts-sn-test11.tail21a653.ts.net:9100"   # add when its exporter is deployed
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

      # --- STAGED: EC2 auto-discovery. Needs the IAM role (ec2:DescribeInstances)
      # on this host + MagicDNS resolving <Name-tag>.tail21a653.ts.net. Enable to
      # auto-register the subnet routers instead of listing them statically.
      # {
      #   job_name = "ec2-nodes";
      #   ec2_sd_configs = [{ region = "us-east-1"; port = 9100; }];
      #   relabel_configs = [
      #     { source_labels = [ "__meta_ec2_tag_Name" ]; target_label = "instance"; }
      #     { source_labels = [ "__meta_ec2_instance_id" ]; target_label = "instance_id"; }
      #     { source_labels = [ "__meta_ec2_instance_state" ]; regex = "running"; action = "keep"; }
      #     { source_labels = [ "__meta_ec2_tag_Name" ];
      #       replacement = "\${1}.tail21a653.ts.net:9100";
      #       target_label = "__address__"; }
      #   ];
      # }
      # ------------------------------------------------------------------------
    ];
  };

  services.grafana = {
    enable = true;
    settings.server = {
      http_addr = "0.0.0.0"; # tailnet-reachable; public side closed by host firewall
      http_port = 3000;
      domain = "${gladstoneArgs.hostName}.tail21a653.ts.net";
    };

    # Auto-provision the Prometheus datasource.
    provision.datasources.settings.datasources = [{
      name = "Prometheus";
      type = "prometheus";
      access = "proxy";
      url = "http://127.0.0.1:9090";
      isDefault = true;
    }];
  };
}
