# Repeat Edit — Implementation History & Roadmap

## Current Status (2026-05-12)

**Completed**: Phases 1–11 (initial transaction-driven design) +
Phases 12–18 (descriptor + registry refactor).  All 322 tests passing.
**Architecture**: Transaction-driven, fully data-described, with
pluggable selection-recreation and op-runner registries.

## Module Structure

```
helixel.el
├── helixel-edit.el     (kernel: tx schema + sel/op registries, no deps)
├── helixel-action.el   (action ring, `;' jumping; consumes tx)
├── helixel-repeat.el   (`.', count prefix, edit ring, picker, debug)
├── helixel-common.el   (state machine, edit cmds; registers ops + sel kinds)
├── helixel-search.el   (search/find-char, n/N repeat context)
├── helixel-textobj.el  (text objects; registers `textobj' sel kind)
└── helixel-surround.el (registers `surround' sel kind + ms/mt/md/mr ops)
```

Dependency chain (one-way, no cycles):
```
helixel-edit  →  helixel-action  →  helixel-repeat  →  helixel-common
   (kernel)       (ring + ;)        (. dispatch)       (commands + ops)
```

`helixel-repeat.el` no longer references any specific operator or
selection kind — dispatch is purely table-driven.

## Architecture Summary

```
selection cmd → helixel--repeat-sel-ctx  (a selection descriptor plist)
  ↓
edit cmd      → helixel--record-edit(op, &rest payload)
  ↓
helixel-edit-make → tx (:op :sel :payload :marker)
  ↓
helixel--last-tx = tx                 (dot-repeat head)
helixel--edit-ring = (tx ... )        (per-buffer history, deduped)
helixel--live-edit-set(tx)            (action ring — ; jumping)
  ↓
. (count) → helixel-repeat-edit
  → helixel-sel-recreate(:kind ctx)  ;; cl-defgeneric, per-kind methods
  → helixel-edit-op-runner(:op)      ;; op registry, registered per module
```

Extension points (zero kernel edits required):
- `helixel-edit-defop NAME :runner FN :display LABEL/FN`
- `cl-defmethod helixel-sel-recreate ((_kind (eql K)) ctx) ...)`
- `cl-defmethod helixel-sel-display  ((_kind (eql K)) ctx) ...)`

## Refactor Phases (2026-05-12)

| # | What | Files |
|---|------|-------|
| 12 | `cl-defgeneric helixel-sel-recreate`; line/rect/movement methods. | edit, repeat, common |
| 13 | Surround `:sel` becomes pure data `(:kind surround :delimiter D)`; fixes the latent `:fn helixel-surround-add` re-prompt bug. | surround |
| 14 | Textobj `:sel` becomes `(:kind textobj :command S :count N [:delimiter D])`; legacy `:fn` fallback removed. | textobj, edit, common |
| 15 | Op registry replaces 60-line pcase; runners self-register in owning modules; `helixel-repeat.el` shrinks 225→145 lines, all `declare-function` noise removed. | edit, repeat, common, surround |
| 16 | `.` accepts numeric prefix; replay wrapped in `condition-case` so failure does not discard `helixel--last-tx`. | repeat |
| 16b | **Bug fix**: `helixel-insert-exit` was discarding `plist-put` return on a possibly-nil payload, so `c<text><esc>.` replayed an empty change.  Added `helixel-edit-with-payload` immutable setter; end-to-end tests for change and insert. | edit, common |
| 17 | Pluggable display: `:display` may be a function; new `helixel-sel-display` cl-defgeneric; per-kind/per-op rich labels (e.g. `R[Q]`, `d.inner-word`, `c.Lx3`, `mr[)]`). | edit, repeat, common, textobj, surround |
| 17b | Edit ring (`helixel--edit-ring`, `helixel-edit-ring-max=64`, head dedup) + `helixel-repeat-edit-pick` completing-read picker. | repeat |
| 18 | Housekeeping: `helixel--inhibit-action-track` moves to its rightful home (`helixel-action.el`); commentary refreshed; `helixel-repeat-debug` for inspection; checkdoc clean. | action, common, repeat, edit, surround, textobj |
| 19 | **P0.1 ring-head sync**: `helixel-insert-exit` now syncs `helixel--edit-ring` head so `helixel-repeat-edit-pick` replays full payload.  Added 2 end-to-end pick tests. | common, test |
| 20 | **P0.2 undo amalgamation**: `.` replay wrapped in `undo-amalgamate-change-group` — all iterations are a single undo step.  Added undo test. | repeat, test |
| 21 | **P1.1 track-visual-move guarded during replay**: `helixel--track-visual-move` no-ops when `helixel--inhibit-repeat-record` is t.  Also fixed `helixel-define-command` to only inject `track-visual-move` for `:category movement` commands (edit commands like kill/change were polluting `helixel--repeat-sel-ctx` after their own `record-edit` consumed it). | common, test |
| 22 | **P1.2 rect-change replay**: `helixel--repeat-change-core` calls `helixel--rect-replay` directly instead of the full `helixel-insert-exit` (avoids unnecessary state switching during `.` replay).  Added state-invariance test. | common, test |
| 23 | **Lint**: Fixed all checkdoc warnings (22 across `helixel-action.el`, `helixel-common.el`), added missing docstrings, fixed column-width violations. All files: checkdoc + compile + package-lint clean, ≤80 cols. | action, common, repeat |

## Future Work

- **Edit register integration**: `"a.` / `"ay` to name and recall edits.
- **Persistence**: serialise `helixel--edit-ring` to `desktop` (now
  feasible since descriptors are pure data).
- **Yank-pop UX for `.`**: `M-.` after `.` rotates to the previous ring
  entry, undoing & re-applying à la `yank-pop`.
- **Change replay mode**: choose between `text` (current; insert stored
  string) and `keys` (re-execute key sequence so abbrev / yasnippet /
  electric indent fire again).
- **Cross-buffer repeat**: ring is currently buffer-local.

---

## Historical Phases (pre-refactor)


### Phase 1 — Remove dedup from action-start, add `;` group-skipping
- `helixel-action-start` now always pushes old action, always creates fresh marker
- `;` cycling uses `helixel-action--cycle-group-start` to skip consecutive
  same-group entries → equivalent UX, complete ring
- `helixel-action--same-content-p` now includes `:edit` comparison and marker position

### Phase 2 — Add `edit` category to action system
- `edit` added to cycle-categories, display format, same-content-p comparison
- `helixel--live-edit-set` atomic setter added

### Phase 3 — Selection context tracking
- `helixel--repeat-sel-ctx` set by all textobj macros/functions, line select,
  rect select — records `(:fn FUNCTION :kind KIND)`
- Pair/quote/tag/block functions now consistently set `helixel--selection-type = 'textobj`

### Phase 4 — Edit recording
- `helixel--last-edit`, `helixel--change-track-marker`, `helixel--inhibit-repeat-record` variables
- `helixel--record-edit(operator)` called at start of all 9 editing commands
- Change text extracted in `helixel-insert-exit` via change-track-marker
- `c` and `r` double-recording bugs found and fixed

### Phase 5 — Repeat edit execution
- `helixel-repeat-edit` bound to `.` in normal mode
- Recreates selection via stored sel-ctx, then replays operator
- `helixel--repeat-change-core` for change operations
- `helixel--delete-selection` extracted as shared kill core (no recording, no clear-data)

### Phase 6 — Tests
- 10 new ERT tests: no-prev error, paste, replace-char, indent, kill-textobj,
  kill-linewise, change-textobj, preserves-last-edit, clear-data, copy repeat

### Phase 7 — Insert-mode text repeat
- All insert-entry commands (`i`/`I`/`a`/`A`/`o`/`O`) now record `insert-text`
- Reuses `change-track-marker` pattern to capture typed text
- `.` inserts stored text at point
- 2 new tests: insert-text, empty insert-text

### Phase 8 — Charwise movement repeat
- `helixel--track-visual-move` accumulates movement commands during visual mode
  into `sel-ctx :moves` list `((CMD . COUNT) ...)`
- `.` replays movements with visual-state binding to extend selection
- Injected into `helixel-define-movement` and `helixel--with-movement-surround` macros
- 2 new tests: movement-kill, movement-change

### Phase 9 — Extract repeat to dedicated module
- New file `helixel-repeat.el` with all repeat infrastructure
- Variables moved: `helixel--repeat-sel-ctx`, `helixel--last-edit`,
  `helixel--change-track-marker`, `helixel--inhibit-repeat-record`
- Functions moved: `helixel--record-edit`, `helixel-repeat-edit`,
  `helixel--repeat-change-core`
- New unified dispatcher: `helixel--recreate-selection(sel-ctx)`
- `:type` → `:kind` normalization throughout
- `helixel--delete-selection` and `helixel--track-visual-move` stay in
  `helixel-common.el` (tight coupling with movement macros there)
- helixel-repeat uses `declare-function` for helixel-common editing commands
  (load-time safe, no circular dependency)

### Phase 10 — Transaction-driven refactoring (4 sub-phases)
- **Phase 10a**: New `helixel-edit.el` kernel module — unified tx schema
  `(:op :sel :payload :marker)`, builder (`helixel-edit-make`), equality,
  display. No helixel deps.
- **Phase 10b**: Convert repeat to store transaction. `helixel--last-edit`
  replaced by `helixel--last-tx`. `helixel--record-edit` builds tx via
  `helixel-edit-make`. Tests updated.
- **Phase 10c**: Unify action ring to store transaction. `helixel--live-edit-set`
  takes `(tx)` instead of `(operator sel-ctx &rest extra)`. Action ring `:edit`
  sub-plist is now a full tx. `helixel-action--same-content-p` delegates to
  `helixel-edit-equal-p`. `helixel-action-display` delegates to `helixel-edit-display`.
- **Phase 10d**: Extract execution dispatcher. `helixel--execute-edit(tx)`
  maps `:op` to execution functions. `helixel-repeat-edit` reduced to 5 lines:
  read tx → recreate selection → execute.

## Architecture Summary

```
selection cmd → helixel--repeat-sel-ctx
  ↓
edit cmd → helixel--record-edit(op, &rest payload)
  ↓
helixel-edit-make(op, sel-ctx, payload) → tx (:op :sel :payload :marker)
  ↓
helixel--last-tx = tx              (dot-repeat consumer)
helixel--live-edit-set(tx)         (action ring — ; jumping consumer)
  ↓
. → helixel-repeat-edit()
  → helixel--recreate-selection(edit-sel tx)
  → helixel--execute-edit(tx)      (unified dispatcher)
```

## Future Work

### Priority 1 — Count prefix support  ✓ DONE (Phase 11)
**Problem**: `3 x d` (select 3 lines, delete) didn't store count.
**Solution**: Added `:count` to `sel-ctx` plist. `helixel-select-line`,
`helixel-select-line-up`, and `helixel-select-rectangle` now:
- Accept `&optional count` (prefix arg)
- Accumulate count on consecutive calls (extending existing selection)
- Store `:count N` in `helixel--repeat-sel-ctx`
`helixel--recreate-selection` passes count to `:fn` during replay.
4 new tests added.

### Lower Priority
- **Undo repeat**: `.` after `u`/`U` — debatable value
- **Cross-buffer repeat**: last-tx is buffer-local
- `helixel-insert-after` records `insert-text`

---

## Phase 24 — Search-aware `.` repeat

**Date**: 2026-05-14
**Files**: `helixel-common.el`, `helixel-search.el`, `helixel-repeat.el`,
`helixel-edit.el`, `helixel-test.el`

- Unified search-edit design: `search` sel with `:entry-kind` and
  `:cursor-offset` replaces separate `insert-selection-*` kinds
- `.` after search + insert/append finds the NEXT match automatically
- Uses `isearch-search-string` for consistent isearch behavior
- `looking-at` guard skips current match for insert ops (chained `.`)
- Error handling: "Search pattern not found" when no more matches
- Removed `helixel-search-activate-mark` — mark always active after search
- Added 8 end-to-end tests for search + `.` scenarios

## Phase 25 — Movement selection `.` e2e tests + kmacro guards

**Date**: 2026-05-14
**Files**: `helixel-repeat.el`, `helixel-test.el`, `AGENTS.md`

- Added 3 end-to-end tests for movement + `.`:
  `vw d .` at start, `.` at different word start, `v w w d .`
- Added kmacro guards: `helixel--record-edit` inhibited during
  `executing-kbd-macro`; `helixel-repeat-edit` shows descriptive error
  during kmacro playback if no edit is stored
- Updated `AGENTS.md` with pitfalls #20 (stale .elc), #21 (kmacro),
  #22 (movement `.` design)
- 391 tests passing, lint clean

## Phase 26 — , comma repeat-selection audit + e2e tests

**Date**: 2026-05-14
**Files**: `helixel-test.el`, `AGENTS.md`

- Audited `,` flow for all 7 selection kinds: `helixel-repeat-selection`
  → `helixel--recreate-selection` → kind-specific recreate (search,
  movement, textobj, line, rect, surround, insert-*). All kinds set
  `helixel--repeat-has-preview` correctly so `.` uses the region.
- Added 3 end-to-end `,` tests: line kill preview, line count override,
  movement preview (vw d preview). Total 10 `,` tests pass.
- Design finding: `,` with count override works for line/rect/textobj
  but not for movement/search (count isn't meaningful for those).
- `:bounds` enrichment (from Phase 25 #22) would make `,` more
  predictable when buffer has changed — recorded bounds could be
  shown alongside the replayed selection.
