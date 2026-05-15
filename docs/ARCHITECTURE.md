# helixel-mode Architecture (Detailed)

> **基础信息**（文件映射、依赖图、数据结构、核心 API、Refactor 阶段）见
> 项目根目录的 `AGENTS.md`。本文档只补充 AGENTS.md 未覆盖的详细子系统说明。

---

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

**Dedup removed from `action-start`** (2026-05): `helixel-action-start` now
**always** pushes the old valid action to ring and **always** creates a fresh
marker. The session-continuity dedup that collapsed `www` into one entry is gone.

**Group-skipping in `;`**: Consecutive ring entries with the same
`(category subcat)` form a "group". `;` cycling jumps to the **oldest** entry
of each group (via `helixel-action--cycle-group-start`), preserving the original
UX while keeping a complete ring.

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

All ring mutations go through `helixel-action--ring-push` which deep-copies
and deduplicates (including marker position comparison):

```elisp
(helixel-action-start cat subcat)            ;; **always** pushes old valid action, always fresh marker
(helixel--live-put :marker MARKER)           ;; override marker afterward (find-repeat, from-history)
(helixel-action-commit)                       ;; commit live action → ring (deep-copied)
(helixel-action-cycle &optional arg)         ;; `;' — first press commits + group-skipping filtered ring walk
(helixel--cancel-action)                      ;; C-g — commit meaningful action + push cancel sentinel
```

Key invariants:
- Ring entries are deep-copied; never alias live action
- `action-start` always pushes the old action and creates a fresh marker
  (no session-continuity dedup)
- `;` cycling uses group-skipping: consecutive same `(category subcat)` entries
  are shown as one group
- `:dir` on actions set at creation, never mutated after commit
- Repeat direction lives in `helixel--repeat-dir` (search.el), separate from
  action `:dir`
- Content dedup in `ring-push` compares marker positions to distinguish
  same-type operations at different locations

### `helixel-define-movement` API

Wraps a builtin Emacs command with action tracking.  Internally delegates to
`helixel-define-command`.

```elisp
;; Wrapper mode — creates a new command that wraps a builtin
(helixel-define-movement NAME BUILTIN TYPE &optional DIR)

;; Advice mode — injects :before advice directly into the builtin
(helixel-define-movement nil BUILTIN TYPE &optional DIR :advice)

;; Example (wrapper):
(helixel-define-movement helixel-forward-paragraph forward-paragraph goto)

;; Example (advice):
(helixel-define-movement nil forward-char char :dir forward :advice)
```

---

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

- **`/ ?`**: use isearch with `isearch-mode-end-hook` to commit result to action
  ring and set `helixel--repeat-data`
- **`* #`**: extract symbol, build regex, run isearch, commit to ring and set
  repeat-data
- **`f F t T`**: store type/char in `helixel--action` plist, delegate to
  `helixel-search--find-char-exec`, set repeat-data
- **`n N`**: `n` reads `helixel--repeat-category` and `helixel--repeat-dir`;
  `N` flips direction then delegates to `n`
- **`C-u n/N`**: delegate to `helixel-search--from-history` which uses
  `action-start` + sets repeat context

### Repeat Context

Separate from `helixel--action :dir` — direction for n/N repeat lives in:

```elisp
helixel--repeat-dir   ;; 'forward | 'backward — where n goes next
helixel--repeat-data  ;; plist: :category, :pattern or :type/:char
```

Set by `/`, `*`, `f` etc. and `C-u n/N`.
Read by `n` via `helixel-repeat-category()` and `helixel-repeat-dir()`.
Flipped by `N` via `helixel-repeat-flip-dir()`.
Never mutates `helixel--action :dir`, which is a historical record set at
action creation.

Why separate repeat-dir from action `:dir`:
- `helixel--action :dir` is set once at creation and must never be mutated
  after commit (otherwise content-based dedup would see the changed `:dir`
  and push duplicate ring entries).
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
- Both record the picked entry in `helixel--repeat-data` and create a new
  action via `helixel-action-start`
- Syncs ring front's `:dir` when the picked entry IS the ring front (for
  display consistency)

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

## Repeat Edit (`.`) — Detailed Tables

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

`helixel-textobj.el` has no `(require 'helixel-common)` dependency. It exposes
two hook variables that `helixel-common.el` injects after loading:

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

This means `helixel-textobj.el` can be extracted as a third-party package —
callers just set the two hooks.

### Word/WORD Movement Helpers

`helixel-textobj.el` provides the building blocks that both text object
selection and movement commands share:

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

Text objects (`iw`,`aw`,`iW`,`aW`) use the same underlying
`helixel--forward-word` / `helixel--forward-WORD` forward-ops via the
thing-at-point system.

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
All text objects call the action hook (`helixel-textobj-action-function`)
when available, which `helixel-common.el` wires to `helixel-action-start`.

---

## Keybinding API

```elisp
(helixel-define-key STATE KEY DEF &optional MODE)
;; STATE: insert, normal, motion, visual, view, goto, window, space
;; MODE: major-mode symbol for mode-specific bindings
```

---

## Global Jump List (`C-o` / `C-i`)

### Overview

Analogous to Vim's jumplist — `C-o` jumps to older positions, `C-i` (Tab)
jumps to newer positions.  Unlike `;` which only sets mark, jump commands
**move point** and support **cross-buffer** navigation.

The jump list is a **global** ring (`helixel--jump-list`) that mirrors the
buffer-local action ring.  Every action committed via
`helixel-action--ring-push` is also pushed to the jump list (filtered by
`helixel-jump-categories`).

### Entry Format

```elisp
(:marker   <marker>     ;; position in target buffer
 :buffer   <buffer>     ;; which buffer this entry lives in
 :category <symbol>     ;; movement | search | find-char | edit | goto | textobj | user
 :subcat   <symbol>     ;; char | line | word | search | next | etc.)
```

### Keybindings

| Key | Command | Behavior |
|-----|---------|----------|
| `C-o` | `helixel-jump-backward` | Jump to older entry, moving point |
| `C-i` (Tab) | `helixel-jump-forward` | Jump to newer entry |

### Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `helixel-jump-list-max` | `100` | Max entries in the global jump list |
| `helixel-jump-categories` | `(movement textobj search find-char edit goto user)` | Categories that are **recorded** into the jump list |
| `helixel-jump-cycle-categories` | same as above | Categories visible during `C-o`/`C-i` cycling |

Users can narrow `helixel-jump-cycle-categories` to exclude basic movements
(e.g., keep only `search find-char edit goto`) for a tighter Vim-style jumplist
while still recording everything for completeness.

### Cross-Buffer Jumps

When `C-o` or `C-i` switches to a different buffer, a **return entry**
(`jump/return`) is automatically pushed so `C-i` can take you back.  This
is handled internally by `helixel--jump-goto`.

### Group-Skipping (Generic Helpers)

Both `;` cycling and `C-o`/`C-i` jump navigation share the same group-skipping
algorithm via generic parameterized helpers in `helixel-action.el`:

```elisp
;; Core group navigation (parameterized by same-group predicate)
(helixel--grouped-ring-group-start   list pos same-group-pred)  → oldest in group
(helixel--grouped-ring-group-newest  list pos same-group-pred)  → newest in group

;; Visibility filtering (parameterized by visible predicate)
(helixel--grouped-ring-visible-index list pos visible-pred)  → first visible ≥ pos
(helixel--grouped-ring-visible-count list visible-pred)      → count of visible
(helixel--grouped-ring-find         list pos dir visible-pred) → next visible in dir
```

Usage:
- `;` cycling: `same-group-pred` = `helixel-action--same-group-p`
  (category+subcat), `visible-pred` = `helixel-action--cycle-visible-p`
  (checks `cycle-categories`)
- C-o/C-i: `same-group-pred` = `helixel--jump-same-group-p`
  (category+subcat+buffer), `visible-pred` = `helixel--jump-visible-p`
  (checks `jump-cycle-categories` + live marker)

Consecutive entries with matching predicates are collapsed into one jump target
(the oldest of the group).  Buffer identity is included for jumps so entries
in different buffers are never merged.

### Jump List Push via Hook

Every action pushed to the ring triggers `helixel-action-push-functions` —
an abnormal hook run with the action plist as argument.  The jump list
subsystem subscribes via `add-hook`, so `helixel-action.el` has zero
dependency on the jump list.

```elisp
(defvar helixel-action-push-functions nil
  "Abnormal hook run after an action is pushed to `helixel--action-ring'.
Each function is called with one argument, the action plist.")

;; helixel-common.el wires it:
(add-hook 'helixel-action-push-functions #'helixel--jump-list-push)
```

### Public API

```elisp
;; Push current point to jump list (for custom commands)
(helixel-register-jump &optional category subcat)

;; Add :before advice to a command to auto-register its start position
(helixel-define-jump-command 'symbol)
```

### Hook

```elisp
(defvar helixel-jump-cleanup-function nil
  "Function called after a successful C-o/C-i jump to clean up selection state.
Set by helixel-common.el to `helixel--clear-data'.")
```

### Architecture

```
helixel--action-ring (buffer-local)          helixel--jump-list (global)
         │                                           │
         │  helixel-action--ring-push               │
         │  ──► run-hook 'action-push-functions ──► │
         │         │                                 │
         │         └── helixel--jump-list-push       │
         │                                           │
    ; / C-u ;                                    C-o / C-i
    (buffer-local, push-mark)                    (global, goto-char + switch-buffer)
```

---

## Test Conventions

- Use `(helixel-test-with-buffer "content" body...)` for buffer tests
- Set `this-command` and `last-command` before calling functions that use them
- 366 ERT tests covering search, find-char, movement, textobj, surround,
  action tracking, history, and session management
