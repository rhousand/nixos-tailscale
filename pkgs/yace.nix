{ lib, buildGoModule, fetchFromGitHub }:

# Yet Another CloudWatch Exporter (nerdswords/yet-another-cloudwatch-exporter).
# Not in nixpkgs, so we build it here with buildGoModule.
#
# FIRST BUILD — fill the two hashes:
#   1. Build once: src `hash` is lib.fakeHash -> copy the real hash from the error.
#   2. Build again: `vendorHash` is lib.fakeHash -> copy the real hash from the error.
# Then rebuild clean. Also confirm `subPackages`/mainProgram against the pinned tag.
buildGoModule rec {
  pname = "yet-another-cloudwatch-exporter";
  version = "0.67.0";

  src = fetchFromGitHub {
    # Repo transferred nerdswords -> prometheus-community. Pin the canonical org and
    # the immutable commit for v0.67.0 (tags can move, redirects can break). Hash is
    # unchanged: content verified identical across the transfer.
    owner = "prometheus-community";
    repo = "yet-another-cloudwatch-exporter";
    rev = "15fb369c3ffaa46d7e32ab3ce22578cd98444623"; # v${version}
    hash = "sha256-3VMNLkzzwJX4ZhLihppjyBZDD/W+z5xLsMkZLUYHOF0=";
  };

  vendorHash = "sha256-0wHvXiYQGYU89SSOEBxiSC0CLGwOfN2Dzn8WeEBLYFk=";

  subPackages = [ "cmd/yace" ]; # binary -> "yace"; verify path for the tag

  ldflags = [ "-s" "-w" "-X main.version=${version}" ];

  # pure Go, no CGO needed
  env.CGO_ENABLED = 0;

  meta = {
    description = "Prometheus exporter for AWS CloudWatch metrics";
    homepage = "https://github.com/nerdswords/yet-another-cloudwatch-exporter";
    license = lib.licenses.asl20;
    mainProgram = "yace";
  };
}
