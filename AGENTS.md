# AGENTS.md — helixel-mode Project Guide

> For AI coding agents working on this project.
> **When you make a mistake, add it to the Pitfalls section below
> and instruct future runs to update AGENTS.md to avoid repeating it.**

## Project Overview

**helixel-mode** is a Helix-style modal editing Emacs package. It provides
Vim/Helix-like modal editing with dot-repeat (`.`), session jumping (`;`),
and a pluggable operator/selection architecture.

## File Map

| File | Responsibility |
|------|---------------|
| `helixel.el` | Entry point, requires all sub-modules |
| `helixel-edit.el` | **Kernel**: edit tx schema (`helixel-edit` struct), `helixel-sel` struct, op registry. NO helixel deps. |
| `helixel-action.el` | Action ring, `;` jumping, group-skipping. Requires helixel-edit. |
| `helixel-repeat.el` | Dot-repeat (`.`): record edits, recreate selections, execute. Requires helixel-action + edit. |
| `helixel-common.el` | State machine, keymaps, movement/editing commands, shared kill core. |
| `helixel-search.el` | Search/find-char engine + `n`/`N` repeat context. |
| `helixel-textobj.el` | Text objects (word, WORD, pair, quote, tag, etc.) |
| `helixel-delimiter.el` | Unified delimiter protocol for surround/textobj. |
| `helixel-surround.el` | Surround operations: add, delete, replace. |
| `helixel-test.el` | ERT test suite (~366 tests). |

## Dependency Graph (one-way, no cycles)

```
helixel-edit.el          kernel
   ↓
helixel-action.el        ring + ;
   ↓
helixel-repeat.el        . dispatch
   ↓
helixel-common.el        state + editing commands
   ↓
helixel-search.el        search/find-char
```

## Key Data Structures

### Edit Transaction (plist — primary format in Phase 6)

```elisp
(:op       symbol          ;; kill|change|copy|replace|replace-char|paste-after|...
 :sel      helixel-sel|plist|nil  ;; selection descriptor
 :payload  plist           ;; operator-specific data
 :marker   marker          ;; start position
 :runner   function        ;; (TX) -> nil, stored at record time (Phase 6)
 :display  string|function ;; label for history (Phase 6)
)
```

### helixel-sel struct (Phase 5)

```elisp
(cl-defstruct helixel-sel
  kind        ;; symbol: see CTX schema table below
  ctx         ;; plist of extra data (see kind-specific accessors)
  recreate    ;; function (ctx) that recreates the selection
  display)    ;; string or function (ctx) -> string

;; CTX schema — valid keys per kind:
;;
;;   line                    :dir (forward|backward)  :count (int ≥ 1)
;;   rect                    :count (int ≥ 1)
;;   movement                :moves ((CMD . COUNT) ...)
;;   textobj                 :command (symbol)   :count (int)   :delimiter (plist)
;;   search                  :pattern (string)   :dir (forward|backward)
;;   surround                :delimiter (plist)
;;   insert-selection-start  :cursor-offset (int|nil, set by insert-exit)
;;   insert-selection-end    :cursor-offset (int|nil, set by insert-exit)
;;   insert-beginning-line   (none)
;;   insert-end-line         (none)
;;   insert-search-offset    :offset (int)
```

## Key APIs

### Selection (helixel-edit.el)
```elisp
(helixel-sel-create kind ctx recreate &optional display)  → struct
(helixel-sel-get-kind sel)        → symbol (works on struct OR plist)
(helixel-sel-get-field sel key)   → value from ctx (use kind-specific accessors instead)
(helixel-sel-call-recreate sel)   → recreates selection
(helixel-sel-call-display sel)    → display string
(helixel-sel-equal-p a b)         → boolean
(helixel-sel-update-ctx sel k v)  → new sel with ctx updated
(helixel-sel-count sel)           → generic :count from ctx or 0
;; Kind-specific accessors (take sel struct or raw ctx plist):
;; ──────────────────────────────────────────────────────────
(helixel-sel-line-dir obj)          → :dir   (line); default `forward'
(helixel-sel-line-count obj)        → :count (line); default 1
(helixel-sel-rect-count obj)        → :count (rect); default 1
(helixel-sel-movement-moves obj)    → :moves (movement); list
(helixel-sel-textobj-command obj)   → :command (textobj)
(helixel-sel-textobj-count obj)     → :count   (textobj); default 1
(helixel-sel-textobj-delimiter obj) → :delimiter (textobj)
(helixel-sel-search-pattern obj)    → :pattern (search)
(helixel-sel-search-dir obj)        → :dir     (search); default `forward'
(helixel-sel-surround-delimiter obj)→ :delimiter (surround)
(helixel-sel-insert-offset obj)     → :offset       (insert-search-offset)
(helixel-sel-insert-cursor-offset obj) → :cursor-offset (insert-* kinds)
```

### Edit Transaction (helixel-edit.el)
```elisp
(helixel-edit-make op sel &rest kv)  → `helixel-edit' struct
(helixel-edit-op tx)                 → struct slot :op
(helixel-edit-sel tx)                → struct slot :sel
(helixel-edit-payload tx)            → struct slot :payload (plist)
(helixel-edit-runner tx)             → struct slot :runner
(helixel-edit-display-field tx)      → struct slot :display-field
(helixel-edit-equal-p a b)           → boolean (ignores :marker)
(helixel-edit-display tx)            → "d.textobj", "c", etc.
(helixel-edit-with-payload tx k v)   → new struct with updated payload
```

### Repeat (helixel-repeat.el)
```elisp
(helixel--record-edit operator &rest extra)  → stores tx + ring + action
(helixel--recreate-selection sel-ctx)        → runs recreate closure
(helixel--execute-edit tx)                   → calls stored :runner
(helixel-repeat-edit &optional count)        → bound to `.`
```

## Refactor Phases Status

| Phase | Status | Description |
|-------|--------|-------------|
| 1-3 | ✅ Done | before/after-change-functions recording, remove old code |
| 4 | ✅ Done | helixel-edit cl-struct (immutable edit transaction) |
| 5 | ✅ Done | helixel-sel cl-struct with kind-specific ctx accessors |
| 6 | ✅ Done | Op runner stored in struct slot |
| 7 | ✅ Done | Full test migration to struct API (helixel-edit-make) |
| 8 | ✅ Done | Remove cl-defmethod fallbacks, op registry → symbol properties |

## Build & Test Commands

```bash
make test          # Run all ERT tests
make lint          # checkdoc + compile + package-lint + column-check + ctx-lint
make compile       # Byte-compile all .el files
make ctx-lint      # Check raw plist-get on ctx keys (also part of make lint)
```

## Pitfalls — Lessons Learned

### 1. Parentheses balancing in test edits
**Problem**: When inserting test code between existing ERT tests, paren mismatches
cause "End of file during parsing" errors that are hard to debug.
**Fix**: After any edit to helixel-test.el, verify with:
```bash
emacs --batch -Q -L . -l helixel-test.el
```
Or use awk to count net parens: `awk '{...}' helixel-test.el` (net should be 0).
Or rewrite new function from scratch based on old code

### 6. Column width limit is 80 chars
**Problem**: `make lint` checks for lines exceeding 80 columns. Long docstrings
and backtick-quoted symbols are common culprits.
**Fix**: Break long lines, use `concat` for long error messages.

### 7. `checkdoc` requires Lisp symbols in backticks
**Problem**: Checkdoc warns when Lisp symbols in docstrings are not in backticks.
E.g., `after-change-functions` → `` `after-change-functions' ``.

### 8. `package-lint` requires closing parens not on their own lines
**Problem**: `)` on a line by itself triggers package-lint warning.
This is a pre-existing issue in helixel-common.el:277.

### 9. Test isolation: `helixel--last-tx` is buffer-local by default
**Problem**: Tests that set `helixel--last-tx` in one buffer and expect to read
it in another will fail. The variable is buffer-local.
**Fix**: Use `let` bindings or explicitly set the variable in the target buffer.

### 13. `sed -i 'N,Md'` depends on exact file state
**Problem**: Using sed to delete line ranges requires knowing the EXACT
current line numbers. Earlier edits shift line numbers, making the sed
command delete wrong lines, leaving dangling method bodies that cause
"Invalid read syntax" errors.
**Fix**: Always use `git checkout` to restore the file to a known state
before applying sed. Or use Python scripts that search for patterns
instead of hardcoding line numbers.

### 14. Missing closing `"` in docstrings causes "End of file during parsing"
**Problem**: When editing docstrings, if the closing double-quote is
accidentally removed, Emacs reports "End of file during parsing" because
it treats the rest of the file as a string literal.  The paren counter
(`awk`) shows net 0, which is misleading.
**Fix**: Always verify docstring edits don't drop the closing `"`.
Use `emacs --batch -Q -l file.el` to test each file after editing.

### 19. Never use match-data in `helixel-insert`/`helixel-insert-after` body
**Problem**: After search, `helixel-search--done-hook` calls
`helixel--live-search-set` and `helixel-action-commit` which can invalidate
`match-data`.  Using `(match-end 0)` in the insert command body can return
nil, causing `(goto-char nil)` → jump to buffer start (position 1).
**Fix**: Use `(region-end)` and `(region-beginning)` instead.  The region
is set up reliably by `helixel-search--handle-done` via `set-marker` on
the mark, and markers don't become stale when match-data is invalidated.
**Also**: Don't carry over `(unless (helixel--end-of-line-p) (forward-char))`
from the no-context fallback path into the search path — that forward-char
is only for the Helix-style `a` behavior when there's no selection.

---

### 20. Stale .elc files silently hide changes
**Problem**: When `.el` source files are edited but corresponding `.elc`
files are not recompiled, Emacs loads the stale compiled version.
Tests that pass with the `.el` source (which `load` reads directly when
no `.elc` exists) fail when the `.elc` is loaded instead.
**Fix**: Always `rm -f *.elc && make compile` after editing source files
before running tests.  The `make lint` and `make test` targets should
always be preceded by a fresh compile.

### 21. Kmacro recording and play-back interacts with repeat state
**Problem**: During keyboard macro playback (`executing-kbd-macro` non-nil),
`helixel--last-tx` may be nil or point to a different context than when the
macro was recorded.  Pressing `.` during playback could fail with
"No previous edit to repeat" or replay the wrong edit.
**Fix**: `helixel--record-edit` is inhibited during kmacro execution
(checks `executing-kbd-macro`).  `helixel-repeat-edit` still works during
kmacro playback but shows a descriptive error if no edit is stored.
This prevents kmacro from overwriting `helixel--last-tx` and keeps
`. ` functional when a valid edit exists.

### 22. Movement-selection `.` replays moves, not positions
**Problem**: Movement selections (`v w` in visual mode) record the sequence
of movement commands (`:moves ((helixel-forward-word-start . 1))`).
During `.` replay, the same movements are replayed from the cursor position.
This is the correct behavior (contextual replay), but it means `.` at a
different position may select different amounts of text than the original.
**Design**: This is intentional and matches Helix/Vim behavior. The
`:bounds` enrichment (future) would allow `,` (repeat-selection) to show
the original selection bounds when the text hasn't changed.

### 23. Cursor movement between insertions lost → segment-based replay
**Problem**: During insert mode after a search (`/hello<RET>iaa<M-f>bb`),
all inserted text was concatenated into one string ("aabb") with a single
cursor-offset.  Cursor movements (like `<M-f>`) between insertions were
invisible, causing `.` to insert all text at one position → "aabbhello"
instead of the correct "aahellobb".
**Fix**: `helixel--on-after-change` now records `(beg . text)` pairs
instead of bare strings.  `helixel--insert-finish` computes gap-based
segments `((gap . text) ...)` where gap is the distance from the previous
insertion's end.  The `insert-text` runner replays each segment at
`match-beginning + cumulative-gap`, correctly reproducing the original
cursor movements.  Falls back to legacy text insert when no search sel
or no active region.
**Affected scenario**: Any search + insert with cursor movement between
insertions (e.g., `i aa <M-f> bb <esc> .`).

---

### 24. Kmacro records ESC on some Emacs versions → strip trailing ESC
**Problem**: `start-kbd-macro` / `end-kbd-macro` may include the terminating
ESC key in `last-kbd-macro` on some Emacs builds.  Replaying `[?f ?o ?o ?\e]`
via `self-insert-command` triggers `keyboard-quit` or other ESC-bound
commands, breaking dot-repeat.
**Fix**: In `helixel--insert-finish`, after `end-kbd-macro`, check if the
last key is `?\e` (27) and strip it with `(substring raw 0 -1)`.
Also check for empty vector.

### 25. self-insert-command deletes active region during key replay
**Problem**: During `.` replay, the selection recreation (e.g.
`helixel--recreate-search`) activates a region via `push-mark`.
When `helixel--execute-keys` replays character keys via
`self-insert-command`, Emacs' `delete-selection-mode` deletes the
active region before inserting, destroying the search match.
**Fix**: Call `(deactivate-mark)` before `helixel--execute-keys` in
the `insert-text` runner.  Character keys are now inserted via
`insert-char` directly, avoiding `self-insert-command` entirely.

### 26. `start-kbd-macro` / `end-kbd-macro` display messages
**Problem**: The C primitives `start-kbd-macro` and `end-kbd-macro`
display "Defining kbd macro..." and "Keyboard macro defined" in the
echo area, which is visible to the user during insert mode.
**Fix**: Bind `inhibit-message` to t around both calls.

### 27. `:repeat-advance` tag system for operator auto-advance
**Design**: Each operator declares its `.` auto-advance behavior via
`:repeat-advance` in `helixel-edit-defop`.  Values: `nil` (no advance),
`'line` (forward-line when sel is line kind), function (custom).
Read by `helixel-edit-op-advance` and executed by
`helixel--repeat-do-advance` in Branch H of `helixel-repeat-edit`.

### 28. Kmacro-only insert replay (no change-hook recording)
**Design**: Insert-mode recording now uses ONLY `start-kbd-macro` /
`end-kbd-macro`.  The captured key sequence is stored in `:keys` payload.
Replay uses `helixel--execute-keys` (primary) or `:text` (fallback).
Removed: `before-change-functions`/`after-change-functions` hooks,
`helixel--insert-recorder`, `helixel--insert-recorder-bol`,
segment-based replay (`helixel--insert-segments`), and the
`helixel-repeat-change-method` defcustom.

**Recording**: `helixel--insert-begin` starts kmacro (no hooks).
`helixel--insert-finish` stops kmacro, returns the key vector.
`helixel-insert-exit` computes `:text` from `helixel--change-track-marker`
to `(point)` as fallback, stores `:keys` as primary replay mechanism.

**Replay**: `insert-text` runner checks `:keys` first (deactivate-mark
+ `helixel--execute-keys`), falls back to `:text` via `insert`.
`helixel--repeat-change-core` follows the same pattern.

**Third-party support**: Any command that triggers insert mode will
have its keystrokes captured by kmacro and replayed by `.`.  The
`:repeat-advance` tag on the operator handles auto-advance.

**Cursor-offset**: No longer computed at record time.  For tests that
need cursor positioning within a match, set `:cursor-offset` in the
sel ctx manually.  In real usage, kmacro keys encode cursor movement.

---

*Last updated: Command-based replay via pre-command-hook recording.*

### 31. Command-based replay replaces key-based for insert-mode keys
**Design**: During insert-mode recording, `pre-command-hook` captures
`this-command` for each keypress.  `helixel--insert-finish` returns
`(KEYS . COMMANDS)`.  During `.` replay, `helixel--execute-keys`
receives both keys and commands:
- If COMMANDS are available → call each command directly (keymap-independent).
  `self-insert-command' is handled via `insert-char' with the key.
- If no commands (tests, old txs) → fall back to `insert-char' for
  characters, `execute-kbd-macro' for non-characters.
This solves the normal-vs-insert mode keymap mismatch: commands like
`backward-char' and `forward-word' work correctly regardless of which
mode `.` is pressed in.
