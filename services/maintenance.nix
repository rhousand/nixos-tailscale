{ config, pkgs, inputs,  ... }:

{
  # Offload builds to the x86_64 build server (harmonia binary cache + remote
  # builder over Tailscale). max-jobs = 0 forces all builds to the remote builder.
  system.activationScripts.createSshConfig = ''
                install -d -m 0700 /root/.ssh
                cat <<EOF > /root/.ssh/config
    Host nixos-builder-x84-64-linux.tail21a653.ts.net
      User builder
      HostName nixos-builder-x84-64-linux.tail21a653.ts.net
      Port 8022
      IdentitiesOnly yes
      StrictHostKeyChecking accept-new

    Host bitbucket.org
      User git
      IdentitiesOnly yes
      IdentityFile /root/.ssh/id_ed25519
      StrictHostKeyChecking accept-new
    EOF
                chmod 0600 /root/.ssh/config
  '';
  nix = {
    distributedBuilds = true;
    settings = {
      max-jobs = 0; # Disable local builds
      builders-use-substitutes = true; # Use substitutes from builders
      substituters = [ "https://nixos-builder-x84-64-linux.tail21a653.ts.net?priority=10" ];
      trusted-public-keys = [ "nixos-builder-x84-64-linux.tail21a653.ts.net:J2dvKtFWJsEUi1D5+1ELl2KciwfNkqlCbqY+gWpw/0k=" ];
      trusted-substituters = [
        "http://nixos-builder-x84-64-linux.tail21a653.ts.net"
      ];
    };
    buildMachines = [
      {
        hostName = "nixos-builder-x84-64-linux.tail21a653.ts.net";
        systems = [
          "x86_64-linux"
          "aarch64-linux"
        ];
        sshUser = "builder";
        maxJobs = 4;
        sshKey = "/root/.ssh/id_ed25519";
        supportedFeatures = [
          "nixos-test"
          "benchmark"
          "big-parallel"
        ];
      }
    ];
  };

  # Point at the remote git ref, not `inputs.self.outPath`.
  # `self.outPath` is a /nix/store path baked in at build time, which means:
  #   1. the upgrade rebuilds the same frozen snapshot forever, never picking
  #      up new commits, and
  #   2. `nix build --print-out-paths` on a store-path flake ref echoes the
  #      source path back instead of the realised output (NixOS/nix#13367),
  #      so nixos-rebuild aborts with "configuration path seems to be missing
  #      essential files".
  #
  # No query params: flake.nix is at the repo root and `main` is the default
  # branch, so neither `?dir=` nor `?ref=` is needed. That matters -- a second
  # query param would need an `&`, and auto-upgrade.nix builds the argument as
  # `"--flake ${cfg.flake}"` and then splices it into the generated shell
  # script unquoted via `toString cfg.flags`. Bash would background the first
  # half of the nixos-rebuild command and the unit dies with exit 127.
  #
  # The `#<attr>` fragment is pinned explicitly. Without it nixos-rebuild
  # resolves `nixosConfigurations.$(hostname)`, which is fragile; every host
  # that enables autoUpgrade must therefore have its flake attribute name
  # equal to its networking.hostName.
  #
  # Note there is no `--update-input`: it cannot write a lock file for a
  # remote flake, and nix 2.34 deprecates it. Hosts now deploy whatever
  # flake.lock is committed on main -- bump inputs with `nix flake update`
  # plus a PR, not on each host independently at 02:00.
  system.autoUpgrade = {
    enable = true;
    flake = "git+ssh://git@bitbucket.org/scain-td/nixos-flake-tailscale#${config.networking.hostName}";
    # No "--refresh" here: auto-upgrade.nix already prepends it whenever
    # `flake` is set, so listing it again just duplicates the argument.
    flags = [
      "--verbose"
      "-L" # print build logs
    ];
    dates = "02:00";
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
    dates = [ "05:00" ]; 
  };


}
