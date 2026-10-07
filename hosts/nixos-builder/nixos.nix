{ config, pkgs, inputs, ... }:
let
  # Split so the shipper's target and the readiness probe below cannot drift.
  graylogHost = "graylogserver.tail21a653.ts.net";
  graylogPort = 12203;
in
{
  # The builder does not import services/maintenance.nix, so it needs its own
  # root ssh client config to fetch the flake from Bitbucket. No builder Host
  # block here -- it *is* the builder, and it has no distributedBuilds /
  # buildMachines / max-jobs = 0 config, so it never offloads to itself.
  system.activationScripts.createSshConfig = ''
    install -d -m 0700 /root/.ssh
    install -m 0600 /dev/null /root/.ssh/config
    cat <<'EOF' > /root/.ssh/config
    Host bitbucket.org
      User git
      IdentitiesOnly yes
      IdentityFile /root/.ssh/id_ed25519
      StrictHostKeyChecking accept-new
    EOF
  '';

  # Builder runs its maintenance off-peak (noon / 2pm) so it is idle and available
  # during the other hosts' 02:00 autoUpgrade window when they build against it.
  # Remote git ref, not `inputs.self.outPath` -- see services/maintenance.nix
  # for the full rationale (frozen store snapshot + NixOS/nix#13367, and the
  # unquoted `&` splice that kills the unit with exit 127).
  system.autoUpgrade = {
    enable = true;
    flake = "git+ssh://git@bitbucket.org/scain-td/nixos-flake-tailscale#${config.networking.hostName}";
    # No "--refresh" here: auto-upgrade.nix already prepends it whenever
    # `flake` is set, so listing it again just duplicates the argument.
    flags = [
      "--verbose"
      "-L" # print build logs
    ];
    dates = "12:00";
    randomizedDelaySec = "45min";
  };

  # Flake-based system; the channel is unused and only produces
  # "nixos-system was not found in the Nix search path" noise on upgrade.
  nix.channel.enable = false;

  nix.gc = {
    automatic = true;
    dates = "00:01";
    options = "--delete-older-than 10d";
  };
  nix.optimise = {
    automatic = true;
    dates = [ "14:00" ];
  };

  services = {
    SystemdJournal2Gelf = {
      enable = true;
      graylogServer = "${graylogHost}:${toString graylogPort}";
    };
  };

  # SystemdJournal2Gelf resolves the Graylog host once, at startup, and panics
  # outright if the lookup fails:
  #
  #   panic: while connecting to Graylog server:
  #     dial udp: lookup graylogserver.tail21a653.ts.net: no such host
  #
  # Observed 2026-10-07. A switch that bumps the Tailscale package restarts
  # tailscaled, and the upstream unit is ordered only after network.target, so
  # it can be started in the same second tailscaled comes back -- before
  # tailscaled-autoconnect has run `tailscale up` and before MagicDNS answers.
  # It recovers on its own via Restart=on-failure, but switch-to-configuration
  # has already counted a failed unit and exits 4, so nixos-upgrade.service
  # reports failure and (since DAP-1286) NixosUpgradeFailed and
  # NixosUpgradeUnitFailed both fire -- for a 30-second journal-shipping gap.
  #
  # Ordering after tailscaled.service alone is NOT enough: that means the daemon
  # started, not that the node is authenticated with DNS working. Same lesson as
  # services/monitoring/grafana-sso.nix. Since what this service actually needs
  # is one name to resolve, probe for exactly that rather than for backend state.
  systemd.services.SystemdJournal2Gelf = {
    after = [ "tailscaled-autoconnect.service" ];
    wants = [ "tailscaled-autoconnect.service" ];
    serviceConfig.ExecStartPre = pkgs.writeShellScript "wait-for-graylog-dns" ''
      for _ in $(seq 1 30); do
        ${pkgs.getent}/bin/getent hosts ${graylogHost} >/dev/null 2>&1 && exit 0
        sleep 2
      done
      echo "${graylogHost} did not resolve within 60s" >&2
      exit 1
    '';
  };
}
