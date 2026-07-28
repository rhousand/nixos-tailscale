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

      # --- STAGED: enable once clients run node_exporter -----------------------
      # EC2 auto-discovery. New instances with node_exporter + a matching Name
      # tag register themselves. Needs the IAM role (ec2:DescribeInstances) on
      # this host and MagicDNS resolving <Name-tag>.tail21a653.ts.net.
      # {
      #   job_name = "ec2-nodes";
      #   ec2_sd_configs = [{ region = "us-east-1"; port = 9100; }];
      #   relabel_configs = [
      #     { source_labels = [ "__meta_ec2_tag_Name" ]; target_label = "instance"; }
      #     { source_labels = [ "__meta_ec2_instance_id" ]; target_label = "instance_id"; }
      #     { source_labels = [ "__meta_ec2_instance_state" ]; regex = "running"; action = "keep"; }
      #     # Resolve over the tailnet by MagicDNS (EC2 SD only exposes AWS IPs).
      #     { source_labels = [ "__meta_ec2_tag_Name" ];
      #       replacement = "\${1}.tail21a653.ts.net:9100";
      #       target_label = "__address__"; }
      #   ];
      # }
      #
      # ts-sn-test11 is scraped statically (not via EC2 SD) per request.
      # {
      #   job_name = "tailnet-static";
      #   static_configs = [{
      #     targets = [ "ts-sn-test11.tail21a653.ts.net:9100" ];
      #   }];
      #   relabel_configs = [
      #     { source_labels = [ "__address__" ];
      #       regex = "([^.]+)\\..*";
      #       replacement = "\${1}";
      #       target_label = "instance"; }
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
