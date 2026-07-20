#!/usr/bin/env bash
# skoglog — git commits as a functional immutable linked list of events.
#
# Each event is one commit (delta-only): the commit tree holds a single
# event.json. Parent commit = list tail (cdr). Ref = head pointer. Fork = an
# O(1) new head that shares the tail. All writes are pure plumbing: no working
# tree, no index, so concurrent writers on different streams never contend.
#
# Usage:  skoglog.sh <cmd> [args...]
#   init
#   append <stream> <type> [payload-json]   -> prints new head sha
#   head   <stream>
#   car    <stream|sha>                      -> head event.json
#   cdr    <stream|sha>                      -> tail commit sha ("" if nil)
#   list   <stream>                          -> "<sha> <type> <id>" root->head
#   fork   <src-stream|sha> <new-stream>     -> O(1) shared-tail fork
#
# Store location: $SKOGLOG_DIR (default .skoglog), a bare git repo.
set -euo pipefail

: "${SKOGLOG_DIR:=.skoglog}"
REF_PREFIX="refs/skog"

_git() { git --git-dir="$SKOGLOG_DIR" "$@"; }

# MVP id: time-sortable + random suffix. Production intent: ULID.
gen_id() { printf '%s-%04x' "$(date -u +%Y%m%dT%H%M%S)" "$RANDOM"; }

# stream name or raw sha -> commit sha
_resolve() {
  _git rev-parse --verify --quiet "$REF_PREFIX/$1" 2>/dev/null \
    || _git rev-parse --verify "$1"
}

cmd_init() {
  [ -d "$SKOGLOG_DIR" ] || git init --quiet --bare "$SKOGLOG_DIR"
}

cmd_append() {
  local stream="$1" type="$2" payload="${3:-}"
  [ -n "$payload" ] || payload='{}'   # JSON-empty default (kept out of ${..} to avoid brace clash)
  local ref="$REF_PREFIX/$stream"
  local id ts event blob tree parent commit
  id="$(gen_id)"
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  event="$(printf '{"id":"%s","type":"%s","ts":"%s","payload":%s}' \
    "$id" "$type" "$ts" "$payload")"
  blob="$(printf '%s' "$event" | _git hash-object -w --stdin)"
  tree="$(printf '100644 blob %s\tevent.json\n' "$blob" | _git mktree)"
  parent="$(_git rev-parse --verify --quiet "$ref" || true)"
  if [ -n "$parent" ]; then
    commit="$(_git commit-tree "$tree" -p "$parent" -m "$type $id")"
    _git update-ref "$ref" "$commit" "$parent"   # CAS: head must be unchanged
  else
    commit="$(_git commit-tree "$tree" -m "$type $id")"
    _git update-ref "$ref" "$commit" ""            # create: ref must not exist
  fi
  printf '%s\n' "$commit"
}

cmd_head() { _git rev-parse --verify "$REF_PREFIX/$1"; }

cmd_car() { printf '%s\n' "$(_git show "$(_resolve "$1"):event.json")"; }

cmd_cdr() { _git rev-parse --verify --quiet "$(_resolve "$1")^" || true; }

cmd_list() { _git log --reverse --format='%H %s' "$REF_PREFIX/$1"; }

cmd_fork() {
  local sha; sha="$(_resolve "$1")"
  _git update-ref "$REF_PREFIX/$2" "$sha" ""
  printf '%s\n' "$sha"
}

main() {
  local cmd="${1:-}"; shift || true
  case "$cmd" in
    init|append|head|car|cdr|list|fork) "cmd_$cmd" "$@";;
    *) echo "usage: skoglog.sh {init|append|head|car|cdr|list|fork} ..." >&2
       exit 1;;
  esac
}

main "$@"
