{ pkgs, ... }:
let
  # --- Node Exporter Full (grafana.com dashboard 1860) ------------------------
  # Pin the revision; "latest" is not reproducible. Bump rev + re-prefetch:
  #   nix-prefetch-url https://grafana.com/api/dashboards/1860/revisions/<n>/download
  nodeFullRev = 45;
  nodeFull = pkgs.fetchurl {
    url = "https://grafana.com/api/dashboards/1860/revisions/${toString nodeFullRev}/download";
    hash = "sha256-GExrdAnzBtp1Ul13cvcZRbEM6iOtFrXXjEaY6g6lGYY=";
  };

  # Revision 45 wires all 127 panel datasource refs to a template variable,
  # "uid": "[$]{ds_prometheus}", whose `current` ships EMPTY. A provisioned
  # dashboard never gets the import dialog that would populate it, so it loads
  # with no datasource selected and every panel renders nothing. Rewrite the
  # placeholder to the stable uid declared in prometheus-grafana.nix.
  #
  # Note for future bumps: older revisions of 1860 used an __inputs block with
  # an upper-case ${DS_PROMETHEUS} instead. Revision 45 has no __inputs at all,
  # so a sed written for the old spelling silently matches nothing -- hence the
  # guard below, which fails the build rather than shipping a blank dashboard.
  nodeFullFixed = pkgs.runCommand "node-exporter-full.json" { } ''
    before=$(${pkgs.gnugrep}/bin/grep -c 'ds_prometheus' ${nodeFull} || true)
    if [ "$before" -eq 0 ]; then
      echo "dashboard 1860 rev ${toString nodeFullRev}: no ds_prometheus placeholder found."
      echo "The datasource wiring changed upstream -- inspect the JSON and update this sed."
      exit 1
    fi
    ${pkgs.gnused}/bin/sed 's/[$]{ds_prometheus}/prometheus/g' ${nodeFull} > $out
    if ${pkgs.gnugrep}/bin/grep -q '[$]{ds_prometheus}' $out; then
      echo "placeholder survived the rewrite; dashboard would load with no datasource."
      exit 1
    fi
  '';
in {
  # The file provider watching /etc/grafana-dashboards is already declared in
  # cloudwatch-yace.nix, so these are just two more files in that directory.
  # Grafana picks them up without a restart.
  environment.etc."grafana-dashboards/node-exporter-full.json".source = nodeFullFixed;

  # Hand-rolled: there is no upstream dashboard for Nix build metrics, because
  # the nixos_upgrade_* / nixos_generation_* series are defined in this repo
  # (services/monitoring/build-metrics.nix). Panel-by-panel notes live in
  # documentation/nixos-build-metrics-plan.md section 7.2.
  environment.etc."grafana-dashboards/nixos-builds.json".source =
    ../../dashboards/nixos-builds.json;
}
