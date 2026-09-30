# Shared constant, not a module: the directory node_exporter's textfile collector
# reads and that build-metrics.nix writes into. Imported by both so the path
# cannot drift between the reader and the writer.
#
#   textfileDir = import ./textfile-dir.nix;
"/var/lib/node-exporter/textfile"
