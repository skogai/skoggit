# skoglog — git commits as a functional immutable linked list

MVP testing ground: use git's object model to keep append-only event state.
Distilled from the gitlord fork's plumbing core, stripped to the substrate.

## Premise

A git commit DAG **is** a persistent (immutable) linked list:

| linked list | git plumbing | meaning |
|-------------|--------------|---------|
| `cons(x, tail)` | `commit-tree <tree> -p <parent>` | append event `x` onto the list |
| `car(list)` | read `event.json` at head commit | the head event |
| `cdr(list)` | `rev-parse <sha>^` | the tail (previous commit) |
| `nil` | ref does not exist | the empty list |
| head pointer | `refs/skog/<stream>` | current list identity |
| `fork` | `update-ref refs/skog/<new> <sha>` | O(1) new head sharing the tail |

Delta-only: each commit's tree holds **just this one event** (`event.json`).
Full state = walk the parent chain. No tree accretion, no working tree, no
index — writes are pure plumbing, so N writers on N streams never contend.

- append: **O(1)**
- fork: **O(1)** (structural sharing — the tail is never copied)
- full walk: **O(N)**

## Schema

Everything git already tracks stays git's job. We add exactly one field: a
stable `id` (survives history rewrites; the commit sha does not).

`event.json` — the one blob in each commit's tree:

```json
{
  "id":   "20260720T141032-3f9a",
  "type": "file_read",
  "ts":   "2026-07-20T14:10:32Z",
  "payload": { "path": "README.md" }
}
```

- `id` — stable unique id, time-sortable. MVP: `<UTC-timestamp>-<rand>`.
  Production intent: ULID.
- `type` — event type (`file_read`, `file_change`, `hook`, `tool_call`, ...).
  Freeform string; not an enum at this stage.
- `ts` — event time (git also records committer date; this is the event's own).
- `payload` — arbitrary event data. Carries its own content (see decision #2).

Commit message header is `"<type> <id>"` so `git log --format='%H %s'` reads the
whole stream's metadata without opening a single blob.

Ref namespace: `refs/skog/<stream>`. A stream is one list; forks are new streams.

## Decisions on record

1. **Schema = git-native + one id.** Git does the linking/time/addressing; we add `id`.
2. **Event carries its own payload** (reverted the log/workspace byte split). *Why the split was proposed:* to avoid storing bytes twice once a separate workspace-repo-of-record exists. No such repo at MVP stage, so premature. Revisit later.
3. **No reader-contract / consequence trailers** — parked.
4. **No read-time pruning / assembly** — parked.
5. **Delta-only, immutable linked list** — commit = cons cell; fork = shared tail.

## Operations

| command | git plumbing | list op |
|---------|--------------|---------|
| `init` | `git init --bare` | create store |
| `append <stream> <type> <json>` | hash-object → mktree → commit-tree → update-ref (CAS) | cons |
| `head <stream>` | `rev-parse refs/skog/<stream>` | list identity |
| `car <stream>` | `show <sha>:event.json` | head event |
| `cdr <stream>` | `rev-parse <sha>^` | tail |
| `list <stream>` | `log --reverse --format='%H %s'` | walk root→head |
| `fork <src> <new>` | `update-ref refs/skog/<new> <sha>` | O(1) shared-tail fork |

`append` uses compare-and-swap (`update-ref <ref> <new> <old>`): the write only
lands if the head is still where we read it, so concurrent appenders are safe.
An empty `<old>` means "create only if absent" (cons onto `nil`).

## Try it

```bash
skoglog/demo.sh        # end-to-end: append, list, car, fork with shared tail
```

Implementation: `skoglog/skoglog.sh` (~60 lines of pure git plumbing).
