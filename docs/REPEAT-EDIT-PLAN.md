# Repeat Edit — Implementation History & Roadmap

## Current Status (2026-05-07)

**Completed**: Phases 1–10, all 254 tests passing.
**Architecture**: Transaction-driven — single schema shared by repeat, action ring, and edit commands.

## Module Structure

```
helixel.el
├── helixel-edit.el     (kernel: tx schema — :op :sel :payload :marker)
├── helixel-action.el   (ring, ; group-skipping → stores tx in :edit)
├── helixel-repeat.el   (. infrastructure — last-tx, record-edit, execute-edit)
├── helixel-common.el   (state machine, editing commands, shared kill core)
├── helixel-search.el   (search/find-char, n/N repeat context)
└── helixel-textobj.el  (text objects, hooks-based decoupling)
```

Dependency chain (one-way, no cycles):
```
helixel-edit  →  helixel-action  →  helixel-repeat  →  helixel-common
   (kernel)       (ring + ;)        (. dispatch)       (commands)
```
helixel.el
  ├── helixel-action.el  (ring, ; group-skipping, edit category)
  ├── helixel-repeat.el  (NEW: . infrastructure — recording, sel-ctx, replay)
  ├── helixel-common.el  (state machine, editing commands, movements, keymaps)
  ├── helixel-search.el  (search/find-char, n/N repeat context)
  └── helixel-textobj.el (text objects, hooks-based decoupling)
```

## Completed Phases

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

### Priority 1 — Count prefix support
**Problem**: `3 x d` (select 3 lines, delete) doesn't store count.
**Approach**: Add `:count` to `sel-ctx` plist.

### Priority 2 — `C-u .` edit history browsing
**Approach**: Reuse action ring + `helixel-edit-display` for completing-read.

### Lower Priority
- **Undo repeat**: `.` after `u`/`U` — debatable value
- **Cross-buffer repeat**: last-tx is buffer-local
- `helixel-insert-after` records `insert-text`
