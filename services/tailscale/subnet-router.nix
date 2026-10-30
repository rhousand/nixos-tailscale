{
  pkgs,
  config,
  gladstoneArgs,
  ...
}: {
  # Install and enable tailscaled.service. The useRoutingFetures set to server allow subnet routing and dns routing
  services.tailscale = {
    enable = true;
    package = pkgs.unstable.tailscale;
    useRoutingFeatures = "server";
    authKeyFile = config.age.secrets.tsKeyAge.path;
    # extraUpFlags only apply when tailscaled-autoconnect runs `tailscale up`,
    # i.e. at first login. On an already-authenticated node a restart skips
    # it, so anything set here silently drifts if someone runs
    # `tailscale up/set` by hand -- ts-sn-stage12 ended up with
    # AppConnector.Advertise=false that way, keeping stale app-connector
    # routes in its prefs. Tags stay here: `tailscale set` cannot change
    # them, and on existing nodes they are managed in the admin console.
    extraUpFlags = ["--advertise-tags=${gladstoneArgs.tsAdvertiseTags}"];
    # extraSetFlags run as `tailscale set` on every start, re-asserting state
    # that must hold on every subnet router.
    extraSetFlags = ["--ssh" "--advertise-connector"];
  };

  # create a oneshot job to authenticate to Tailscale
#  systemd.services.tailscale-autoconnect = {
#    description = "Automatic connection to Tailscale";
#
#    # make sure tailscale is running before trying to connect to tailscale
#    after = ["network-pre.target" "tailscale.service"];
#    wants = ["network-pre.target" "tailscale.service"];
#    wantedBy = ["multi-user.target"];
#
#    # set this service as a oneshot job
#    serviceConfig.Type = "oneshot";
#
#    # have the job run this shell script
#    script = with pkgs; ''
#      # wait for tailscaled to settle
#      sleep 2
#
#      # check if we are already authenticated to tailscale
#      status="$(${unstable.tailscale}/bin/tailscale status --json | ${jq}/bin/jq -r .BackendState)"
#      if [ $status = "Running" ]; then # if so, then do nothing
#        exit 0
#      fi
#
#      # otherwise authenticate with tailscale
#      ${unstable.tailscale}/bin/tailscale up --ssh --advertise-connector --advertise-tags=${gladstoneArgs.tsAdvertiseTags} --auth-key ${gladstoneArgs.tsAuthKey}
#
#    '';
#  };

  services = {
    networkd-dispatcher = {
      enable = true;
      rules."50-tailscale" = {
        onState = [ "routable" ];
        script = ''
          #!/bin/sh
          NETDEV=$(${pkgs.iproute2}/bin/ip -o route get 8.8.8.8 | ${pkgs.coreutils}/bin/cut -f 5 -d " ")
          ${pkgs.ethtool}/bin/ethtool -K "$NETDEV" rx-udp-gro-forwarding on rx-gro-list off
        '';
      };
    };
  };
  networking.hostName = gladstoneArgs.hostName;
  networking.firewall = {
    # enable the firewall
    enable = true;

    # always allow traffic from your Tailscale network
    trustedInterfaces = ["tailscale0"];

    # allow the Tailscale UDP port through the firewall
    allowedUDPPorts = [config.services.tailscale.port];

    # allow you to SSH in over the public internet
    allowedTCPPorts = [22];
  };
}
