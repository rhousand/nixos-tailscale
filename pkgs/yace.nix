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
  version = "0.61.3"; # check the latest release and pin it

  src = fetchFromGitHub {
    owner = "nerdswords";
    repo = "yet-another-cloudwatch-exporter";
    rev = "v${version}";
    hash = lib.fakeHash; # TODO: replace after first build
  };

  vendorHash = lib.fakeHash; # TODO: replace after second build

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
