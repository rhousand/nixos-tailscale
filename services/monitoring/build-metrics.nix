{ config, pkgs, lib, ... }:
let
  textfileDir = import ./textfile-dir.nix;
  stampFile = "/run/nixos-upgrade-start";

  markStart = pkgs.writeShellScript "nixos-upgrade-mark-start" ''
    ${pkgs.coreutils}/bin/date +%s > ${stampFile}
  '';

  # systemd hands ExecStopPost $SERVICE_RESULT, $EXIT_CODE and $EXIT_STATUS.
  # ExecStopPost runs on EVERY termination path -- clean exit, non-zero exit,
  # timeout, OOM kill -- so a build that dies still produces a metric. A wrapper
  # script only reports when it survives.
  #
  # Every file is written to a temp name and renamed: the textfile collector
  # reads unlocked, and a half-written .prom makes node_exporter report
  # node_textfile_scrape_error 1 instead of the metrics.
  writeResult = pkgs.writeShellScript "nixos-upgrade-write-metrics" ''
    set -u
    # Do not depend on tmpfiles having run: activation does create this, but a
    # missing directory here would fail the hook and (see the "-" prefixes
    # below) is not worth any risk to the upgrade path.
    ${pkgs.coreutils}/bin/install -d -m 0755 ${textfileDir}
    now=$(${pkgs.coreutils}/bin/date +%s)
    start=$(${pkgs.coreutils}/bin/cat ${stampFile} 2>/dev/null || echo "$now")
    duration=$(( now - start ))

    if [ "''${SERVICE_RESULT:-success}" = "success" ]; then
      exit_code=0
    else
      exit_code=''${EXIT_STATUS:-1}
    fi

    out=${textfileDir}/nixos_upgrade.prom
    tmp=$out.$$

    {
      echo '# HELP nixos_upgrade_last_run_timestamp_seconds Unix time the last nixos-upgrade run finished.'
      echo '# TYPE nixos_upgrade_last_run_timestamp_seconds gauge'
      echo "nixos_upgrade_last_run_timestamp_seconds $now"
      echo '# HELP nixos_upgrade_duration_seconds Wall-clock seconds of the last nixos-upgrade run.'
      echo '# TYPE nixos_upgrade_duration_seconds gauge'
      echo "nixos_upgrade_duration_seconds $duration"
      echo '# HELP nixos_upgrade_last_exit_code Exit code of the last nixos-upgrade run (0 = success).'
      echo '# TYPE nixos_upgrade_last_exit_code gauge'
      echo "nixos_upgrade_last_exit_code $exit_code"
    } > "$tmp"

    if [ "$exit_code" -eq 0 ]; then
      echo '# HELP nixos_upgrade_last_success_timestamp_seconds Unix time of the last successful nixos-upgrade run.' >> "$tmp"
      echo '# TYPE nixos_upgrade_last_success_timestamp_seconds gauge' >> "$tmp"
      echo "nixos_upgrade_last_success_timestamp_seconds $now" >> "$tmp"
    else
      # Carry the previous success timestamp across a failed run so the "hours
      # since last good build" panel keeps counting instead of going blank.
      ${pkgs.gnugrep}/bin/grep '^nixos_upgrade_last_success_timestamp_seconds' "$out" >> "$tmp" 2>/dev/null || true
    fi

    ${pkgs.coreutils}/bin/chmod 0644 "$tmp"
    ${pkgs.coreutils}/bin/mv -f "$tmp" "$out"
  '';

  # A unit exit code only says the run finished, not that the system moved.
  # The build server sat frozen on a July generation for two months while
  # nixos-upgrade reported success in 1.7s per run; only generation age catches
  # that. See documentation/nixos-build-metrics-plan.md section 1.
  writeGeneration = pkgs.writeShellScript "nixos-generation-write-metrics" ''
    set -u
    ${pkgs.coreutils}/bin/install -d -m 0755 ${textfileDir}
    profile=/nix/var/nix/profiles/system

    # The symlink's OWN mtime is when this generation was activated. Do NOT add
    # -L: that follows through to the store path, whose mtime Nix normalises to
    # 1, so the metric would read 1970-01-01 and NixosGenerationStale would fire
    # on every host forever.
    built=$(${pkgs.coreutils}/bin/stat -c %Y "$profile")
    gen=$(${pkgs.coreutils}/bin/readlink "$profile" | ${pkgs.gnused}/bin/sed 's/.*-\([0-9]*\)-link/\1/')

    out=${textfileDir}/nixos_generation.prom
    tmp=$out.$$

    {
      echo '# HELP nixos_generation_number Current NixOS system generation number.'
      echo '# TYPE nixos_generation_number gauge'
      echo "nixos_generation_number $gen"
      echo '# HELP nixos_generation_build_timestamp_seconds Unix time the current generation was activated.'
      echo '# TYPE nixos_generation_build_timestamp_seconds gauge'
      echo "nixos_generation_build_timestamp_seconds $built"
    } > "$tmp"

    ${pkgs.coreutils}/bin/chmod 0644 "$tmp"
    ${pkgs.coreutils}/bin/mv -f "$tmp" "$out"
  '';

  # node_uname_info only shows the RUNNING kernel. nixos-upgrade switches
  # nightly without rebooting, so after a kernel bump the booted kernel and the
  # one the default generation will boot diverge silently until a reboot. See
  # documentation/kernel-version-tracking-plan.md.
  #
  # Compares kernel STORE PATHS, not version strings, so a same-version rebuild
  # with different patches or config also counts as pending. Versions come from
  # the closure's kernel-modules/lib/modules/<version> directory, which avoids
  # parsing the kernel image.
  writeKernel = pkgs.writeShellScript "nixos-kernel-write-metrics" ''
    set -u
    ${pkgs.coreutils}/bin/install -d -m 0755 ${textfileDir}
    booted_sys=/run/booted-system
    default_sys=/nix/var/nix/profiles/system

    # Emit "unknown" rather than failing: a missing lookup must not stop the
    # rest of the file being written.
    kver() {
      for d in "$1"/kernel-modules/lib/modules/*; do
        if [ -d "$d" ]; then
          ${pkgs.coreutils}/bin/basename "$d"
          return
        fi
      done
      echo unknown
    }

    booted=$(kver "$booted_sys")
    default=$(kver "$default_sys")
    booted_path=$(${pkgs.coreutils}/bin/readlink -f "$booted_sys/kernel" 2>/dev/null || true)
    default_path=$(${pkgs.coreutils}/bin/readlink -f "$default_sys/kernel" 2>/dev/null || true)

    # Only flag a reboot when both paths resolved; an unreadable profile is a
    # gap, not evidence of a staged kernel.
    if [ -n "$booted_path" ] && [ -n "$default_path" ] && [ "$booted_path" != "$default_path" ]; then
      reboot_required=1
    else
      reboot_required=0
    fi

    out=${textfileDir}/nixos_kernel.prom
    tmp=$out.$$

    {
      echo '# HELP nixos_kernel_info Booted and default-generation kernel versions.'
      echo '# TYPE nixos_kernel_info gauge'
      echo "nixos_kernel_info{booted=\"$booted\",default=\"$default\"} 1"
      echo '# HELP nixos_kernel_reboot_required 1 if the default generation boots a different kernel than the running one.'
      echo '# TYPE nixos_kernel_reboot_required gauge'
      echo "nixos_kernel_reboot_required $reboot_required"
    } > "$tmp"

    ${pkgs.coreutils}/bin/chmod 0644 "$tmp"
    ${pkgs.coreutils}/bin/mv -f "$tmp" "$out"
  '';
in {
  # Deliberately does NOT import node-exporter.nix: flake.nix already imports
  # that per host in call form, and the module system dedupes by path only -- a
  # second, call-form copy would redefine exporters.node.enable and fail to
  # merge. Import both side by side instead. The textfile directory and its
  # tmpfiles rule come from node-exporter.nix.

  # Outcome + duration. Guarded so the module is safe to import on a host with
  # no autoUpgrade -- there is no nixos-upgrade.service to hook there.
  systemd.services.nixos-upgrade = lib.mkIf config.system.autoUpgrade.enable {
    serviceConfig = {
      # The "-" prefix makes systemd ignore a non-zero exit from these hooks.
      # Without it, any failure while writing metrics marks nixos-upgrade.service
      # failed even when the rebuild itself succeeded -- so the instrumentation
      # would manufacture the exact NixosUpgradeFailed / NixosUpgradeUnitFailed
      # alert it exists to report, on every host that imports this module.
      # Observability must never be able to break the thing it observes.
      ExecStartPre = [ "-${markStart}" ];
      # writeKernel here too, so a kernel staged by the nightly switch shows up
      # immediately rather than up to an hour later on the next timer tick.
      ExecStopPost = [ "-${writeResult}" "-${writeKernel}" ];
    };
  };

  # Generation age, on a timer rather than tied to an upgrade run: a host that
  # stops upgrading altogether must still report a growing age. The kernel
  # metrics ride the same timer; OnBootSec clears the reboot flag ~2 min after
  # a reboot.
  systemd.services.nixos-generation-metrics = {
    description = "Export the current NixOS generation and kernel as Prometheus metrics";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = [ "${writeGeneration}" "${writeKernel}" ];
    };
  };

  systemd.timers.nixos-generation-metrics = {
    description = "Refresh NixOS generation metrics hourly";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "1h";
    };
  };
}
