{ ... }: {
  # Reusable per-host exporter. Import on the monitor host (self-scrape) and
  # on every client you want scraped.
  #
  # Reachable over the tailnet ONLY. openFirewall stays false so we never punch
  # 9100 public; instead we open it explicitly on tailscale0 below. The 0.0.0.0
  # bind is safe because the host firewall gates the public side (public allows
  # only 22 + the tailscale UDP port).
  services.prometheus.exporters.node = {
    enable = true;
    enabledCollectors = [ "systemd" ];
    port = 9100;
    listenAddress = "0.0.0.0";
    openFirewall = false;
  };

  # Explicit tailnet-only opening. Self-contained so this module works on hosts
  # that do NOT set trustedInterfaces=["tailscale0"] (e.g. the build server).
  # On hosts that do trust tailscale0 this is redundant but harmless.
  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 9100 ];
}
