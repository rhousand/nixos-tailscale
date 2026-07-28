{ ... }: {
  # Reusable per-host exporter. Import on the monitor host (self-scrape) and,
  # later, on every client you want scraped.
  #
  # Reachable over the tailnet ONLY. Every host in this repo sets
  #   networking.firewall.trustedInterfaces = ["tailscale0"];
  # so :9100 is open on tailscale0 and blocked on the public interface (public
  # allows only 22 + the tailscale UDP port). openFirewall stays false so we
  # never punch 9100 public. The 0.0.0.0 bind is safe because the host firewall
  # gates the public side.
  services.prometheus.exporters.node = {
    enable = true;
    enabledCollectors = [ "systemd" ];
    port = 9100;
    listenAddress = "0.0.0.0";
    openFirewall = false;
  };
}
