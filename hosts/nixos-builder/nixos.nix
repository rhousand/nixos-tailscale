{ config, pkgs, inputs, ... }:

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
      graylogServer = "graylogserver.tail21a653.ts.net:12203";
    };
  };
}
