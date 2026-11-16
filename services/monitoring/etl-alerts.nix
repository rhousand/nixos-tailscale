{ pkgs, ... }: {
  # Alert rules for ETL jobs (dbt + Python) run by MWAA on tryon-etl-python.
  # Series are written by bashlib/etl_metrics.sh in the tryon-etl-python repo into
  # that host's node_exporter textfile dir, so they arrive via the ec2-nodes job
  # with instance="tryon-etl-python" and a per-job etl_job label. No scrape job of
  # their own. See documentation/telemetry-plan.md.
  #
  # Its own ruleFiles entry, not services.prometheus.rules -- same reason as
  # build-alerts.nix. Routing to Slack is handled by alertmanager-slack.nix.
  services.prometheus.ruleFiles = [
    (pkgs.writeText "etl-rules.yml" ''
      groups:
        - name: EtlJobs
          rules:
            - alert: EtlJobFailed
              # The textfile keeps the last run's exit code until the next run, so
              # this stays firing (re-nagging every 4h) until a run succeeds.
              expr: etl_job_exit_code != 0
              for: 5m
              labels:
                severity: warning
              annotations:
                summary: 'ETL job {{ $labels.etl_job }} failed (exit {{ $value }})'
                description: 'Check the MWAA task log, and on tryon-etl-python: /mnt/tryon-etl-python/dbt-artifacts/{{ $labels.etl_job }}/logs'

            - alert: EtlJobStale
              # Threshold is per job: the 2nd argument to etl_metrics_init. Jobs
              # without one are not covered. A job that has never succeeded has no
              # last_success series, so it cannot fire here -- EtlJobFailed covers it.
              expr: |
                time() - etl_job_last_success_timestamp_seconds
                  > on (instance, etl_job) etl_job_expected_interval_seconds
              for: 30m
              labels:
                severity: warning
              annotations:
                summary: 'No successful {{ $labels.etl_job }} run within its expected interval'
                description: 'Last success {{ $value | humanizeDuration }} ago. Check the DAG is still scheduled and not paused in MWAA.'

            - alert: EtlJobHung
              # Started but not finished. 3h fits the longest job (dbt prod full
              # refresh, ~2h); scope by etl_job if shorter jobs need tighter limits.
              expr: |
                etl_job_last_start_timestamp_seconds > etl_job_last_run_timestamp_seconds
                and time() - etl_job_last_start_timestamp_seconds > 3 * 3600
              labels:
                severity: warning
              annotations:
                summary: '{{ $labels.etl_job }} has been running for over 3h'
                description: 'If the MWAA task already ended, the script was killed without running its EXIT trap (e.g. SIGKILL).'

            - alert: DbtTestsFailing
              expr: dbt_nodes_total{resource_type="test", status=~"fail|error"} > 0
              for: 5m
              labels:
                severity: warning
              annotations:
                summary: '{{ $value }} dbt tests {{ $labels.status }} in {{ $labels.etl_job }}'
                description: 'Failing tests: dbt_node_status{etl_job="{{ $labels.etl_job }}", resource_type="test", status=~"fail|error"}'

            - alert: EtlMetricsFileBroken
              # A malformed .prom drops that file's metrics while :9100 still looks
              # healthy, so every rule above would silently stop seeing the job.
              expr: node_textfile_scrape_error{instance="tryon-etl-python"} == 1
              for: 15m
              labels:
                severity: warning
              annotations:
                summary: 'Textfile metrics on tryon-etl-python failed to parse'
                description: 'Check: curl -s localhost:9100/metrics | grep textfile; then inspect /var/lib/node-exporter/textfile/*.prom'
    '')
  ];
}
