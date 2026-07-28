let
  rhousand = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILEwR5cCd9w3xIcdVfOrISCnsdeIW1tPlPAv1bE/z/On";
  root-ts-sn = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHlqxg6xLWiuR4w+sZ0+6vPulQq0GBKExjZnTvnxkTcM";
  users = [rhousand root-ts-sn];

  rhlaptop = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEMuMvlwiXCgccwm+VTQlMSbL0vEvPtMrKpc022AKYf3";
  ts-sn-test11 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOWGAHke7NflnNCYXQKXe8wE9rDJrCV3BV7AWia2PqFZ";
  ts-sn-test12 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILGaoMvul1XuY+OWaGTYEAb6sXztxtja3lvQ7tfCF7qy";
  ts-sn-stage1 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPd9yN8U+r1+A+EeCJiYjAmWa2Dt3MnXJSyuToZwQNwK";
  ts-sn-stage11 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICgGGmuU+CzdM1J1mo5Ic34GpxvHYn49MV6I9OIMR2pP";
  systems = [rhlaptop ts-sn-test11 ts-sn-test12 ts-sn-stage1 ts-sn-stage11 ];

  # Build server (nixos-builder-x84-64-linux) recipient set for ts-buildserver.age.
  # Kept distinct so the tskey secrets above are not rekeyed. host-buildserver is
  # the builder's SSH host key (decrypts at runtime).
  root-buildserver = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICf4tBiDpwvK1ZIR/+ny+VTg90aEnkoFUQo/BFvxs1aQ";
  joe = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINjxGNI3O5tBMSuYQteJLbtm8IxguAlXPBjwnELH4JMO";
  host-buildserver = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICPSSb7lk/gg1U+TtU6XsADbMPue8xMrIEySaZp7z6s9";
  joelaptop = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL/bYGbi5MZNcgX05OKvfGuC2nqrTziDaLMacJfNCu91";
  buildserverUsers = [rhousand root-buildserver joe];
  buildserverSystems = [rhlaptop host-buildserver joelaptop];
in {
  "ts-sn-test11-tskey.age".publicKeys = users ++ systems;
  "ts-sn-test12-tskey.age".publicKeys = users ++ systems;
  "ts-sn-stage11-tskey.age".publicKeys = users ++ systems;
  "ts-sn-stage1-tskey.age".publicKeys = users ++ systems;
  "ts-buildserver.age".publicKeys = buildserverUsers ++ buildserverSystems;
}
