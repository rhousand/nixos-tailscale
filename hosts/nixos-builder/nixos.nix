{ config, pkgs, inputs, ... }:

{
  # Builder runs its maintenance off-peak (noon / 2pm) so it is idle and available
  # during the other hosts' 02:00 autoUpgrade window when they build against it.
  system.autoUpgrade = {
    enable = true;
    flake = inputs.self.outPath;
    flags = [
      "--refresh"
      "--verbose"
      "-L" # print build logs
    ];
    dates = "12:00";
    randomizedDelaySec = "45min";
  };

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
