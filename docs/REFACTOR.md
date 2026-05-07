# helixel-mode Refactoring Session Log

> **Status**: Complete — Phase A done. All 202 tests passing.
> **Goal**: Replace independent state variables with a single `helixel--action` plist +
> `helixel--action-ring`, enabling future `.` repeat and cleaner direction/state management.

---

## 1. Data Structures

### `helixel--action` — live action plist (buffer-local)

```elisp
(defvar-local helixel--action nil
  "Current active action plist.
Keys: :category :subcat :marker :dir :char :type :pattern :display")
```

### `helixel--action-ring` — action history ring (buffer-local)

```elisp
(defvar-local helixel--action-ring nil
  "Ring of actions, most recent first. Each entry is a plist.
Shared by session jump (`;`), repeat (`n`/`N`), and history (`C-u n`).
Capped at `helixel-action-ring-max'.")
```

### `helixel--action-pos` — ring cycle position (buffer-local)

```elisp
(defvar-local helixel--action-pos nil
  "Ring position for `;' cycling: nil=live, 0=newest, 1=next, ...")
```

### Action Plist Key Reference

| Key | Category | Meaning |
|-----|----------|---------|
| `:category` | all | `movement` `search` `find-char` `textobj` `state` |
| `:subcat` | all | `char` `line` `word` `WORD` `goto` `scroll` `lineselect` `rectselect` `next` `till` `repeat` `pair` `quote` `tag` `symbol` `sentence` `paragraph` `insert` `exit` `toggle` |
| `:marker` | all | start position marker for `;` jump |
| `:dir` | movement/search/find-char | `forward` `backward` |
| `:pattern` | search | regexp string |
| `:type` | find-char | `next` `till` |
| `:char` | find-char | target character |
| `:display` | all | t = show in C-u n history completion |

### Display Formats

| Category | Fields | Format |
|----------|--------|--------|
| search forward | `:pattern "foo" :dir forward` | `/foo/` |
| search backward | `:pattern "foo" :dir backward` | `?foo?` |
| find-char next fwd | `:type next :char ?x :dir forward` | `f→x` |
| find-char next bwd | `:type next :char ?x :dir backward` | `F→x` |
| find-char till fwd | `:type till :char ?x :dir forward` | `t→x` |
| find-char till bwd | `:type till :char ?x :dir backward` | `T→x` |
| movement | `:subcat line` | `movement.line` |
| textobj | `:subcat word` | `textobj.word` |

---

## 2. Key Functions

### `helixel--dir()` → direction symbol
Returns current direction from `helixel--action :dir`, falling back to `'forward`.

### `helixel--set-dir(dir)`
Sets direction on `helixel--action :dir`. Creates `helixel--action` if nil.

### `helixel-action-start(category subcat &rest attrs)` → action plist
Start or continue an action. Logic:
1. If previous action has same `(category subcat)` → continue, preserve marker
2. If different → push old to ring (skipping meaningless actions: search without `:pattern`, find-char without `:type`)
3. Create new action plist
4. `:marker` in attrs overrides the auto-created marker

### `helixel--action-meaningful-p(action)` → boolean
Returns nil for search actions without `:pattern` or find-char without `:type`.

### `helixel-action-cycle(&optional arg)` — bound to `;`
Cycles through `helixel--action-ring`, setting mark at `:marker` (point stays).
- First press with live action: pushes live to ring (if meaningful), shows ring[0]
- Without arg: go to older action
- With arg (C-u): go to newer action
- Meaningless live actions are discarded, not pushed to ring

### `helixel-action-display(action)` → string
Formats action plist for display.

### `helixel-search--action-push()`
Pushes current `helixel--action` to ring with `:display t`. Deduplicates adjacent identical entries.

### `helixel-search--sync-action-direction(&optional entry)`
Syncs direction of front ring entry to match current direction.

### `helixel-search--find-char-core(&optional action)`
Execute find-char from action plist or ring. Stores `:type` and `:char` on `helixel--action` for repeat detection.

### `helixel-search--from-history(forwardp)`
Selects search/find-char from ring. Filters for valid entries (search with `:pattern`, find-char with `:type`). Sets `:category` to `find-char` when replaying find-char.

---

## 3. What Was Removed

### from helixel-common.el:
- `helixel--direction` → replaced by `helixel--dir()` / `helixel--set-dir()`
- `helixel--current-find` → migrated to `helixel--action :type` / `:char`
- `helixel--session-mark`, `helixel--session-type`, `helixel--session-ring`, `helixel--session-pos`
- `helixel-session-ring-max`
- `helixel--command-session-type`, `helixel--session-start`, `helixel-select-session`
- All `(put ... 'helixel-session ...)` calls

### from helixel-search.el:
- `helixel--current-find` (defvar-local)
- `helixel-search-history-max`, `helixel-search--history-ring`, `helixel-search--history-display`
- `helixel-search--command-directions`
- All `(put ... 'helixel-session ...)` calls
- `helixel-search--push-history` → `helixel-search--action-push`
- `helixel-search--sync-history-direction` → `helixel-search--sync-action-direction`

### from helixel-textobj.el:
- All `(put ... 'helixel-session ...)` calls
- `(helixel--session-start)` → `(helixel-action-start 'textobj subcat)`

---

## 4. Command → Action Mapping

| Command | Category | Subcat | Extra |
|---------|----------|--------|-------|
| helixel-backward-char | movement | char | :dir backward |
| helixel-forward-char | movement | char | :dir forward |
| helixel-next-line | movement | line | :dir forward |
| helixel-previous-line | movement | line | :dir backward |
| helixel-forward-word-start | movement | word | :dir forward |
| helixel-forward-word-end | movement | word | :dir forward |
| helixel-backward-word-start | movement | word | :dir backward |
| helixel-forward-WORD-start | movement | WORD | :dir forward |
| helixel-forward-WORD-end | movement | WORD | :dir forward |
| helixel-backward-WORD | movement | WORD | :dir backward |
| helixel-go-* / helixel-goto-line | movement | goto | — |
| helixel-scroll-* | movement | scroll | — |
| helixel-select-line | movement | lineselect | :dir forward |
| helixel-select-line-up | movement | lineselect | :dir backward |
| helixel-select-rectangle | movement | rectselect | — |
| helixel-insert | state | insert | — |
| helixel-insert-exit | state | exit | — |
| helixel-mode / helixel-mode-all | state | toggle | — |
| helixel-search-forward | search | search | :dir forward |
| helixel-search-backward | search | search | :dir backward |
| helixel-search-at-point-* | search | search | :dir forward/backward |
| helixel-find-next-char | find-char | next | :dir forward |
| helixel-find-prev-char | find-char | next | :dir backward |
| helixel-find-till-char | find-char | till | :dir forward |
| helixel-find-prev-till-char | find-char | till | :dir backward |
| helixel-find-repeat | find-char | repeat | — |
| helixel-search-repeat-next | — (delegates to find-repeat or isearch-repeat) | — | — |
| helixel-search-repeat-reverse | — (delegates to find-repeat or isearch-repeat) | — | — |
| helixel-mark-inner-word etc. | textobj | word | — |
| helixel-mark-inner-WORD etc. | textobj | WORD | — |
| helixel-mark-inner-symbol etc. | textobj | symbol | — |
| helixel-mark-inner-sentence etc. | textobj | sentence | — |
| helixel-mark-inner-paragraph etc. | textobj | paragraph | — |
| helixel-mark-inner-paren etc. | textobj | pair | — |
| helixel-mark-inner-*-quote etc. | textobj | quote | — |
| helixel-mark-inner-tag etc. | textobj | tag | — |

**Note:** `helixel-search-repeat-next`/`helixel-search-repeat-reverse` no longer create their own `search/repeat` wrapper actions. They delegate directly to `helixel-find-repeat` or `helixel-search--isearch-repeat`.

---

## 5. Repeat Detection Logic

`helixel-search-repeat-next`/`helixel-search-repeat-reverse` determine what to repeat by checking:

1. Live `helixel--action :category`:
   - `find-char` → repeat find-char
   - `search` with `:type` → repeat find-char (after C-u N from history)
   - `search` without `:type` → repeat search (isearch)
2. Ring scan (if live action is neither): find most recent `search` or `find-char` entry

This ensures `f x` → `j` → `n` correctly repeats find-char (finds it in ring),
and `f x` → `/hello` → `n` correctly repeats search (search is more recent in ring).

---

## 6. Direction Handling

- Direction stored in `helixel--action :dir` via `helixel--set-dir`
- `helixel--dir()` reads from action plist, falls back to `'forward`
- Directional commands pass `:dir` to `helixel-action-start`
- `N`/`C-u N` toggle direction via `helixel--set-dir`
- `helixel-search--sync-action-direction` syncs ring front entry's `:dir`

---

## 7. Key Design Decisions

### Marker preservation
- Continuing same `(category subcat)` preserves the original marker
- `helixel-find-repeat` fetches original marker from ring when live action is different
- `:marker` attrs override auto-created marker in `helixel-action-start`

### Meaningless action guarding
- `helixel--action-meaningful-p` rejects search without `:pattern` and find-char without `:type`
- Guard applied in `helixel-action-start` push and `helixel-action-cycle` first press
- `helixel-search--from-history` filters for valid entries at display time

### No search/repeat wrapper actions
- `helixel-search-repeat-next`/`helixel-search-repeat-reverse` do NOT create `search/repeat` actions
- They delegate directly to the actual operation (find-char or isearch)
- This prevents meaningless entries from polluting the ring

### Textobj subcategories
- Text objects use specific subcats: `word`, `WORD`, `symbol`, `sentence`, `paragraph`, `pair`, `quote`, `tag`
- Different textobj families create independent sessions for `;`

---

## 8. Test Status

**202/202 tests passing.** Added 5 new tests for bug fixes:

| Test | Covers |
|------|--------|
| `helixel-test-repeat-find-after-movement` | `f x` → `j` → `n` correctly repeats find-char |
| `helixel-test-repeat-search-over-find` | Ring has [search, find-char], `n` picks search |
| `helixel-test-repeat-no-search-repeat-wrap` | `n`/`N` do not create search/repeat wrapper actions |
| `helixel-test-action-cycle-skip-meaningless` | `;` skips meaningless live actions |
| `helixel-test-history-from-history-sets-find-char-category` | C-u N replay sets `:category` to `find-char` |

---

## 10. Word/WORD Dependency Flip & Movement Rewrite

**Goal**: Eliminate duplicate word-boundary definitions between text objects and
movement commands.

**Before**:
- `helixel-textobj.el` → `(require 'helixel-common)` — circular risk
- `helixel-common.el` movement functions: own regex-based word detection
- `helixel-textobj.el`: `helixel--forward-word`/`helixel--forward-WORD` via thing-at-point

**After**:
- `helixel-common.el` → `(require 'helixel-textobj)`
- `helixel-textobj.el`: no helixel deps, exposes hooks for integration
- Movement commands delegate to `helixel--forward-beginning`/`helixel--forward-end`

### Decoupling via Hooks

```elisp
;; helixel-textobj.el — hook variables (default nil)
(defvar helixel-textobj-action-function nil)
(defvar helixel-textobj-visual-state-p-function nil)

;; helixel-common.el — injected after helixel-action-start definition
(setq helixel-textobj-action-function #'helixel-action-start)
(setq helixel-textobj-visual-state-p-function
      (lambda () (eq helixel--current-state 'visual)))
```

### New Helpers (in helixel-textobj.el)

```elisp
(helixel--forward-beginning THING &optional COUNT)  ; w / b
(helixel--forward-end       THING &optional COUNT)  ; e
```

### Movement Functions Rewritten

| Key | Old (regex) | New (thing-at-point) |
|-----|-------------|---------------------|
| `w` | `re-search-forward "[[:alnum:]]+[ ]*\\|..."` | `(helixel--forward-beginning 'helixel-word)` |
| `b` | `re-search-backward "\\([[:alnum:]]+[ ]*\\)\\|..."` | `(helixel--forward-beginning 'helixel-word -1)` |
| `e` | `re-search-forward "\\([[:alnum:]]+\\)\\|..."` | `(helixel--forward-end 'helixel-word)` |
| `W` | `re-search-forward "[ \t]+\\S-"` | `(helixel--forward-beginning 'helixel-WORD)` |
| `B` | `re-search-backward "[ \t]+\\S-"` | `(helixel--forward-beginning 'helixel-WORD -1)` |
| `E` | `re-search-forward "\\S-+\\(\\s-\\|..."` | `(helixel--forward-end 'helixel-WORD)` |

### Keymap Wiring Moved

`helixel-textobj-map` parenting moved from `helixel-textobj.el` bottom to
`helixel-common.el` (after `(require 'helixel-textobj)`).

---

## 11. Phase B — Action System Extraction + Repeat Refactor

> **Date**: 2026-05-05
> **Goal**: Fix state mutation bugs (ring aliasing + direction corruption),
> extract action system to `helixel-action.el`, separate repeat context
> from action direction, make repeat categories configurable.

### 11.1. New File: `helixel-action.el`

Extracted from `helixel-common.el` (plus `action-commit` from search):

- Variables: `helixel--action`, `helixel--action-ring`, `helixel--action-pos`,
  `helixel-action-ring-max`, `helixel--action-required-keys`
- Functions: `helixel-action-start`, `helixel-action-display`,
  `helixel-action-cycle`, `helixel--action-valid-p`,
  `helixel--jump-to-marker`, `helixel--cancel-action`,
  `helixel-action-commit` (renamed from `helixel-search--action-push`)
- Helpers: `helixel-action--same-content-p`, `helixel-action--ring-cap`

**Removed**: `helixel--dir()` / `helixel--set-dir()` — repeat direction
belongs in search, not the action system.  `helixel--action :dir` is
now a historical record set at creation and never mutated after commit.

Key invariants:
1. **Copy-on-push**: every ring push deep-copies.
2. **`:dir` immutability**: `:dir` on actions set at creation, never mutated.
3. **No repeat coupling**: action system has zero knowledge of repeat.

### 11.2. Repeat Context (`helixel-search.el`)

New buffer-local variables separate from action system:

```elisp
helixel--repeat-dir   ;; 'forward | 'backward — where n goes next
helixel--repeat-data  ;; plist: :category, :pattern or :type/:char
```

API: `helixel-repeat-dir`, `helixel-repeat-set-dir`, `helixel-repeat-flip-dir`,
`helixel-repeat-set`, `helixel-repeat-category`.

Set by `/`, `?`, `*`, `#`, `f`, `F`, `t`, `T` and `C-u n/N`.
Read by `n`/`N`.  Flipped by `N`.
**Never mutates `helixel--action :dir`** — this is the key design change
that eliminates the direction-corruption bugs.

### 11.3. Sync Cleanup

`helixel-search--sync-action-direction` replaced by
`helixel-search--sync-ring-front-dir(dir)` — pure function, takes
explicit DIR parameter, only touches ring front (independent copy),
never mutates live action.

### 11.4. `from-history` Uses `action-start`

Previously, `from-history` directly `plist-put`'d on `helixel--action`,
creating incomplete actions (missing `:subcat`, `:marker`).  Now it uses
`helixel-action-start` which creates a proper action plist with all
required keys and handles session transitions correctly.

### 11.5. Dead Code Removed

- `helixel-search--detect-repeat-cat` — replaced by `helixel-repeat-category`
- `search`+`:type` → `find-char` check — confirmed unreachable

### 11.6. Bugs Fixed

| Bug | Fix |
|-----|-----|
| `set-dir` corrupts ring front (object aliasing) | Copy-on-push in all commit sites |
| `set-dir` corrupts ring entry `:dir` (N toggles direction) | Direction lives in `helixel--repeat-dir`, never in committed action's `:dir` |
| `from-history` search path doesn't update live action | Uses `action-start` (full plist with `:category`, `:subcat`, `:marker`) |
| `C-u n`/`N` `forwardp` depends on current direction | Always pass `t` for `C-u n`, `nil` for `C-u N` |
| Bare `(:dir ...)` entries in ring | `set-dir` removed; only `action-start` creates actions |
| `sync-action-direction` corrupts live action | Replaced by pure `sync-ring-front-dir(dir)` |

### 11.7. Session Continuity Fix

`helixel-find-repeat` previously used `'repeat` as subcat, creating
`(find-char repeat)` which differed from the original `(find-char next/till)`.
This caused `action-start` to push the old action to ring on every n press.
Fixed by using the original variant (`next` or `till`) from
`helixel--repeat-data :type`.  Same principle as `w w w` all sharing
`(movement word)`.

---

## 12. Phase C — Nested Data Structure + Atomic Setters

> **Date**: 2026-05-06
> **Goal**: Make the action data model self-documenting and prevent
> category-field misuse at the API level.

### 12.1. Nested Action Structure

Category-specific fields moved from flat plist keys into sub-plists
keyed by category keyword:

**Before** (flat, no field ownership):
```elisp
(:category search :subcat search :marker <M> :dir forward :pattern "foo" :display t)
(:category find-char :subcat next :marker <M> :dir forward :type next :char ?x)
```

**After** (nested, self-documenting):
```elisp
(:category search :subcat search :marker <M> :display t
 :search    (:pattern "foo" :dir forward))

(:category find-char :subcat next :marker <M>
 :find-char (:type next :char ?x :dir forward))

(:category movement :subcat line :marker <M>
 :movement (:dir forward))
```

### 12.2. Atomic Data Setters

Generic `helixel--cat-put(key value)` removed.  Replaced by
category-specific setters whose signatures enforce completeness:

```elisp
(helixel--live-search-set pattern dir)          ;; 2 required args
(helixel--live-find-char-set type char dir)     ;; 3 required args
(helixel--live-cat-set-dir dir)                 ;; shared :dir setter (cross-category)
```

Design: no way to pass wrong fields or incomplete data:
```elisp
(helixel--cat-put :type 'next)          ;; IMPOSSIBLE — doesn't exist
(helixel--live-search-set "foo")        ;; IMPOSSIBLE — arity error
(helixel--live-find-char-set 'next ?x)  ;; IMPOSSIBLE — arity error
```

The function signatures ARE the contract.

### 12.3. Category Accessors

```elisp
(helixel--live-cat-get :type)                  ;; read from live action's sub-plist
(helixel--action-cat-get ring-entry :dir)       ;; read from any action's sub-plist
```

Sub-plist key derived automatically from `:category` (e.g. `'search` → `:search` keyword).

### 12.4. `action-start` Simplified

No longer accepts sub-plist data.  Creates only the skeleton
(`:category`, `:subcat`, `:marker`).  Callers use atomic setters after:

```elisp
;; Before:
(helixel-action-start 'search 'search :search '(:dir forward))
;; After:
(helixel-action-start 'search 'search)
(helixel--live-cat-set-dir 'forward)
```

### 12.5. Unified Ring Push

All ring mutations go through `helixel-action--ring-push(action)`:
- Deep-copies before pushing
- Deduplicates via content comparison (compares sub-plists)
- Caps ring to `helixel-action-ring-max`
- Called by `action-commit`, `action-start`, `action-cycle`, `cancel-action`

No caller does its own `push` + `copy-tree` + dedup.

---

## 13. Phase D — Live/Ring API Distinction (2026-05-06)

### 13.1. Rename: `live-` prefix for live-action operations

All functions operating on the implicit `helixel--action` now have a `live-`
prefix.  Functions taking an explicit action plist parameter use `action-`.

| Old | New | Reason |
|-----|-----|--------|
| `helixel--cat-get` | `helixel--live-cat-get` | No "live" identifier |
| `helixel--cat-set-dir` | `helixel--live-cat-set-dir` | Implicit live target hidden |
| `helixel--search-set` | `helixel--live-search-set` | Consistency with live prefix |
| `helixel--find-char-set` | `helixel--live-find-char-set` | Consistency with live prefix |

### 13.2. Unified Naming Convention

```
Live action (implicit helixel--action):
  helixel--live-get key              ;; flat read
  helixel--live-put key value        ;; flat write
  helixel--live-cat-get key          ;; sub-plist read
  helixel--live-search-set p d       ;; atomic setter
  helixel--live-find-char-set t c d  ;; atomic setter
  helixel--live-cat-set-dir d        ;; shared :dir setter

Ring/any action (explicit plist parameter):
  helixel--action-get action key     ;; flat read
  helixel--action-cat-get action key ;; sub-plist read
```

### 13.3. Redundant `action-start` attrs removed

The search/find-char commands in `helixel-search.el` previously passed
`:search '(:dir ...)` / `:find-char '(:dir ...)` to `helixel-action-start`,
but these were immediately overwritten by `live-search-set` /
`live-find-char-set` in the execution path.  Removed from all 8 call sites:

```elisp
;; Before (dead code — overwritten in done-hook):
(helixel-action-start 'search 'search :search '(:dir forward))
;; After:
(helixel-action-start 'search 'search)
```

### 13.4. Additional cleanup

- Fixed `helixel-define-movement` macro indentation (advice-mode branch)
- Removed redundant `progn` in `helixel-search--done-hook`
- Updated `helixel-action--ring-push` docstring (mentioned old flat keys)
- `from-history` search path now extracts `:subcat` from entry (was hardcoded to `'search`)
- Test `helixel-test-repeat-no-search-repeat-wrap`: use `action-cat-get` not raw `plist-get` for `:pattern`

### 13.5. Bug fix: C-g session cancel → cancel sentinel

**Problem**: `copy-tree` does not deep-copy marker objects.  When `ring-push`
copied an action plist, the ring entry and the live action shared the same
marker.  `cancel-action` freed the live-action marker, corrupting the ring
entry's `:marker`.  Subsequent `;' pressed hit `cl-assertion-failed:
(mark)' because `push-mark` received a dead marker.

Additionally, after cancel the new same-type action was dedup'd against
the old one (identical movement/word content), so `;` couldn't push a
separate ring entry for the new session.

**Fix**:
- `helixel-action--ring-push`: explicitly `copy-marker` the `:marker` so
  ring entries own independent marker objects.
- `helixel--jump-to-marker`: guard against dead markers.
- `cancel-action` now pushes a `(state cancel)` sentinel after the old
  action.  This acts as a session boundary: the new action differs from
  the sentinel, so natural dedup lets it through without `nodedup`.
- New `helixel-action-cycle-categories` custom controls which categories
  `;' navigates (default: movement, textobj, search, find-char).  Cancel
  sentinels (`state`) are hidden.
- `action-cycle` rewritten with filtered ring walking:
  `cycle-visible-p`, `cycle-visible-index`, `cycle-visible-count`,
  `cycle-display` helpers.
- `action-display`: `(state cancel)` shown as `"C-g"`.

**New test**: `helixel-test-c-g-cancels-session` covers the full
`w w C-g w ; ;` flow, verifying ring [movement/word(new), state/cancel,
movement/word(old)] and correct visible-only cycling.

---

## 14. Phase E — from-history refactoring (2026-05-06)

### 14.1. Split `helixel-search--from-history`

The ~80-line function was split into three focused functions:

| Function | Responsibility |
|----------|---------------|
| `helixel-search--history-collect` | Filter ring for valid repeatable entries, build (display . action) alist |
| `helixel-search--history-select` | completing-read prompt, return chosen action plist |
| `helixel-search--history-execute` | Execute chosen action: set repeat-dir, create action, run search/find-char |
| `helixel-search--from-history` | Thin orchestration: collect → select → compute use-dir → execute |

### 14.2. Search path uses `re-search-forward` with let-bound isearch state

The search path in from-history previously used `re-search-forward` directly
without setting up isearch state, which meant:
- `isearch-string` / `isearch-regexp` / `isearch-forward` were not set for
  subsequent `n` repeat (bug #4)
- `isearch-other-end` was not set, so `handle-done` region logic didn't work (bug #3)
- Using `isearch-mode` directly was explored but rejected: it calls
  `isearch-update` → `isearch-message` → `move-to-window-line` which fails
  in batch tests because the temp buffer is not displayed in the selected window

Fix: all isearch state vars (`isearch-string`, `isearch-regexp`, `isearch-forward`,
`isearch-success`, `isearch-other-end`) are let-bound in the search branch.
`re-search-forward` / `re-search-backward` does the actual search.
After search, `isearch-success` and `isearch-other-end` are set from
`(match-beginning 0)` so `helixel-search--handle-done` works correctly
(same region logic as `*`/`#`).

### 14.3. Fix repeat after C-u n (bug #4)

`helixel-search--isearch-repeat` now reads the pattern from
`helixel--repeat-data :pattern` and sets `isearch-string` / `isearch-regexp` /
`isearch-forward` before delegating to `isearch-repeat-forward` /
`isearch-repeat-backward`.  This means:

- `C-u n` picks from history → `helixel-repeat-set` stores pattern
- Subsequent `n` → `helixel-search--isearch-repeat` reads from repeat-data
  → sets isearch vars → `isearch-repeat-forward` finds the string

Previously, `isearch-repeat-forward` relied on global `isearch-string`
which was only set during an active isearch session and lost after exit.

### 14.4. Removed ring-entry marker preservation

`from-history` no longer copies `:marker` from the picked ring entry.
`helixel-action-start` creates a fresh marker at point (or continues
an existing session).  This is consistent with the principle that
history picks reuse only the search string and direction, not the
original session origin.

### 14.5. Cleaner action creation

Removed redundant `helixel--live-put :marker` / `helixel--live-search-set` /
`helixel-repeat-set` calls that were dead code (overwritten by
done-hook or not affecting the result).  Commit is explicit in
`history-execute` via `helixel-action-commit` for both search and
find-char paths.

---

## 15. Phase F — Repeat Edit Architecture (2026-05-07)

> **Goal**: Implement dot-repeat (`.`) — replay the last editing operation
> at the current cursor position.

### 15.1. Action System Changes (`helixel-action.el`)

**Remove dedup from `helixel-action-start`**:
- Previously: same `(category subcat)` → preserve marker, skip ring push
- Now: always push old valid action, always create fresh marker
- Result: `www` creates 3 ring entries instead of 1

**Add group-skipping to `;` cycling**:
- `helixel-action--same-group-p`, `helixel-action--cycle-group-start`,
  `helixel-action--cycle-group-newest`
- `;` shows the oldest entry in each consecutive same-group run
- Equivalent UX to old dedup, but ring is complete

**Marker-aware content dedup**:
- `helixel-action--same-content-p` now compares marker positions
- Prevents same-type operations at different positions from being merged

**New `edit` category**:
- Added to cycle-categories, display format, content comparison
- `helixel--live-edit-set(operator sel-type sel-fn &rest extra)` atomic setter

### 15.2. Selection Context (`helixel--repeat-sel-ctx`)

Set by textobj/line/rect/movement selection commands, read by edit commands:
```elisp
;; textobj/line/rect:
(:fn helixel-mark-inner-word :kind textobj)

;; movement (accumulated during visual mode):
(:kind movement :moves ((helixel-forward-word-start . 2) (helixel-next-line . 1)))
```

Setters added to:
- All textobj macros (`helixel-define-mark-object/pair/quote/regex-textobj`)
- Manual tag/block functions
- `helixel-select-line`, `helixel-select-line-up`, `helixel-select-rectangle`
- `helixel--track-visual-move` injected into `helixel-define-movement` and
  `helixel--with-movement-surround` macros

Fixed: pair/quote/tag/block functions now set `helixel--selection-type = 'textobj`.

### 15.3. Edit Recording (`helixel--record-edit`)

All 9 editing commands call `helixel--record-edit(operator)` before executing:

| Key | Operator | Extra |
|-----|----------|-------|
| `d` | `kill` | — |
| `c` | `change` | track-marker for change-text |
| `y` | `copy` | — |
| `r` | `replace` | — |
| `R` | `replace-char` | `:replace-char CHAR` |
| `p` | `paste-after` | — |
| `P` | `paste-before` | — |
| `<` | `indent-left` | — |
| `>` | `indent-right` | — |
| `i`/`I`/`a`/`A`/`o`/`O` | `insert-text` | track-marker for text |

Recording also creates an `(edit OPERATOR)` action in the ring for `;` jumping.

**Shared kill core**: `helixel--delete-selection` extracts the deletion logic
(push to kill-ring, no record, no clear-data) used by kill, change, and
repeat-change-core.

**Change text tracking**: `helixel--change-track-marker` set before entering
insert mode, read in `helixel-insert-exit` to extract `:change-text`.

**Bug fix**: `c` and `r` compound commands double-recorded edits (e.g.,
`change` → `kill` overwrote the change record). Fixed via
`helixel--inhibit-repeat-record` on inner calls.

### 15.4. Dot-Repeat Execution

`helixel-repeat-edit` bound to `.` in normal mode:

1. Read `helixel--last-edit` (:operator, :sel-ctx, :change-text, ...)
2. `helixel--recreate-selection(sel-ctx)` — unified dispatcher
   - `:fn` present → `(funcall fn)` (textobj, line, rect)
   - `:kind movement` → replay `:moves` with `helixel--current-state='visual`
3. Execute operator (kill/copy/paste/indent/insert-text/...)

### 15.5. Movement Repeat

Movements during visual mode accumulate via `helixel--track-visual-move`:
- Same command repeated → increment count
- Different command → push new entry
- Stored as `(:kind movement :moves ((CMD . COUNT) ...))`

On `.` replay, `helixel--current-state` is let-bound to `'visual` so that
movements extend the region (not create fresh ones).

### 15.6. Module Extraction

All repeat infrastructure extracted to `helixel-repeat.el`:
- Variables: `helixel--repeat-sel-ctx`, `helixel--last-edit`,
  `helixel--change-track-marker`, `helixel--inhibit-repeat-record`
- Functions: `helixel--record-edit`, `helixel-repeat-edit`,
  `helixel--repeat-change-core`, `helixel--recreate-selection`
- `sel-ctx` key `:type` → `:kind` normalization throughout

Dependencies: `helixel-repeat` → `helixel-action` (load time).
Editing commands called at runtime via `declare-function` to avoid
circular dependency with `helixel-common`.

`helixel--delete-selection` and `helixel--track-visual-move` stay in
`helixel-common.el` (tightly coupled to movement macros and editing commands there).

### 15.7. Tests (251 total, +14 new)

Repeat-specific tests:
- No-prev error, paste, replace-char, indent, kill-textobj, kill-linewise,
  change-textobj, preserves-last-edit, clear-data, copy
- Insert-text, empty insert-text
- Movement-kill, movement-change

