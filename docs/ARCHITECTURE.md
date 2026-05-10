# helixel-mode Architecture

## File Responsibilities

| File | Role |
|------|------|
| `helixel.el` | Entry point: requires sub-modules, provides `helixel` feature |
| `helixel-edit.el` | **Edit transaction model**: unified schema (`:op :sel :payload :marker`), builder, equality, display. No helixel deps — kernel module. |
| `helixel-action.el` | Action infrastructure: ring API, `;` group-skipping. Stores edit txs in ring. Requires helixel-edit. |
| `helixel-repeat.el` | Dot-repeat (`.`): recording (`helixel--record-edit` → `helixel--last-tx`), selection replay, execution dispatcher. Requires helixel-action, helixel-edit. |
| `helixel-common.el` | State machine, keymaps, movement, editing commands, shared kill core. Requires helixel-action, helixel-textobj, helixel-repeat. |
| `helixel-search.el` | Search & find-char engine + repeat context. Requires helixel-common. |
| `helixel-textobj.el` | Text objects and selection. Independent of helixel-common via hooks. |
| `helixel-delimiter.el` | Unified delimiter protocol: plist accessors, finder (`helixel-delimiter-find`), bounds (`helixel-delimiter-bounds`), builders for pair/tag/block/regex delimiters. |
| `helixel-surround.el` | Surround operations: add, delete, replace. Uses delimiter protocol from helixel-delimiter. |
| `helixel-test.el` | ERT test suite (305 tests) |

### Dependency Graph

```
helixel-edit.el          kernel (no helixel deps)
   ↓
helixel-action.el        ring + ;  (requires helixel-edit)
   ↓
helixel-repeat.el        . infrastructure (requires helixel-action + edit)
   ↓
helixel-delimiter.el     delimiter protocol (standalone)
   ↓
helixel-textobj.el       text objects (requires helixel-delimiter)
   ↓
helixel-surround.el      surround ops (requires helixel-delimiter)
   ↓
helixel-common.el        state machine + editing (requires all above)
   ↓
helixel-search.el        (requires helixel-common)
```

### Edit Transaction Schema (`helixel-edit.el`)

All edit operations are represented as a single plist:

```elisp
(:op     symbol    ;; kill | change | copy | replace | replace-char
                   ;; | paste-after | paste-before | indent-left | indent-right
                   ;; | insert-text
 :sel    plist|nil ;; selection context (:fn F :kind K) or nil
 :payload plist    ;; operator-specific data
 :marker marker)   ;; start position (for ; jumping)

;; Payload per :op:
;;   change:       (:inserted-text STRING)
;;   replace-char: (:char CHAR)
;;   insert-text:  (:text STRING)
```

Key functions:
```elisp
(helixel-edit-make op sel-ctx &rest payload-kv)  → tx
(helixel-edit-op tx)       → :op
(helixel-edit-sel tx)      → :sel
(helixel-edit-payload tx)  → :payload
(helixel-edit-equal-p a b) → boolean (ignores :marker)
(helixel-edit-display tx)  → "d.textobj", "c", "p", etc.
```

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
  :edit (:op kill :sel (:fn helixel-mark-inner-word :kind textobj)
         :payload nil :marker <M>))
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
(helixel--live-edit-set tx)                       ;; store full tx in :edit sub-plist
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

## Repeat Edit (`.`) — Transaction-Driven Architecture

### Overview

All editing operations are represented as **edit transactions** (`helixel-edit.el`),
a unified schema consumed by repeat (`.`), action ring (`;`), and editing commands.

A transaction is a plist: `(:op OP :sel SEL-CTX :payload PAYLOAD :marker MARKER)`.

### Data Flow

```
selection cmd → set helixel--repeat-sel-ctx
  ↓
edit cmd → helixel--record-edit(op, &rest payload-kv)
  ↓
helixel-edit-make(op, sel-ctx, payload) → tx (:op :sel :payload :marker)
  ↓
helixel--last-tx = tx            (dot-repeat consumer)
helixel--live-edit-set(tx)       (action ring — ; jumping consumer)
  ↓
. → helixel-repeat-edit()
  → helixel--recreate-selection(edit-sel tx)
  → helixel--execute-edit(tx)    (unified dispatcher)
```

### Key Variables

```elisp
;; helixel-repeat.el:
helixel--repeat-sel-ctx       ;; Set by selection, consumed by record-edit
helixel--last-tx               ;; Latest transaction (:op :sel :payload :marker)
helixel--change-track-marker   ;; Tracks inserted text (change/insert operations)
helixel--inhibit-repeat-record ;; Prevents re-recording during . and compound cmds

;; helixel-edit.el (kernel, no side effects):
;; No buffer-local state — pure data functions.
```

### Selection Replay

`helixel--recreate-selection(sel-ctx)` is the unified dispatcher:
- `:fn` present → `(funcall fn)` (textobj, line, rect)
- `:kind movement` → replay `:moves` list with visual state binding

### Execution Dispatcher

`helixel--execute-edit(tx)` maps `:op` to the appropriate execution function.
`helixel-repeat-edit` is now 5 lines: read tx → recreate selection → execute.

### Shared Kill Core (`helixel-common.el`)

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

`helixel--record-edit(operator &rest extra)` builds a tx via `helixel-edit-make`,
stores it in `helixel--last-tx`, and pushes to the action ring. The `extra` kwargs
become the tx `:payload`.

The `helixel--inhibit-repeat-record` variable is bound to `t` during:
- `helixel-repeat-edit` (to prevent `.` from overwriting `last-tx`)
- `helixel-replace` → `helixel-yank` internal call (to prevent double-record)

### Supported Operations

| Key | Operator | Requires sel-ctx? | Payload |
|-----|----------|-------------------|---------|
| `d` | `kill` | yes | nil |
| `c` | `change` | yes | `(:inserted-text STRING)` |
| `y` | `copy` | yes | nil |
| `r` | `replace` | no | nil |
| `R` | `replace-char` | no | `(:char CHAR)` |
| `p` | `paste-after` | no | nil |
| `P` | `paste-before` | no | nil |
| `<` | `indent-left` | yes (line) | nil |
| `>` | `indent-right` | yes (line) | nil |
| `i`/`I`/`a`/`A`/`o`/`O` | `insert-text` | no | `(:text STRING)` |

Sel-ctx structure:
- `(:fn FUNCTION :kind textobj|line|rect)` — replay by calling the function
- `(:kind movement :moves ((FN . COUNT) ...))` — replay in visual state to extend region

### Not Recorded

Commands that do NOT generate repeatable edits:
- `undo`/`undo-redo` (`u`/`U`)
- State transitions (entry to insert not via `c`/`i`/etc. is recorded)
- Search/find-char (use `n`/`N` instead)
- Colon commands (`:`)

### Future Extensions

| Feature | Approach | Status |
|---------|----------|--------|
| Charwise movement repeat (`vw d` → `.`) | `:moves` list in sel-ctx with visual-state binding | ✅ DONE |
| Insert-mode typing repeat (`ihello<ESC>`) | `change-track-marker` in all insert-entry commands | ✅ DONE |
| Unified edit transaction model | `helixel-edit.el`, tx schema shared by repeat/action | ✅ DONE |
| Count prefix repeat (`3x d` → `.`) | `:count` in sel-ctx | 🔜 |
| `C-u .` edit history browsing | Reuse action ring + `helixel-edit-display` | 🔜 |

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

### Selection Activation Helper

All textobj commands delegate to a single helper for activating the range:

```elisp
(helixel--activate-textobj-range RANGE &optional DELIMITER)
```

Handles both cons `(BEG . END)` and list `(BEG END ...)` ranges.
Sets `helixel--selection-type` to `'textobj` and populates
`helixel--repeat-sel-ctx` with `:fn this-command :kind 'textobj :delimiter`.
All textobj macros and hand-written functions use this helper, eliminating
~57 lines of duplicated boilerplate.

### Macros

```elisp
(helixel-define-mark-object NAME THING DOC SUBCAT &optional RESTRICTED-P)
(helixel-define-mark-pair NAME OPEN CLOSE DOC INNER-P)
(helixel-define-mark-quote NAME QUOTE-CHAR DOC INNER-P)
(helixel-define-regex-textobj NAME BEGIN-RE END-RE &optional NAME-GROUP SUBCAT)
```

`helixel-define-regex-textobj` defines inner/a textobj commands for
regex-delimited blocks (org `#+begin_src`/`#+end_src`, markdown ``` fences,
LaTeX environments, etc.).  It generates two commands and wires them to the
action hook.  NAME-GROUP enables name-based balancing; nil uses counter-based
matching.

The built-in block textobj (`mi c` / `ma c`) uses
`helixel-block-textobj-alist` with pre-configured patterns for org-mode
and markdown-mode, plus `helixel-block-textobj-fallback-alist` for
additional patterns.

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
| block | `block` | `mic` `mac` |

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
- 305 ERT tests covering search, find-char, movement, textobj, surround, action tracking, history, and session management
