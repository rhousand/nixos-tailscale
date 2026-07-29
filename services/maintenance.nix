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

  system.autoUpgrade = {
    enable = true;
    flake = inputs.self.outPath;
    flags = [
      "--update-input"
      "nixpkgs"
      "--update-input"
      "nixos-unstable"
      "-L" # print build logs
    ];
    dates = "02:00";
    randomizedDelaySec = "45min";
  };

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
