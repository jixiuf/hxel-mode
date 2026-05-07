# Repeat Edit — Implementation History & Roadmap

## Current Status (2026-05-07)

**Completed**: Phases 1–6, all 247 tests passing.

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
  rect select — records `(:fn this-command :type TYPE)`
- Pair/quote/tag/block functions now consistently set `helixel--selection-type = 'textobj`

### Phase 4 — Edit recording
- `helixel--last-edit`, `helixel--change-track-marker`, `helixel--inhibit-repeat-record` variables
- `helixel--record-edit(operator)` called at start of all 9 editing commands
- Change text extracted in `helixel-insert-exit` via change-track-marker
- `c` and `r` double-recording bugs found and fixed

### Phase 5 — Repeat edit execution
- `helixel-repeat-edit` bound to `.` in normal mode
- Recreates selection via stored sel-ctx function, then replays operator
- `helixel--repeat-change-core` for change operations
- `helixel--delete-selection` extracted as shared kill core (no recording, no clear-data)

### Phase 6 — Tests
- 10 new ERT tests: no-prev error, paste, replace-char, indent, kill-textobj,
  kill-linewise, change-textobj, preserves-last-edit, clear-data, copy repeat

## Architecture Summary

```
selection command → helixel--repeat-sel-ctx (:fn ... :type ...)
         │
         ▼
edit command → helixel--record-edit → helixel--last-edit (for .)
         │              │
         │              └→ action-start 'edit → ring (for ;)
         ▼
   . → helixel-repeat-edit() → read last-edit → funcall sel-ctx.fn → execute
```

Shared kill core:
```
helixel--delete-selection → delete region/char, push to kill-ring
  Used by: helixel-kill-thing-at-point (d)
           helixel-change-thing-at-point (c)
           helixel--repeat-change-core (.)
```

## Future Work

### Priority 1 — Charwise movement repeat
**Problem**: `v w d` then `.` can't repeat because the charwise selection
from movement has no `sel-ctx`.
**Approach**: Extend `sel-ctx` to support `:moves` list:
```elisp
;; Current: single function
(:fn helixel-mark-inner-word :type textobj)

;; Future: movement sequence
(:moves ((helixel-forward-word-start . 1) (helixel-forward-word-end . 1))
 :type movement)
```
Commands in visual mode would accumulate moves into a running list,
then `d`/`c`/`y` would store the list as part of `sel-ctx`.

### Priority 2 — Count prefix support
**Problem**: `3 x d` (select 3 lines, delete) doesn't store count.
**Approach**: Add `:count` to `sel-ctx` plist, read `current-prefix-arg` in
selection commands.

### Priority 3 — Insert-mode typing repeat
**Problem**: `ihello<ESC>` doesn't record as an edit — `.` repeats
whatever edit happened BEFORE entering insert mode.
**Approach**: Track inserted text during insert mode similar to
change tracking, or record key sequences.

### Lower Priority
- **Undo repeat**: `.` after `u`/`U` — debatable value
- **`C-u .`** edit history browsing — reuse action ring + `C-u n` pattern
- **Cross-buffer repeat**: last-edit is buffer-local
