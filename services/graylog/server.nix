{
  pkgs,
  config,
  ...
}: {
  # Networking configuration (adjust as needed)
  networking.hostName = "graylog-server";
  networking.firewall.allowedTCPPorts = [9000 9200 27017];

  # MongoDB configuration
  services.mongodb = {
    enable = true;
    package = pkgs.legacyPackages.x86_64-linux.mongodb-6_0;
    bind_ip = "127.0.0.1";
    enableAuth = false; # Adjust for production
  };

  # OpenSearch configuration
  services.opensearch = {
    enable = true;
    package = pkgs.legacyPackages.x86_64-linux.opensearch;
    settings = {
      "cluster.name" = "graylog-cluster";
      "discovery.type" = "single-node";
      "action.auto_create_index" = false;
      "plugins.security.disabled" = true; # Disable security for simplicity; enable in production
      "network.host" = "127.0.0.1";
    };
    extraJavaOptions = [
      "-Xms512m"
      "-Xmx512m"
    ];
  };

  # Graylog configuration
  services.graylog = {
    enable = true;
    package = pkgs.legacyPackages.x86_64-linux.graylog-6_0;
    elasticsearchHosts = ["http://127.0.0.1:9200"];
    passwordSecret = "yPE4lpLpjdCxJ5V3q9st7nSw6zo9XYueL191VubFqdjRMK9Wtc4WGbDhJD1AvUPcBwZhMTxtmt9JurbT0fOwaqIdonmVWMAd"; # Replace with a secure random string
    rootPasswordSha2 = "c0b0109d9439de57fe3cf03abeccbc52f4c98170c732d3b69af5e6395ace574e"; # SHA-256 of your admin password
    extraConfig = ''
      http_bind_address = 0.0.0.0:9000
      http_external_uri = http://graylog.example.com:9000/
    '';
  };

  # Ensure Java is available for Graylog and OpenSearch
  environment.systemPackages = with nixpkgs.legacyPackages.x86_64-linux; [
    openjdk11
  ];
}
