{
  pkgs,
  config,
  gladstoneArgs,
  ...
}: {
  # Plain tailnet node for the monitor host: no subnet routing, no connector.
  # Auth key comes from agenix (persistent server), same as the subnet routers.
  services.tailscale = {
    enable = true;
    package = pkgs.unstable.tailscale;
    useRoutingFeatures = "none";
    authKeyFile = config.age.secrets.tsKeyAge.path;
    extraUpFlags = ["--ssh" "--advertise-tags=${gladstoneArgs.tsAdvertiseTags}"];
  };

  networking.hostName = gladstoneArgs.hostName;
  networking.firewall = {
    enable = true;
    trustedInterfaces = ["tailscale0"];
    allowedUDPPorts = [config.services.tailscale.port];
    allowedTCPPorts = [22];
  };
}
