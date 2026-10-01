{ inputs, config, pkgs, ... }: {
  imports = [ inputs.harmonia.nixosModules.harmonia ];

  services.harmonia-dev = {
    cache = {
      enable = true;
      # Signing key generated with:
      #   nix-store --generate-binary-cache-key nixos-builder-x84-64-linux.tail21a653.ts.net \
      #     /var/lib/secrets/harmonia.secret /var/lib/secrets/harmonia.pub
      # Public key (/var/lib/secrets/harmonia.pub) is trusted by the subnet-router
      # clients in services/maintenance.nix.
      signKeyPaths = [ "/var/lib/secrets/harmonia.secret" ];
      settings = {
        bind = "127.0.0.1:5000"; # Listen locally only
        enable_compression = true;
        priority = 30;
      };
    };
    daemon.enable = true;
  };

  services.caddy = {
    enable = true;

    # Caddy collects per-server HTTP metrics only when this is enabled. Verified
    # on 2.11.4: without it the admin endpoint answers /metrics with HTTP 200 but
    # emits zero caddy_http_* series, so the cache panels would sit empty with no
    # obvious cause.
    #
    # Top-level `metrics`, not the nested `servers { metrics }`. 2.11.4 accepts
    # both but logs on every reload:
    #   "The nested 'metrics' option inside `servers` is deprecated and will be
    #    removed in the next major version. Use the global 'metrics' option
    #    instead."
    # Left on the nested form, a future Caddy major would silently stop
    # collecting and the cache panels would go blank for no visible reason.
    globalConfig = ''
      metrics
    '';

    virtualHosts."nixos-builder-x84-64-linux.tail21a653.ts.net".extraConfig = ''
      reverse_proxy 127.0.0.1:5000
    '';

    # Metrics on a dedicated port, scraped by ts-mon1 (job "builder-cache" in
    # services/monitoring/prometheus-grafana.nix). This is how we see whether
    # clients are pulling NARs from the cache or rebuilding them.
    #
    # Do NOT point the scrape at Caddy's admin endpoint (127.0.0.1:2019)
    # instead: that same listener serves /load and /config, which rewrite the
    # running server configuration with no authentication. It stays on
    # loopback. This site block serves only the metrics handler.
    virtualHosts.":9180".extraConfig = ''
      metrics /metrics
    '';
  };

  # Tailnet only. The builder's public firewall still allows just 22 and the
  # Tailscale UDP port, and this module does not set trustedInterfaces, so the
  # opening has to be explicit. Needs a Tailscale ACL permitting
  # tag:monitoring -> tag:x86-builder on tcp:9180.
  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 9180 ];
}
