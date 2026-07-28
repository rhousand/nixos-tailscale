{ config, pkgs, ... }:

{
  # Telegraf → CloudWatch host metrics.
  services.telegraf = {
    enable = true;
    extraConfig = {
      agent = {
        interval = "60s";
        flush_interval = "60s";
        hostname = ""; # Use system hostname
      };

      # CloudWatch output
      outputs.cloudwatch = [{
        region = "us-east-1";
        namespace = "CWAgent";
      }];

      # Memory metrics
      inputs.mem = [{}];

      # Swap metrics
      inputs.swap = [{}];

      # Disk metrics
      inputs.disk = [{
        mount_points = ["/"];
      }];

      # CPU metrics
      inputs.cpu = [{
        percpu = false;
        totalcpu = true;
        collect_cpu_time = false;
        report_active = false;
      }];
    };
  };
}
