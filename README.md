# helixel-mode

Helix-style modal editing for Emacs.

## Install

```elisp
(use-package helixel
  :vc (:url "https://github.com/jixiuf/helixel-mode")
  :config (helixel-mode))
```

Or manually:

```elisp
(add-to-list 'load-path "/path/to/helixel-mode")
(require 'helixel)
(helixel-mode)
```

Requires Emacs >= 29.1.

## Usage

| Key | Action |
|-----|--------|
| `h` `j` `k` `l` | Move |
| `w` `b` `e` | Word forward / back / end |
| `W` `B` `E` | WORD forward / back / end |
| `f` `t` `F` `T` | Find char |
| `m i` `m a` | Text objects (word, symbol, sentence, paragraph, pairs, quotes, tags) |
| `m s` `m t` | Surround add / add tag |
| `m d` `m r` | Surround delete / replace |
| `;` | Set mark to previous session start |
| `C-o` `C-i` | Jump to older / newer position (global, cross-buffer) |
| `M-.` | Repeat last find-char |
| `n` `N` | Repeat / reverse direction repeat (`C-u n` pick from history) |
| `.` | Repeat last edit (kill, change, paste, insert, ...) |
| `i` `a` `I` `A` `o` `O` | Enter insert mode |
| `v` | Enter visual mode |
| `d` `c` `y` `r` `R` | Edit: delete, change, copy, replace, replace-char |
| `p` `P` | Paste after / before |
| `<` `>` | Indent left / right |
| `u` `U` | Undo / redo |
| `x` | Select current line |
| `g` | Goto prefix |
| `SPC` | Space prefix (LSP / project) |
| `C-w` | Window prefix |
| `:` | ex commands |
| `ESC` | Normal mode |

### States

| State | Description |
|-------|-------------|
| normal | Default editing state |
| insert | Text input |
| visual | Selection mode |
| motion | Read-only navigation |

### Text Objects

`m i` (inner) and `m a` (a / around) select text objects.  Supports
word (`w`), WORD (`W`), symbol (`o`), sentence (`s`), paragraph (`p`),
pairs (`(` `[` `{` `<`), quotes (`\"` `'` `` \` ``), tags (`t`),
and block (`c`).

**Region-aware selection** — in normal mode when a region is already
active, the first press selects the text object **within the highlighted
region** instead of what is at point.  This means:

- `hello |world` with region `hello ` active: `miw` selects `hello`.
- Second press (follow-up): selects the **next** word without expanding.
- In **visual** mode: pressing repeatedly **expands** the selection.

White space adjustment: cursor on whitespace between words automatically
finds the adjacent word.

**Block text object** — `mi c` / `ma c` selects the nearest enclosing
block (org `#+begin_src`/`#+end_src`, markdown ``` fences, or bracket
pairs `()` `[]` `{}`).  Mode-specific patterns are configured via
`helixel-block-textobj-alist`:

```elisp
;; Built-in defaults — override to add or customize
(setq helixel-block-textobj-alist
      '((org-mode . ("^#\\+begin_\\([^ \n\r]+\\)[^\n]*"
                     "^#\\+end_\\([^ \n\r]+\\)[^\n]*" 1))
        (org-mode . ("^```.+$" "^```[ \t]*$" nil))
        (markdown-mode . ("^```.+$" "^```[ \t]*$" nil))
        (gfm-mode . ("^```.+$" "^```[ \t]*$" nil))))
```

Each entry is `(MODE . (BEGIN-RE END-RE NAME-GROUP))`.  Multiple
entries for the same MODE are tried; the tightest enclosing block wins.
`NAME-GROUP` nil means counter-based balancing (fences), an integer
means name-based (org blocks).  Fallback patterns can be added via
`helixel-block-textobj-fallback-alist`.

### Surround

`m s` (surround-add) and `m t` (surround-add-tag) wrap the active
selection with delimiter pairs.  `m d` (delete) removes surrounding
delimiters.  `m r` (replace) replaces them with new ones.

`m s` reads a character and looks it up first in
`helixel-surround-block-alist` (per-mode string pairs like
`#+begin_src`/`#+end_src`), then in `helixel--surround-pairs` (char
pairs like `()` `[]` `{}` `<>` and quotes).

`m t` reads a tag name string and wraps the selection in XML tags.

`m d` and `m r` read delimiter info from the previous text object
selection (mi / ma), so no extra input is needed — just select a text
object then press `m d` or `m r`.

| Key | Selection type | Behavior |
|-----|---------------|----------|
| `m s` `(` | Active region | Wrap region in `( )` |
| `m s` `[` | Active region | Wrap region in `[ ]` |
| `m s` `{` | Active region | Wrap region in `{ }` |
| `m s` `<` | Active region | Wrap region in `< >` |
| `m s` `'` | Active region | Wrap region in `' '` |
| `m s` `"` | Active region | Wrap region in `" "` |
| `m s` `` ` `` | Active region | Wrap region in `` ` `` |
| `m s` `s` | Active region (org) | Wrap in `#+begin_src` / `#+end_src` |
| `m s` `e` | Active region (org) | Wrap in `#+begin_example` / `#+end_example` |
| `m s` `q` | Active region (org) | Wrap in `#+begin_quote` / `#+end_quote` |
| `m s` `` ` `` | Active region (markdown) | Wrap in `` ``` `` / `` ``` `` |
| `m t` | Active region | Wrap in `<tag>` / `</tag>` |
| `m d` | After mi/ma | Delete surrounding delimiters |
| `m r` | After mi/ma | Replace surrounding delimiters |

After `m s` or `m r`, the new region (including delimiters) stays
selected so you can chain `m d` or `m r` immediately.

#### Custom Block Pairs

Add major-mode-specific block surround pairs via
`helixel-surround-block-alist`:

```elisp
(setq helixel-surround-block-alist
      '((org-mode
         (?s . ("#+begin_src " . "#+end_src"))
         (?e . ("#+begin_example " . "#+end_example"))
         (?q . ("#+begin_quote " . "#+end_quote")))
        (markdown-mode
         (?\` . ("```" . "```")))))
```

The first element of each entry is the key character pressed after
`m s`.  The second is `(OPEN-STRING . CLOSE-STRING)`.

### Search & Repeat

**`n` / `N`** — repeat search or find-char.  
**`C-u n` / `C-u N`** — pick from combined search/find-char history.

| Key | Context | Behavior |
|-----|---------|----------|
| `n` | After `/` or `?` | Repeat search forward |
| `N` | After `/` or `?` | Reverse direction then repeat |
| `n` | After `f`/`F`/`t`/`T` | Repeat find-char forward |
| `N` | After `f`/`F`/`t`/`T` | Reverse direction then repeat find-char |
| `C-u n` | anytime | Pick from combined history & execute |
| `C-u N` | anytime | Toggle direction + pick from history |

`N` flips the search direction; subsequent `n` continues in the new direction.

The history ring (`helixel--action-ring`) merges search regexps (`/ ? * #`)
and find-char entries (`f F t T`) into one list.  Entries appear as `/pattern/`
for searches, or `f→X` / `F→X` / `t→X` / `T→X` for find-char (case indicates
original direction: lowercase = forward, uppercase = backward).
Selecting a find-char entry replays it with `next`/`till` semantics.

- `C-u n` executes in the entry's stored direction.
- `C-u N` toggles the stored direction, then executes.
- When `N` or `C-u N` toggles the direction of the most recent entry,
  the ring entry is also flipped to reflect the new direction.
- Ring size is controlled by `helixel-action-ring-max` (default 50).

Examples:
```
/foo<RET>   search "foo"
n           next match forward
n           next match forward
N           reverse direction, go back to previous match
n           continue backward (next in reversed direction)

fb          find next "b"
n           find next "b" again
N           reverse direction, find previous "b"
n           continue backward

C-u n       pick a past search/find-char from history
```

### Session Mark (`;`)

`;` sets the mark at where a movement sequence started. Point stays
in place — the region shows where you came from. Same-type movements
share a session; different types start new ones.

| Key | Behavior |
|-----|----------|
| `;` | Set mark to start of current session (push live → ring, show ring[0]) |
| `;` again | Set mark to older session start |
| `;` again | Set mark further back ... |
| `C-u ;` | Set mark to newer session start |
| `C-u ;` (at newest) | Restore live session mark |

**Session types** (pressing `;` sets mark to independent start positions):

| Category | Session type | Keys |
|----------|-------------|------|
| char | `movement-char` | `h` `l` |
| line | `movement-line` | `j` `k` |
| word | `movement-word` | `w` `e` `b` |
| WORD | `movement-WORD` | `W` `E` `B` |
| symbol | `movement-symbol` | (unbound) |
| goto | `movement-goto` | `g` prefix, `G` |
| scroll | `movement-scroll` | `C-f` `C-b` |
| line select | `movement-lineselect` | `x` `X` |
| textobj-word | `textobj-word` | `miw` `maw` |
| textobj-WORD | `textobj-WORD` | `miW` `maW` |
| textobj-symbol | `textobj-symbol` | `mio` `mao` |
| textobj-sentence | `textobj-sentence` | `mis` `mas` |
| textobj-paragraph | `textobj-paragraph` | `mip` `map` |
| textobj-pair | `textobj-pair` | `mi(` `ma(` `mi[` `ma[` `mi{` `ma{` `mi<` `ma<` |
| textobj-quote | `textobj-quote` | `mi"` `ma"` `mi'` `ma'` ``mi` `` ``ma` `` |
| textobj-tag | `textobj-tag` | `mit` `mat` |
| search | `search` | `/` `?` `*` `#` then `n`/`N` |
| find-char | `find-char` | `f` `F` `t` `T` then `n`/`N`/`M-.` |

`C-g` cancels the current session — the next command starts a fresh session
even if the type matches. The cancelled session is preserved in the ring for
`;` to jump back to.

Examples:
```
w w         move forward two words
;           mark start of this w w session

j j         move down two lines
;           mark start of j j (NOT the w w start!)
;           again: mark start of w w
C-u ;       back to j j mark

f x         find char "x"
n           next "x"
n           next "x"
;           mark start of this find session

;           again: older session ...

w w         move two words (same session, shared start position)
C-g         cancel session — next command starts fresh
w           new session, new start position
;           mark start of this new w
;           again: mark start of the old w w
```

### Jump Navigation (`C-o` / `C-i`)

`C-o` jumps to older positions in the global jump list, `C-i` jumps to newer
ones.  Unlike `;` which only sets the mark, jump commands **move point** and
support **cross-buffer** navigation.

Every action recorded for `;` (movement, search, find-char, textobj, edit) is
also recorded in the jump list.  The same session types and group-skipping
logic apply.

| Key | Behavior |
|-----|----------|
| `C-o` | Jump to the previous (older) position, switching buffers if needed |
| `C-i` | Jump to the next (newer) position |
| `C-o` (at oldest) | "At oldest" — no more positions |
| `C-i` (at newest) | "At newest" — no more positions |

Cross-buffer: when a jump takes you to a different buffer, a return point is
automatically recorded so `C-i` brings you back.

#### Registering jump commands

External commands like `xref-find-definitions` (`g d`) automatically register
their start position via advice.  To register your own commands:

```elisp
;; Method 1: one line — adds :before advice
(helixel-define-jump-command 'my-goto-command)

;; Method 2: call from inside your command body
(defun my-command ()
  (interactive)
  (helixel-register-jump 'goto 'my-cmd)
  ...)
```

#### Configuration

```elisp
;; Max entries in the global jump list (default 100)
(setq helixel-jump-list-max 200)

;; Categories that are recorded (default: all)
(setq helixel-jump-categories '(movement search find-char edit goto))

;; Categories visible during C-o / C-i cycling (default: same as above)
;; Narrow this to exclude basic movements for a tighter jumplist:
(setq helixel-jump-cycle-categories '(search find-char edit goto))
```

### Ex Commands

`:w` write, `:q` quit, `:wq` write-quit, `:o` open file, `:n` scratch buffer, `:vs` vsplit, `:hs` hsplit, `:rl` reload buffer, `:reload-all` reload all, `:pwd` show directory, `:config-open` open init.el.

## Extend

```elisp
;; Add a keybinding
(helixel-define-key 'space "w" #'my-command)

;; Add a typable command
(helixel-define-ex-command "format" #'format-all-buffer)

;; Wrap a builtin movement with session tracking (supports ;)
(helixel-define-movement helixel-forward-paragraph forward-paragraph movement-goto)
(helixel-define-key 'normal "]" #'helixel-forward-paragraph)
```

### Custom Text Object

Define a new thing-based text object (e.g. Go package names
like `github.com/foo/bar`):

```elisp
(require 'thingatpt)

;; 1. Define the character set for the thing
(define-thing-chars gopkg "-/[:alnum:]_.@:*")

;; 2. Set forward-op so forward-thing knows how to move
(put 'gopkg 'forward-op
     (lambda (&optional count)
       (helixel-forward-chars "-/[:alnum:]_.@:*" count)))

;; 3. Define inner / a text-object commands
(helixel-define-mark-object "gopkg" 'gopkg "gopkg" 'gopkg t)

;; 4. Bind to a key (replaces the default paragraph binding)
(define-key helixel-textobj-inner-map "p" #'helixel-mark-inner-gopkg)
(define-key helixel-textobj-outer-map "p" #'helixel-mark-a-gopkg)
```

`mi p` now selects the inner Go package path at point;
`ma p` selects it plus surrounding whitespace.

### Regex Text Objects

Define text objects delimited by arbitrary regexp patterns — useful for
org blocks, markdown fences, LaTeX environments, etc.:

```elisp
;; Org mode #+begin_src / #+end_src blocks (match by name group)
(helixel-define-regex-textobj org-block
  "^#\\+begin_\\([^ \n\r]+\\)[^\n]*"
  "^#\\+end_\\([^ \n\r]+\\)[^\n]*" 1 'block)

;; Global binding (all modes)
(define-key helixel-textobj-inner-map "o" #'helixel-mark-inner-org-block)
(define-key helixel-textobj-outer-map "o" #'helixel-mark-a-org-block)

;; Or mode-specific (org-mode only):
(helixel-define-key 'textobj-inner "o"
  #'helixel-mark-inner-org-block 'org-mode)
(helixel-define-key 'textobj-outer "o"
  #'helixel-mark-a-org-block 'org-mode)

;; Markdown ``` fences (counter-based: name-group nil)
(helixel-define-regex-textobj md-fence
  "^```[^\n]*$" "^```[ \t]*$" nil 'block)
(define-key helixel-textobj-inner-map "`" #'helixel-mark-inner-md-fence)
(define-key helixel-textobj-outer-map "`" #'helixel-mark-a-md-fence)

;; LaTeX \\begin{env} / \\end{env} (capture group 1 = environment name)
(helixel-define-regex-textobj latex-env
  "\\\\begin{\\([^}]+\\)}" "\\\\end{\\([^}]+\\)}" 1 'block)
(define-key helixel-textobj-inner-map "e" #'helixel-mark-inner-latex-env)
(define-key helixel-textobj-outer-map "e" #'helixel-mark-a-latex-env)
```

Arguments: `(NAME BEGIN-RE END-RE &optional NAME-GROUP SUBCAT)`.

- **NAME**: an unquoted symbol for the command suffix (e.g. `org-block` → `helixel-mark-inner-org-block`)
- **BEGIN-RE** / **END-RE**: regexps matching the opening/closing delimiter lines
- **NAME-GROUP**: if an integer, that capture group in both regexps must match (name-based balancing). Use `nil` for counter-based balancing (e.g. markdown fences)
- **SUBCAT**: subcategory symbol for `;` session grouping (default `'block`)

### Tree-sitter Text Objects

Requires [evil-textobj-tree-sitter](https://github.com/meain/evil-textobj-tree-sitter)
as a soft dependency.  If installed, you can define syntax-aware text objects
(function, class, loop, conditional, parameter, comment, etc.):

```elisp
(define-key helixel-textobj-inner-map "f"
  (helixel-get-tree-sitter-textobj "function.inner"))
(define-key helixel-textobj-outer-map "f"
  (helixel-get-tree-sitter-textobj "function.outer"))
(define-key helixel-textobj-inner-map "a"
  (helixel-get-tree-sitter-textobj "parameter.inner"))
(define-key helixel-textobj-outer-map "a"
  (helixel-get-tree-sitter-textobj "parameter.outer"))
```

If `evil-textobj-tree-sitter` is not installed, the function returns nil
and the bindings are silently ignored.

You can also pass a custom query alist mapping major-modes to tree-sitter
queries for user-defined text objects:

```elisp
(define-key helixel-textobj-outer-map "m"
  (helixel-get-tree-sitter-textobj "import"
    '((python-mode . "((import_statement) @import)")
      (python-ts-mode . "((import_statement) @import)")
      (rust-mode . "((use_declaration) @import)"))))
```

