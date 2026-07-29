{ config, pkgs, lib, gladstoneArgs, ... }:
let
  # AWS-side metrics node_exporter can't see: t-class CPU credits + EBS burst.
  # period/length 300s keeps CloudWatch GetMetricData API cost low. Scope with
  # searchTags if you want only a subset of instances.
  yaceConfig = pkgs.writeText "yace-config.yml" ''
    apiVersion: v1alpha1
    sts-region: us-east-1
    discovery:
      jobs:
        - type: AWS/EC2
          regions: [us-east-1]
          period: 300
          length: 300
          metrics:
            - name: CPUCreditBalance
              statistics: [Average]
            - name: CPUCreditUsage
              statistics: [Average]
        - type: AWS/EBS
          regions: [us-east-1]
          period: 300
          length: 300
          metrics:
            - name: BurstBalance
              statistics: [Average]
  '';
in {
  # Build YACE from pkgs/yace.nix (not in nixpkgs). Merges with the other
  # overlays on this host.
  nixpkgs.overlays = [
    (final: prev: {
      # YACE v0.67 needs Go >= 1.25; 25.05's buildGoModule is on Go 1.24, so
      # build it with the unstable overlay's newer toolchain.
      yace = prev.callPackage ../../pkgs/yace.nix {
        buildGoModule = final.unstable.buildGoModule;
      };
    })
  ];

  # Local-only exporter. Credentials come from the instance IAM role via IMDS,
  # so the role needs cloudwatch:GetMetricData, cloudwatch:ListMetrics,
  # tag:GetResources (extend the ts-mon1 instance role).
  systemd.services.yace = {
    description = "Yet Another CloudWatch Exporter";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      DynamicUser = true;
      Environment = "AWS_REGION=us-east-1";
      ExecStart = "${pkgs.yace}/bin/yace --config.file=${yaceConfig} --listen-address=127.0.0.1:5000";
      Restart = "on-failure";
      RestartSec = 10;
    };
  };

  # Prometheus scrapes it over loopback (never on the tailnet). Merges with the
  # scrapeConfigs list in prometheus-grafana.nix.
  services.prometheus.scrapeConfigs = [{
    job_name = "cloudwatch";
    static_configs = [{ targets = [ "127.0.0.1:5000" ]; }];
  }];
}
