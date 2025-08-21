let
  rhousand = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILEwR5cCd9w3xIcdVfOrISCnsdeIW1tPlPAv1bE/z/On";
  root-ts-sn = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHlqxg6xLWiuR4w+sZ0+6vPulQq0GBKExjZnTvnxkTcM";
  users = [rhousand root-ts-sn];

  rhlaptop = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEMuMvlwiXCgccwm+VTQlMSbL0vEvPtMrKpc022AKYf3";
  ts-sn-test11 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOWGAHke7NflnNCYXQKXe8wE9rDJrCV3BV7AWia2PqFZ";
  ts-sn-test12 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILGaoMvul1XuY+OWaGTYEAb6sXztxtja3lvQ7tfCF7qy";
  ts-sn-stage1 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPd9yN8U+r1+A+EeCJiYjAmWa2Dt3MnXJSyuToZwQNwK";
  systems = [rhlaptop ts-sn-test11 ts-sn-test12];
in {
  "ts-sn-test11-tskey.age".publicKeys = users ++ systems;
  "ts-sn-test12-tskey.age".publicKeys = users ++ systems;
  "ts-sn-stage11-tskey.age".publicKeys = users ++ systems;
  "ts-sn-stage1-tskey.age".publicKeys = users ++ systems;
}
