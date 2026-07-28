{
  pkgs,
  config,
  tryonArgs,
  inputs,
  ...
}: {
  imports = [
    inputs.agenix.nixosModules.default
  ];

  age = {
    identityPaths = [
      "/etc/ssh/ssh_host_ed25519_key"
    ];
    secrets = {
      tsKey = {
        file = ../../secrets/ts-buildserver.age;
        mode = "0400";
        owner = "root";
        group = "root";
      };
    };
  };

  services.tailscale = {
    enable = true;
    package = pkgs.tailscale;
    useRoutingFeatures = "none";
    extraSetFlags = [
      "--ssh"
    ];
    extraUpFlags = [
      "--ssh"
      "--advertise-tags=${tryonArgs.tsAdvertiseTags}"
    ];
    authKeyFile = config.age.secrets.tsKey.path;
    openFirewall = true;
  };

  # Let Caddy obtain a Tailscale TLS cert for the harmonia reverse proxy.
  systemd.services.tailscaled.serviceConfig.Environment = [
    "TS_PERMIT_CERT_UID=caddy"
  ];
}
