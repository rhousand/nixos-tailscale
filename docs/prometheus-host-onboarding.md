# Onboarding a host into Prometheus — checklist

How to add a NixOS host to ts-mon1's monitoring without paging yourself, and how
to verify it actually landed. Verified against the live stack 2026-10-02.

The order matters more than any single step: **make the host emit metrics before
you make it visible to Prometheus.** Reversing that is what generates the
onboarding noise.

---

## 0. Decide how it will be discovered

Three jobs can pick up a host. Pick one — being in two means duplicate series with
the same `instance` label, which is how `BuilderDown` originally misfired.

| Job | How a host joins | Requirements |
|---|---|---|
| `ec2-nodes` | automatic, via EC2 service discovery | instance tagged `monitoring=true`, state `running`, **and its EC2 `Name` tag must equal its Tailscale device name** — the relabel rewrites the scrape address to `<Name>.tail21a653.ts.net:9100` |
| `tailnet-static` | add the FQDN to the target list in `services/monitoring/prometheus-grafana.nix` | needs a ts-mon1 deploy to take effect |
| `monitor-self` | ts-mon1 only | n/a |

The `Name`-tag requirement is the quiet trap: EC2 SD only exposes AWS-internal
addresses, so the job rewrites the target to MagicDNS. A `Name` tag that does not
match the device name produces a target that can never resolve.

---

## 1. Pre-flight — before the host is visible

| ✓ | Check | How |
|---|---|---|
| | Host is in the tailnet under the expected name | `tailscale status \| grep <host>` |
| | ACL permits `tag:monitoring` → it on `tcp:9100` | without it the target is unreachable *and* MagicDNS will not resolve it from ts-mon1 — see §4 |
| | Flake config imports `node-exporter.nix` **and** `build-metrics.nix` | both, or the host shows up as a coverage gap |
| | `system.autoUpgrade.enable = true` and its `flake` is a **remote git ref**, not `inputs.self.outPath` | the latter rebuilds a frozen snapshot forever while reporting success |
| | EC2 `Name` tag equals the Tailscale device name | only if using `ec2-nodes` |
| | Host evaluates | `nix eval --raw '.#nixosConfigurations.<host>.config.system.build.toplevel.drvPath'` |

---

## 2. Deploy first, make visible second

```bash
# 1. deploy the host with monitoring already in its config
nixos-rebuild switch --flake '.#<host>'     # on the host, or via its own autoUpgrade

# 2. confirm it is emitting locally, before Prometheus is told about it
curl -s localhost:9100/metrics | grep -E 'nixos_generation|node_textfile_scrape_error'
```

`nixos_generation_*` appears within ~2 minutes of boot (`OnBootSec = "2min"` on the
timer) or immediately after a rebuild. `nixos_upgrade_*` does **not** appear until
the first `nixos-upgrade` run completes — that is expected and alerts nothing, see
§5.

Then make it visible: tag the instance `monitoring=true`, or add it to
`tailnet-static` and deploy ts-mon1.

---

## 3. If you must do it out of order, silence first

Tagging an instance before deploying its config is sometimes unavoidable. Pre-silence
the window — one silence on `instance=` covers both alerts that would fire:

```bash
# on ts-mon1
amtool silence add instance=<host> --duration=4h --comment='onboarding <host>, DAP-xxxx'
```

`comment_required` is set, so the comment is not optional. Expire it early once §4
passes:

```bash
amtool silence query
amtool silence expire <ID>
```

---

## 4. Verify

Two independent checks: does the host **emit**, and did Prometheus **ingest**.
Measure emission from ts-mon1, not from your laptop — Tailscale ACLs decide what
ts-mon1 can resolve and reach, and ts-mon1 is what has to scrape.

```bash
# on ts-mon1 — emission
curl -s http://<host>.tail21a653.ts.net:9100/metrics \
  | grep -E '^nixos_generation|^nixos_upgrade|^node_textfile_scrape_error'

# on ts-mon1 — ingestion
curl -s 'http://127.0.0.1:9090/api/v1/query?query=up' | grep <host>
curl -s -G http://127.0.0.1:9090/api/v1/query \
  --data-urlencode 'query=nixos_generation_number' | grep <host>
```

A healthy new host emits `nixos_generation_number` and
`nixos_generation_build_timestamp_seconds`, reports `node_textfile_scrape_error 0`,
and appears in `up` with value 1. `nixos_upgrade_*` being **absent** is correct
until its first upgrade run completes.

Interpreting a failure to fetch — the `curl` exit code tells you which problem you
have, and they have very different fixes:

| Result | Meaning |
|---|---|
| exit 6, host not in `tailscale status` | not in the tailnet at all |
| exit 6, host *is* in `tailscale status` | ts-mon1 cannot resolve it — MagicDNS only answers for ACL-visible peers, so the ACL is missing |
| exit 7 | reachable, nothing on 9100 — node_exporter not running |
| exit 28 | resolves but filtered — firewall not opened on `tailscale0` |
| fetches, but absent from `up` | no scrape job covers it: wrong `Name` tag, missing `monitoring=true`, or ts-mon1 not yet rebuilt |
| `node_textfile_scrape_error 1` | a malformed `.prom` — some metrics missing while the endpoint looks healthy |
| generation timestamp reads `1` | `stat -L` regression in `build-metrics.nix`; Nix normalises store mtimes to 1, which would make any staleness alert fire forever |

Check tailnet membership from a machine with a broader view than ts-mon1 — the
distinction between "does not exist" and "ACL-hidden" is invisible from ts-mon1,
since both produce an unresolvable name:

```bash
tailscale status | grep <host>
```

---

## 5. What alerts to expect, and when

With `DAP-1286` deployed, on a host added **in the right order**:

| Rule | Fires? | Why |
|---|---|---|
| `NixosUpgradeFailed` | no | `nixos_upgrade_last_exit_code` absent; absence never satisfies `!= 0` |
| `NixosUpgradeStale` | no | same — `time() - <absent>` yields nothing |
| `NixosGenerationStale` | no | the rebuild that installed the module also refreshed the generation, so age starts near 0 |
| `NixosUpgradeUnitFailed` | no | unit exists but is `inactive`, not `failed` |
| `NixosBuildMetricsMissing` | **after 2h** | only if scraped while still not emitting — i.e. the out-of-order case |
| builder / ts-mon1 rules | no | hardcoded to those instances |
| **`InstanceDown`** | **after 5m** | pre-existing rule, `up == 0` unscoped, **critical** — the most likely onboarding page |

So in the right order: nothing. Out of order: `InstanceDown` within 5 minutes and
`NixosBuildMetricsMissing` after two hours.

---

## 6. Hosts managed outside this repo

`tryon-etl-python` is the precedent: a NixOS host in this tailnet, scraped by
ts-mon1, but built from `scain-td/tryon-etl-python` (flake at `iac/flake`). It holds
**byte-identical copies** of `textfile-dir.nix`, `build-metrics.nix` and
`node-exporter.nix`.

For such a host, §1 and §2 still apply, but the config change happens in its repo,
and any change to those modules here must be copied there:

```bash
cp services/monitoring/{textfile-dir,build-metrics,node-exporter}.nix \
   ../<other-repo>/<path-to>/services/monitoring/
diff -r services/monitoring/ ../<other-repo>/<path-to>/services/monitoring/
```

Expect differences only for files that legitimately exist on one side
(`prometheus-grafana.nix`, `build-alerts.nix`, `build-dashboards.nix` are
ts-mon1-only).

Two git-hook traps in that particular repo, both pre-existing:

- `.git/hooks/post-checkout` sources a `git_hooks/hook_lib.sh` that does not exist,
  so with `set -euo pipefail` every branch checkout exits non-zero. Work around it
  with `git -c core.hooksPath=/dev/null checkout …`, which also avoids that hook's
  `nix flake update` side effect.
- `git_hooks/script_formatting.sh` fails closed when `betterleaks` is not on PATH,
  and reports the missing binary as `COMMIT REJECTED: secrets detected`. Put the
  tool on PATH rather than bypassing the scan.

Also check the host's upgrade cadence before trusting staleness thresholds:
`tryon-etl-python` went 36 days between generations 90 and 91, so
`NixosGenerationStale` at 14d would fire there during normal quiet periods.

---

## 7. Decommissioning — the reverse

Removing a host is where stale alerts come from, so do it in this order:

1. Remove it from discovery **first** — untag `monitoring=true`, or drop it from
   `tailnet-static` and deploy ts-mon1. Otherwise `InstanceDown` pages critical the
   moment you terminate the instance.
2. Terminate / shut down the host.
3. Remove its flake config block and its agenix secret, if it will not come back.
   `ts-sn-stage1` is the counter-example: decommissioned, config deliberately kept
   in `flake.nix` for now — which is safe *because* it has no monitoring imports and
   so cannot appear as a down target. Trust `tailscale status` over `flake.nix` when
   auditing which hosts actually exist.
4. Its series age out of the TSDB on the normal 90d retention. Dashboards will keep
   showing it in that window; that is history, not a fault.

---

## 8. Known gaps

- **A host whose first upgrade never succeeds is invisible to `NixosUpgradeStale`**,
  because there is no `last_success_timestamp` to compare against. It is caught by
  `NixosUpgradeFailed` instead (a failed run still writes `last_exit_code`), or by
  `NixosUpgradeUnitFailed`.
- **A host where the upgrade timer never fires at all** is caught by neither of
  those. Only `NixosGenerationStale` notices, and only after 14 days.
- **`InstanceDown` is fleet-wide and critical**, including for the two loopback
  exporter targets (`127.0.0.1:5000`, `127.0.0.1:9250`), which page with an
  instance label of `127.0.0.1:…`. See the appendix.

---

## Appendix — scoping `InstanceDown`

The rule in `services/monitoring/alertmanager-slack.nix` is:

```yaml
- alert: InstanceDown
  expr: up == 0
  for: 5m
  labels: { severity: critical }
  annotations:
    summary: "{{ $labels.instance }} is down"
```

`up` exists for **every** scrape target. Today that is nine, and they are not all
hosts:

```
up=1  job=cloudwatch      instance=127.0.0.1:5000
up=1  job=tailscale       instance=127.0.0.1:9250
up=1  job=builder-cache   instance=nixos-builder-x84-64-linux
up=1  job=tailnet-static  instance=nixos-builder-x84-64-linux
up=1  job=ec2-nodes       instance=tryon-etl-python
up=1  job=monitor-self    instance=ts-mon1
up=1  job=ec2-nodes       instance=ts-sn-stage11
up=1  job=tailnet-static  instance=ts-sn-test11
up=1  job=tailnet-static  instance=ts-sn-test12
```

So "scoping it" means making the rule match only the targets where *host down* is
the right interpretation. Three problems with the unscoped form:

1. **Loopback exporters page as hosts.** If the yace exporter dies, this fires
   `critical: 127.0.0.1:5000 is down`. The host is fine; one exporter stopped. The
   summary actively misleads whoever is woken up.
2. **Duplicate pages for the builder.** It has two targets. A blocked `:9180`
   produces `InstanceDown` (critical) *and* `BuilderCacheMetricsDown` (warning) for
   the same cause — and the critical one is the wrong reading, which is exactly the
   bug already fixed in `BuilderDown` by adding `job="tailnet-static"`.
3. **Every new host is a critical page for its first five minutes** if tagged before
   it is ready.

A scoped version — node_exporter targets only, where the instance label really is a
host:

```yaml
- alert: InstanceDown
  expr: up{job=~"tailnet-static|ec2-nodes|monitor-self"} == 0
  for: 5m
  labels: { severity: critical }
  annotations:
    summary: "{{ $labels.instance }} is down"
    description: "No node_exporter scrape for 5m."

# and a separate, lower-severity rule for the exporters, which are not hosts
- alert: ExporterDown
  expr: up{job=~"cloudwatch|tailscale|builder-cache|prometheus-self|integrations/.*"} == 0
  for: 15m
  labels: { severity: warning }
  annotations:
    summary: "Exporter {{ $labels.job }} on {{ $labels.instance }} is not scrapeable"
    description: "The host is likely fine; this exporter or its port is not. Panels fed by this job will be blank."
```

Trade-off worth stating plainly: the `job=~` allow-list means a **newly added job is
covered by neither rule** until someone edits it. The unscoped `up == 0` has the
opposite failure — it covers everything, including things it describes wrongly. Pick
based on which mistake you would rather make; the allow-list is a deliberate,
greppable list, which is the easier of the two to audit.

Not implemented. `InstanceDown` predates this work and is doing its job today — this
is a proposal, to be weighed against leaving a rule alone that has not actually
misfired yet.
