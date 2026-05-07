# helixel-mode Architecture

## File Responsibilities

| File | Role |
|------|------|
| `helixel.el` | Entry point: requires sub-modules, provides `helixel` feature |
| `helixel-action.el` | Action infrastructure: nested data model, ring API, group-skipping session cycling. |
| `helixel-common.el` | State machine, keymaps, movement, editing, modes, repeat-edit (`.`). Requires helixel-action and helixel-textobj. |
| `helixel-search.el` | Search & find-char engine + repeat context (`helixel--repeat-dir`, `helixel--repeat-data`). Requires helixel-common. |
| `helixel-textobj.el` | Text objects (word, symbol, etc.) with forward-ops. Independent of helixel-common via hooks. |
| `helixel-test.el` | ERT test suite (247 tests) |

## Action Data Model (`helixel-action.el`)

### Nested Structure

Actions are plists.  Universal keys + one category sub-plist keyed by keyword:

```elisp
;; Universal (all actions):
(:category search :subcat search :marker <M> :display t
 ;; Category sub-plist (key matches :category symbol → keyword):
 :search    (:pattern "foo" :dir forward))

(:category find-char :subcat next :marker <M> :display t
 :find-char (:type next :char ?x :dir forward))

(:category movement :subcat line :marker <M>
 :movement (:dir forward))

(:category state :subcat insert :marker <M>)
;; state and textobj have no category-specific data

(:category edit :subcat kill :marker <M> :display t
  :edit (:operator kill :sel-type textobj :sel-fn helixel-mark-inner-word))
```

**Dedup removed from `action-start`** (2026-05): `helixel-action-start` now **always** pushes the old valid action to ring and **always** creates a fresh marker. The session-continuity dedup that collapsed `www` into one entry is gone.

**Group-skipping in `;`**: Consecutive ring entries with the same `(category subcat)` form a "group". `;` cycling jumps to the **oldest** entry of each group (via `helixel-action--cycle-group-start`), preserving the original UX while keeping a complete ring.`

### Accessor API (also includes `edit` category setters)

External code must use these — no raw `plist-get`/`plist-put` on `helixel--action`:

```elisp
;; Flat reads/writes (live — implicit `helixel--action')
(helixel--live-get :category)                  ;; read universal key
(helixel--live-put :display t)                  ;; write universal key

;; Flat read (any action plist)
(helixel--action-get ring-entry :subcat)        ;; flat read from any action

;; Category reads
(helixel--live-cat-get :type)                   ;; read from live action's sub-plist
(helixel--action-cat-get ring-entry :dir)       ;; sub-plist read from any action

;; Atomic setters — function signatures enforce completeness (live only)
(helixel--live-search-set pattern dir)           ;; 2 required args
(helixel--live-find-char-set type char dir)      ;; 3 required args
(helixel--live-cat-set-dir dir)                  ;; shared :dir setter (live only)
(helixel--live-edit-set operator sel-type sel-fn &rest extra)  ;; :edit sub-plist
```

### Ring API (Unified Push)

All ring mutations go through `helixel-action--ring-push` which deep-copies and deduplicates (including marker position comparison):

```elisp
(helixel-action-start cat subcat)            ;; **always** pushes old valid action, always fresh marker
(helixel--live-put :marker MARKER)           ;; override marker afterward (find-repeat, from-history)
(helixel-action-commit)                       ;; commit live action → ring (deep-copied)
(helixel-action-cycle &optional arg)         ;; `;' — first press commits + group-skipping filtered ring walk
(helixel--cancel-action)                      ;; C-g — commit meaningful action + push cancel sentinel
```

Key invariants:
- Ring entries are deep-copied; never alias live action
- `action-start` always pushes the old action and creates a fresh marker (no session-continuity dedup)
- `;` cycling uses group-skipping: consecutive same `(category subcat)` entries are shown as one group
- `:dir` on actions set at creation, never mutated after commit
- Repeat direction lives in `helixel--repeat-dir` (search.el), separate from action `:dir`
- Content dedup in `ring-push` compares marker positions to distinguish same-type operations at different locations

### `helixel-define-movement` API

```elisp
;; Wrapper mode — creates a new command that wraps a builtin
(helixel-define-movement NAME BUILTIN TYPE &optional DIR)

;; Advice mode — injects :before advice directly into the builtin
(helixel-define-movement nil BUILTIN TYPE &optional DIR :advice)

;; NAME:    new command symbol (nil for advice mode)
;; BUILTIN: underlying Emacs command (e.g. forward-paragraph)
;; TYPE:    subcat symbol (e.g. goto)
;; DIR:     optional direction

;; Example (wrapper):
(helixel-define-movement helixel-forward-paragraph forward-paragraph goto)

;; Example (advice):
(helixel-define-movement nil forward-char char :dir forward :advice)
```

## Search & Find-Char (`helixel-search.el`)

### Keybindings

| Key | Command | Direction |
|-----|---------|-----------|
| `/` | `helixel-search-forward` | isearch-regexp forward |
| `?` | `helixel-search-backward` | isearch-regexp backward |
| `*` | `helixel-search-at-point-next` | symbol at point forward |
| `#` | `helixel-search-at-point-prev` | symbol at point backward |
| `f` | `helixel-find-next-char` | find char forward |
| `F` | `helixel-find-prev-char` | find char backward |
| `t` | `helixel-find-till-char` | find till char forward |
| `T` | `helixel-find-prev-till-char` | find till char backward |
| `n` | `helixel-search-repeat-next` | repeat (C-u n: history) |
| `N` | `helixel-search-repeat-reverse` | toggle + repeat (C-u N: history) |
| `M-.` | `helixel-find-repeat` | repeat find-char |

### Architecture

- **`/ ?`**: use isearch with `isearch-mode-end-hook` to commit result to action ring and set `helixel--repeat-data`
- **`* #`**: extract symbol, build regex, run isearch, commit to ring and set repeat-data
- **`f F t T`**: store type/char in `helixel--action` plist, delegate to `helixel-search--find-char-exec`, set repeat-data
- **`n N`**: `n` reads `helixel--repeat-category` and `helixel--repeat-dir`; `N` flips direction then delegates to `n`
- **`C-u n/N`**: delegate to `helixel-search--from-history` which uses `action-start` + sets repeat context

### Repeat Context (`helixel-search.el`)

Separate from `helixel--action :dir` — direction for n/N repeat lives in:

```elisp
helixel--repeat-dir   ;; 'forward | 'backward — where n goes next
helixel--repeat-data  ;; plist: :category, :pattern or :type/:char
```

Set by `/`, `*`, `f` etc. and `C-u n/N`.
Read by `n` via `helixel-repeat-category()` and `helixel-repeat-dir()`.
Flipped by `N` via `helixel-repeat-flip-dir()`.
Never mutates `helixel--action :dir`, which is a historical record set at action creation.

Why separate repeat-dir from action :dir:
- `helixel--action :dir` is set once at creation and must never be mutated after
  commit (otherwise content-based dedup would see the changed `:dir` and push
  duplicate ring entries).
- `helixel--repeat-dir` is independent state that `N` can freely flip without
  touching any ring entry.
- This structural separation eliminates the aliasing/direction-corruption bugs.

### Session Continuity

`helixel-find-repeat` passes the original find-char variant (`next` or `till`)
from `helixel--repeat-data :type` as subcat to `helixel-action-start` —
**not** the literal `repeat`.  This ensures `f h` → `n` → `n` all share the
same `(find-char next)` type, so `action-start` treats them as continuing one
session: no duplicate ring entries, and `;` jumps to the original `f` start.
Same principle as `w w w` all sharing `(movement word)`.

### Configurable Repeat Categories

```elisp
(defcustom helixel-search-repeat-categories '(search find-char)
  "Action :category symbols that n/N can repeat.")
```

### Configurable Cycle Categories

```elisp
(defcustom helixel-action-cycle-categories
  '(movement textobj search find-char edit)
  "Action :category symbols that `;' (`helixel-action-cycle') navigates.
Categories not listed (e.g. `state' for cancel sentinels) are skipped
during cycling but remain in the ring for dedup purposes.")
```

### History Selection (`C-u n` / `C-u N`)

- `C-u n`: pick from history, execute in the entry's **stored** direction
- `C-u N`: pick from history, execute in the **opposite** of stored direction
- Both record the picked entry in `helixel--repeat-data` and create a new action via `helixel-action-start`
- Syncs ring front's `:dir` when the picked entry IS the ring front (for display consistency)

### Core Functions

```elisp
;; Repeat context (helixel-search.el)
(helixel-repeat-dir)                          ; → 'forward | 'backward
(helixel-repeat-set-dir DIR)                  ; set repeat direction
(helixel-repeat-flip-dir)                     ; toggle repeat direction
(helixel-repeat-set CAT &rest DATA)           ; record what to repeat
(helixel-repeat-category)                     ; → 'search | 'find-char | nil

;; Search / find-char functions
(helixel-action-commit)                        ; commit live action → ring (deep-copied)
(helixel-search--sync-ring-front-dir DIR)      ; sync ring entry :dir (no live-action mutation)
(helixel-search--find-char-exec char type dir) ; initial f/F/t/T search
(helixel-search--find-char-core &optional action dir) ; replay find-char
(helixel-search--isearch-repeat dir)           ; isearch repeat, reads pattern from repeat-data
(helixel-search--history-collect)              ; → (display . action) alist from ring
(helixel-search--history-select alist prompt)  ; completing-read → chosen action plist
(helixel-search--history-execute action dir)   ; execute chosen history entry
(helixel-search--from-history forwardp)        ; C-u n/N orchestration
```

---

## Repeat Edit (`.`) (`helixel-common.el`)

### Overview

Dot-repeat replays the last editing operation at the current cursor position.
Supported operations: kill (`d`), change (`c`), copy (`y`), replace (`r`/`R`),
paste (`p`/`P`), indent (`<`/`>`).

### Data Flow

```
selection command → set helixel--repeat-sel-ctx (:fn ... :type ...)
         │
         ▼
edit command → helixel--record-edit(operator) → helixel--last-edit (for .)
         │                    │
         │                    └──→ helixel-action-start 'edit → ring (for ;)
         ▼
   . (dot) → helixel-repeat-edit() → read last-edit
                                        │
                   ┌────────────────────┘
                   ▼
              funcall (:fn) recreate selection
                   │
                   ▼
              execute operator via delete-selection / yank / insert
```

### Key Variables

```elisp
helixel--repeat-sel-ctx       ;; Set by textobj/line/rect selection commands
                              ;; (:fn FUNCTION :type textobj|line|rect)
helixel--last-edit             ;; Latest edit plist for dot-repeat
                              ;; (:operator SYMBOL :sel-ctx PLIST :change-text STR|nil)
helixel--change-track-marker   ;; Tracks inserted text during change operations
helixel--inhibit-repeat-record ;; Prevents `.` and compound commands from re-recording
```

### Shared Kill Core

```elisp
(helixel--delete-selection)   ;; Delete region/char, push to kill-ring.
                              ;; Does NOT record edit, does NOT clear data.
                              ;; Used by: kill, change, repeat-change-core.
```

| Command | record-edit | delete-selection | clear-data | switch insert |
|---------|------------|------------------|------------|---------------|
| `kill-thing-at-point` | yes | yes | yes | no |
| `change-thing-at-point` | yes | yes | no | yes |
| `repeat-change-core` (`.`) | no (inhibited) | yes | no | no (insert text) |

### Recording Details

Each editing command calls `helixel--record-edit(operator)` which:
1. Stores the edit in `helixel--last-edit` (with current `helixel--repeat-sel-ctx`)
2. Consumes `helixel--repeat-sel-ctx` (sets to nil)
3. Calls `helixel-action-start 'edit operator` + `live-edit-set` + `action-commit`
   → enters the action ring for `;` jumping

The `helixel--inhibit-repeat-record` variable is bound to `t` during:
- `helixel-repeat-edit` (to prevent `.` from overwriting `last-edit`)
- `helixel-replace` → `helixel-yank` internal call (to prevent double-record)

### Supported Operations

| Key | Operator | Requires sel-ctx? | Extra data |
|-----|----------|-------------------|------------|
| `d` | `kill` | yes (for textobj/line/rect) | — |
| `c` | `change` | yes | `:change-text` (extracted from insert-exit) |
| `y` | `copy` | yes | — |
| `r` | `replace` | no | — |
| `R` | `replace-char` | no | `:replace-char` CHAR |
| `p` | `paste-after` | no | — |
| `P` | `paste-before` | no | — |
| `<` | `indent-left` | yes (line) | — |
| `>` | `indent-right` | yes (line) | — |

### Not Recorded

Commands that do NOT generate repeatable edits:
- `undo`/`undo-redo` (`u`/`U`)
- Insert-mode entry (`i`/`I`/`a`/`A`/`o`/`O`)
- State transitions and movements
- Search/find-char (use `n`/`N` instead)
- Colon commands (`:`)

### Future Extensions

| Feature | Approach |
|---------|----------|
| Charwise movement repeat (`vw d` → `.`) | Extend `sel-ctx` with `:moves` list of `(fn . count)` pairs |
| Count prefix repeat (`3x d` → `.`) | Add `:count` to `sel-ctx` |
| Insert-mode typing repeat (`ihello<ESC>`) | Track insert text similarly to change tracking |

---

## Text Objects (`helixel-textobj.el`)

### Decoupling via Hooks

`helixel-textobj.el` has no `(require 'helixel-common)` dependency. It exposes two hook
variables that `helixel-common.el` injects after loading:

```elisp
(defvar helixel-textobj-action-function nil
  "If non-nil, called with (CATEGORY SUBCAT) on textobj action start.")

(defvar helixel-textobj-visual-state-p-function nil
  "If non-nil, called with no args, return t when in visual state.")
```

`helixel-common.el` sets them:
```elisp
(setq helixel-textobj-action-function #'helixel-action-start)
(setq helixel-textobj-visual-state-p-function
      (lambda () (eq helixel--current-state 'visual)))
```

This means `helixel-textobj.el` can be extracted as a third-party package — callers
just set the two hooks.

### Word/WORD Movement Helpers

`helixel-textobj.el` provides the building blocks that both text object selection
and movement commands share:

```elisp
(helixel--forward-beginning THING &optional COUNT)  ; w / b
(helixel--forward-end       THING &optional COUNT)  ; e
```

Movement commands in `helixel-common.el` delegate to these:

| Key | Movement Command | Helper Call |
|-----|-----------------|-------------|
| `w` | `helixel-forward-word-start` | `(helixel--forward-beginning 'helixel-word)` |
| `b` | `helixel-backward-word-start` | `(helixel--forward-beginning 'helixel-word -1)` |
| `e` | `helixel-forward-word-end` | `(helixel--forward-end 'helixel-word)` |
| `W` | `helixel-forward-WORD-start` | `(helixel--forward-beginning 'helixel-WORD)` |
| `B` | `helixel-backward-WORD` | `(helixel--forward-beginning 'helixel-WORD -1)` |
| `E` | `helixel-forward-WORD-end` | `(helixel--forward-end 'helixel-WORD)` |
| `v` | `helixel-backward-word-end` | `(helixel--forward-end 'helixel-word -1)` |
| — | `helixel-forward-symbol-start` | `(helixel--forward-beginning 'helixel-symbol)` |
| — | `helixel-forward-symbol-end` | `(helixel--forward-end 'helixel-symbol)` |
| — | `helixel-backward-symbol-start` | `(helixel--forward-beginning 'helixel-symbol -1)` |
| — | `helixel-backward-symbol-end` | `(helixel--forward-end 'helixel-symbol -1)` |
| — | `helixel-backward-WORD-end` | `(helixel--forward-end 'helixel-WORD -1)` |

Text objects (`iw`,`aw`,`iW`,`aW`) use the same underlying `helixel--forward-word` /
`helixel--forward-WORD` forward-ops via the thing-at-point system.

### Macros

```elisp
(helixel-define-mark-object NAME THING DOC SUBCAT &optional RESTRICTED-P)
(helixel-define-mark-pair NAME OPEN CLOSE DOC INNER-P)
(helixel-define-mark-quote NAME QUOTE-CHAR DOC INNER-P)
```

### Subcategories

| Family | Subcat | Commands |
|--------|--------|----------|
| word | `word` | `miw` `maw` |
| WORD | `WORD` | `miW` `maW` |
| symbol | `symbol` | `mio` `mao` |
| sentence | `sentence` | `mis` `mas` |
| paragraph | `paragraph` | `mip` `map` |
| brackets | `pair` | `mi(` `ma(` `mi[` `ma[` `mi{` `ma{` `mi<` `ma<` |
| quotes | `quote` | `mi"` `ma"` `mi'` `ma'` ``mi` `` ``ma` `` |
| tag | `tag` | `mit` `mat` |

Different subcats create independent sessions for `;`.
All text objects call the action hook (`helixel-textobj-action-function`) when
available, which `helixel-common.el` wires to `helixel-action-start`.

## `helixel-define-key` API

```elisp
(helixel-define-key STATE KEY DEF &optional MODE)
;; STATE: insert, normal, motion, visual, view, goto, window, space
;; MODE: major-mode symbol for mode-specific bindings
```

## Test Conventions

- Use `(helixel-test-with-buffer "content" body...)` for buffer tests
- Set `this-command` and `last-command` before calling functions that use them
- 208 ERT tests covering search, find-char, movement, textobj, action tracking, history, and session management
