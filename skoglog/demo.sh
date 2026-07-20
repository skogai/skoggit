#!/usr/bin/env bash
# End-to-end demo: append events, walk the list, fork with a shared tail.
set -euo pipefail
cd "$(dirname "$0")"

export SKOGLOG_DIR="${SKOGLOG_DIR:-/tmp/skoglog-demo.git}"
rm -rf "$SKOGLOG_DIR"

sk() { ./skoglog.sh "$@"; }

echo "== init =="
sk init

echo "== append three events onto stream 'main' =="
sk append main file_read   '{"path":"README.md"}'          >/dev/null
sk append main file_change '{"path":"README.md","workspace_commit":"abc123"}' >/dev/null
head=$(sk append main hook '{"name":"post-tool-use"}')
echo "main head: $head"

echo "== list main (root -> head) =="
sk list main

echo "== car main (head event) =="
sk car main

echo "== cdr main (tail commit) =="
sk cdr main

echo "== fork 'main' -> 'experiment' at head (O(1), shares the tail) =="
sk fork main experiment
sk append experiment file_read '{"path":"SPEC.md"}' >/dev/null

echo "== main is unchanged =="
sk list main

echo "== experiment: same 3 tail commits + 1 new head =="
sk list experiment
