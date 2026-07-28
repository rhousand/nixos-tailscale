{ inputs, config, pkgs, ... }: {
  imports = [ inputs.harmonia.nixosModules.harmonia ];

  services.harmonia-dev = {
    cache = {
      enable = true;
      # Signing key generated with:
      #   nix-store --generate-binary-cache-key nixos-builder-x84-64-linux.tail21a653.ts.net \
      #     /var/lib/secrets/harmonia.secret /var/lib/secrets/harmonia.pub
      # Public key (/var/lib/secrets/harmonia.pub) is trusted by the subnet-router
      # clients in services/maintenance.nix.
      signKeyPaths = [ "/var/lib/secrets/harmonia.secret" ];
      settings = {
        bind = "127.0.0.1:5000"; # Listen locally only
        enable_compression = true;
        priority = 30;
      };
    };
    daemon.enable = true;
  };

  services.caddy = {
    enable = true;
    virtualHosts."nixos-builder-x84-64-linux.tail21a653.ts.net".extraConfig = ''
      reverse_proxy 127.0.0.1:5000
    '';
  };
}
