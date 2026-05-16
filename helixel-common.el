;;; helixel-common.el --- Core engine and keymaps  -*- lexical-binding: t; -*-

;; Copyright (C) 2025  jixiuf

;; Author: jixiuf
;; Keywords: convenience
;; URL: https://github.com/jixiuf/helixel-mode

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Core engine for helixel-mode.
;;
;; Provides the modal state machine, all keymaps, movement commands,
;; editing operations (kill, yank, paste, replace), search, character
;; find, LSP/project integration, colon commands, and the global minor
;; mode toggle.

;;; Code:

(require 'cl-lib)
(require 'flymake)
(require 'eglot)
(require 'rect)
(require 'helixel-action)
(require 'helixel-textobj)
(require 'helixel-repeat)

(declare-function helixel-surround-add "helixel-surround")
(declare-function helixel-surround-add-tag "helixel-surround")
(declare-function helixel-surround-delete "helixel-surround")
(declare-function helixel-surround-replace "helixel-surround")
(declare-function helixel-search--search "helixel-search")


(defcustom helixel-major-mode-default-states
  '((calc-mode . insert)
    (Custom-mode . normal))
  "Alist mapping major modes to default Helixel states.
Each element should be a cons cell (MAJOR-MODE . STATE), where
MAJOR-MODE is a symbol like `dired-mode', and STATE is one of
`normal', `motion' or `insert'.
When `helixel-mode' is activated in a buffer, the state is chosen by
looking up the current major mode in this alist, falling back to guess
based on key bindings: if letters a-z are bound to self-insert commands,
use `normal', otherwise `motion'."
  :type '(alist :key-type symbol :value-type
                (choice (const normal) (const motion) (const insert)))
  :group 'helixel)

(defcustom helixel-replace-delete-char-p nil
  "When non-nil, delete char at point before inserting yanked text.
When no region is active, this controls whether to replace the char
at point (t) or simply insert without deleting (nil)."
  :type 'boolean
  :group 'helixel)


(defvar-local helixel--current-state 'normal
  "Current modal state, one of normal, insert, or motion.")


(defvar helixel-state-alist
  `((insert . helixel-insert-state)
    (normal . helixel-normal-state)
    (visual . helixel-visual-state)
    (motion . helixel-motion-state))
  "Alist of symbol state name to minor mode.")

(defvar-local helixel--selection-type nil
  "Current selection type.
nil means charwise, `line' means linewise, `rect' means rectangle.")

(defvar-local helixel--rect-replay-data nil
  "Plist for rect change replay: (:col N :line-count N).")

(defvar-local helixel--rect-replay-marker nil
  "Marker at insertion point before entering insert for rect change.")

(defvar helixel-global-mode nil
  "Enable Helixel mode in all buffers.")

;; Forward declaration - defined later with keymap initializers
(defvar helixel-state-map-alist)

(defvar helixel--mode-keybindings nil
  "Alist of ((MODE . STATE) . sparse-keymap).
MODE is a major or minor mode symbol.  STATE is a helixel state symbol.
Stores mode-specific helixel bindings registered via `helixel-define-key'.")

;; ── Command definition macro ──
;;
;; All helixel commands use `helixel-define-command' to declare their
;; action metadata.  Tracking code (action-start, direction, edit
;; recording, highlight clearing, visual-mode tracking) is expanded
;; inline at compile time — zero hooks, zero advice.

(defmacro helixel-define-command (name metadata &rest body)
  "Define a helixel command NAME with METADATA auto-tracking.

METADATA is a plist:
  :category      CAT  — action category (movement, edit, search, state, etc.)
  :subcat        SUB  — action subcategory (word, kill, insert, etc.)
  :dir           DIR  — direction for n/N repeat context (forward, backward)
  :edit-op       OP   — calls (helixel--record-edit OP)
  :clear-highlights    — default t for :category movement, nil otherwise
  :params        PARAM-LIST  — optional function parameter list
                                (e.g., (&optional count))

All tracking code is expanded inline at compile time — zero hooks,
zero advice.
BODY is the command's business logic.
If the body begins with (interactive ...), that form is extracted and placed
before the tracking code; otherwise (interactive) is inserted automatically."
  (declare (indent 2))
  (let* ((cat (plist-get metadata :category))
         (sub (plist-get metadata :subcat))
         (dir (plist-get metadata :dir))
         (op  (plist-get metadata :edit-op))
         (clear (if (plist-member metadata :clear-highlights)
                    (plist-get metadata :clear-highlights)
                  (eq cat 'movement)))
         (has-interactive (and (consp (car body))
                               (eq (caar body) 'interactive)))
         (interactive-form (if has-interactive (car body) '(interactive)))
         (rest-body (if has-interactive (cdr body) body))
         (params (plist-get metadata :params))
         (track-visual
          (when (eq cat 'movement)
            `((when (eq helixel--current-state 'visual)
                (helixel--track-visual-move ',name))))))
    `(defun ,name ,(or params ())
       ,(format "Helixel %s.%s command." cat sub)
       ,interactive-form
       ;; ── Action tracking (for ; and C-o/C-i) ──
       (helixel-action-start ',cat ',sub)
       ;; ── Direction (for n/N repeat) ──
       ,@(when dir `((helixel--live-cat-set-dir ',dir)))
       ;; ── Edit recording (for . repeat) ──
       ,@(when op  `((helixel--record-edit ',op)))
       ;; ── Highlight clearing ──
       ,@(when clear '((helixel--clear-highlights)))
       ;; ── Body (pure business logic) ──
       ,@rest-body
       ;; ── Visual-mode tracking (for . replay of movements) ──
       ;; Only movement commands accumulate moves; edit commands
       ;; record the accumulated moves via `helixel--record-edit'.
       ,@track-visual)))

;; Wire textobj hooks for action recording and visual state detection.
(setq helixel-textobj-action-function #'helixel-action-start)
(setq helixel-textobj-visual-state-p-function
      (lambda () (eq helixel--current-state 'visual)))
(setq helixel-jump-cleanup-function #'helixel--clear-data)
(add-hook 'helixel-action-push-functions #'helixel--jump-list-push)

(defun helixel--unload-current-state ()
  "Deactivate the minor mode described by `helixel--current-state'."
  (let ((mode (alist-get helixel--current-state helixel-state-alist)))
    (funcall mode -1)))

(defun helixel--switch-state (state)
  "Switch to STATE."
  (unless (eq state helixel--current-state)
    (helixel--unload-current-state)
    (helixel--clear-data)
    (setq-local helixel--current-state state)
    (let ((mode (alist-get state helixel-state-alist)))
      (funcall mode 1))
    (helixel--refresh-overriding-maps)))

(defun helixel--clear-data ()
  "Clear any intermediate data, e.g. selections/mark."
  (setq helixel--selection-type nil)
  (when rectangle-mark-mode
    (rectangle-mark-mode -1))
  (deactivate-mark))

(defun helixel--track-visual-move (cmd)
  "Append movement CMD to `helixel--repeat-sel-ctx' for visual-mode moves.
Creates/updates a `helixel-sel' struct of kind `movement'.
No-op during dot-repeat replay."
  (when (and (eq helixel--current-state 'visual)
             (not helixel--inhibit-repeat-record))
    (let ((ctx helixel--repeat-sel-ctx)
          (entry (cons cmd 1)))
      (if (and ctx (eq (helixel-sel-get-kind ctx) 'movement))
          (let* ((moves (helixel-sel-movement-moves ctx))
                 (last (car moves)))
            (if (and last (eq (car last) cmd))
                (setcdr last (1+ (cdr last)))
              (setq helixel--repeat-sel-ctx
                    (helixel-sel-update-ctx ctx :moves
                                            (cons entry moves)))))
        (setq helixel--repeat-sel-ctx
              (helixel-sel-create 'movement
                                  `(:moves (,entry))
                                  #'helixel--recreate-movement
                                  (lambda (c)
                                    (let ((ms (helixel-sel-movement-moves c)))
                                      (let ((n (apply #'+ (mapcar #'cdr ms))))
                                        (format "v%d" n))))))))))

(defun helixel--enter-insert ()
  "Enter insert mode, recording buffer changes via the change hooks.
Sets up change-hook recording and switches to insert state."
  (helixel--insert-begin)
  (helixel--switch-state 'insert))

(helixel-define-command helixel-insert
    (:category state :subcat insert)
  (cond
   ;; Search context: refine the search sel with entry-kind
   ((and helixel--repeat-sel-ctx
         (eq (helixel-sel-get-kind helixel--repeat-sel-ctx) 'search))
    (setq helixel--repeat-sel-ctx
          (helixel-sel-update-ctx helixel--repeat-sel-ctx
                                  :entry-kind 'insert))
    (goto-char (region-beginning)))
   ;; Line selection: preserve sel for `.` auto-advance
   ((and helixel--repeat-sel-ctx
         (eq (helixel-sel-get-kind helixel--repeat-sel-ctx) 'line))
    (setq helixel--repeat-sel-ctx
          (helixel-sel-update-ctx helixel--repeat-sel-ctx
                                  :entry-kind 'insert))
    (goto-char (region-beginning)))
   ;; Manual region
   ((use-region-p)
    (setq helixel--repeat-sel-ctx
          (helixel-sel-create
           'insert-selection-start nil
           #'helixel--recreate-insert-selection-start "is"))
    (goto-char (region-beginning)))
   ;; No context
   (t
    (setq helixel--repeat-sel-ctx nil)))
  (helixel--record-edit 'insert-text)
  (setq helixel--change-track-marker (point-marker))
  (helixel--enter-insert))

(helixel-define-command helixel-insert-exit
    (:category state :subcat exit)
  (let* ((result (helixel--insert-finish))
         (keys (car result))
         (commands (cdr result))
         (text (when helixel--change-track-marker
                 (and (marker-position helixel--change-track-marker)
                      (buffer-substring
                       helixel--change-track-marker (point))))))
    ;; Store kmacro keys as primary replay mechanism
    (when keys
      (setq helixel--last-tx
            (helixel-edit-with-payload helixel--last-tx :keys keys)))
    ;; Store executed commands (keymap-independent replay)
    (when commands
      (setq helixel--last-tx
            (helixel-edit-with-payload helixel--last-tx :commands
                                       commands)))
    ;; Store text as replay fallback (tests, programmatic use)
    (when text
      (setq helixel--last-tx
            (helixel-edit-with-payload helixel--last-tx :text text))
      ;; For change operations, same text as :inserted-text
      (when (eq (helixel-edit-op helixel--last-tx) 'change)
        (setq helixel--last-tx
              (helixel-edit-with-payload helixel--last-tx
                                         :inserted-text text))))
    ;; Cleanup
    (when helixel--change-track-marker
      (set-marker helixel--change-track-marker nil)
      (setq helixel--change-track-marker nil))
    ;; Sync ring head
    (when (and helixel--edit-ring helixel--last-tx)
      (setcar helixel--edit-ring helixel--last-tx))
    ;; Rect replay
    (when helixel--rect-replay-data
      (helixel--rect-replay))
    ;; Switch state
    (let ((state (helixel--default-state-for-buffer)))
      (when (eq state 'insert)
        (setq state 'normal))
      (helixel--switch-state state))))

(defun helixel--clear-highlights ()
  "Clear any active highlight, unless in visual state.
Also preserve highlights when `rectangle-mark-mode' is active."
  (unless (or (eq helixel--current-state 'visual) rectangle-mark-mode)
    (deactivate-mark)))

(defmacro helixel-define-movement (name builtin type &rest options)
  "Define a movement command NAME wrapping BUILTIN with TYPE.

OPTIONS is a plist supporting:
  :dir DIR             — direction, e.g. :dir forward
  :advice              — inject :before advice instead of creating wrapper
  :clear-highlights BOOL — clear highlights before executing (default t)

Wrapper mode (default): delegates to `helixel-define-command'.
  (helixel-define-movement helixel-forward-char forward-char char :dir forward)

Advice mode:
  (helixel-define-movement nil forward-char char :dir forward :advice)

Without highlights clearing:
  (helixel-define-movement helixel-scroll-up scroll-up-command scroll
                        :clear-highlights nil)"
  (declare (indent 1))
  (let* ((dir (plist-get options :dir))
         (advicep (plist-get options :advice))
         (clear (if (plist-member options :clear-highlights)
                    (plist-get options :clear-highlights)
                  t)))
    (if advicep
        `(advice-add #',builtin :before
                     (lambda (&rest _)
                       ,(format "Helixel %s movement advice." type)
                       (helixel-action-start 'movement ',type)
                       ,(when dir
                          `(helixel--live-cat-set-dir ',dir))
                       ,@(when clear
                           '((helixel--clear-highlights)))))
      `(helixel-define-command ,name
           (:category movement :subcat ,type :dir ,dir
                      :clear-highlights ,clear)
         (call-interactively #',builtin)))))

(defmacro helixel-define-movements (&rest specs)
  "Register multiple movements from SPECS.
Each element of SPECS is a list of args for `helixel-define-movement'.

Example:
  (helixel-define-movements
    (helixel-forward-char forward-char char :dir forward)
    (helixel-next-line next-line line :dir forward))"
  `(progn
     ,@(mapcar (lambda (s) `(helixel-define-movement ,@s)) specs)))

;; ── Simple movement wrappers ──
;; Generated by helixel-define-movement for builtin commands that only need
;; action tracking + highlight clearing + call-interactively.

(helixel-define-movement helixel-backward-char backward-char char :dir backward)
(helixel-define-movement helixel-forward-char forward-char char :dir forward)
(helixel-define-movement helixel-next-line next-line line :dir forward)
(helixel-define-movement helixel-previous-line previous-line line :dir backward)
(helixel-define-movement helixel-go-beginning-line beginning-of-line goto)
(helixel-define-movement helixel-go-end-line end-of-line goto)
(helixel-define-movement helixel-go-first-nonwhitespace
  back-to-indentation goto)
(helixel-define-movement helixel-go-end-buffer end-of-buffer goto)
(helixel-define-movement helixel-scroll-up-command scroll-up-command scroll
                         :clear-highlights nil)
(helixel-define-movement helixel-scroll-down-command scroll-down-command scroll
                         :clear-highlights nil)

(defun helixel-surround-thing-at-point (&optional thing)
  "Construct a region around THING at point.

Argument THING must be one of the things identified by the package
thingatpt.  Defaults to \\='word."
  (let ((bounds (bounds-of-thing-at-point (or thing 'word))))
    (when bounds
      (set-mark (car bounds))
      (goto-char (cdr bounds))
      (activate-mark))))
(defmacro helixel--with-movement-surround (&rest body)
  "Create a region around movement defined in BODY.
If a region is already active, no new region is created.

Note: `helixel-define-command' handles `clear-highlights'
and `track-visual-move'
automatically, so this macro only does `push-mark' + activate."
  `(let ((current (point)))
     ,@body
     (unless (use-region-p)
       (push-mark current t 'activate))))

(helixel-define-command helixel-forward-word-start
    (:category movement :subcat word :dir forward)
  (helixel--with-movement-surround
   (helixel--forward-beginning 'helixel-word)))

(helixel-define-command helixel-forward-word-end
    (:category movement :subcat word :dir forward)
  (helixel--with-movement-surround
   (helixel--forward-end 'helixel-word)))

(helixel-define-command helixel-backward-word-start
    (:category movement :subcat word :dir backward)
  (helixel--with-movement-surround
   (helixel--forward-beginning 'helixel-word -1)))

(helixel-define-command helixel-backward-word-end
    (:category movement :subcat word :dir backward)
  (helixel--with-movement-surround
   (helixel--forward-end 'helixel-word -1)))

(helixel-define-command helixel-forward-WORD-start
    (:category movement :subcat WORD :dir forward)
  (helixel--with-movement-surround
   (helixel--forward-beginning 'helixel-WORD)))

(helixel-define-command helixel-forward-WORD-end
    (:category movement :subcat WORD :dir forward)
  (helixel--with-movement-surround
   (helixel--forward-end 'helixel-WORD)))

(helixel-define-command helixel-backward-WORD
    (:category movement :subcat WORD :dir backward)
  (helixel--with-movement-surround
   (helixel--forward-beginning 'helixel-WORD -1)))


(helixel-define-command helixel-backward-WORD-end
    (:category movement :subcat WORD :dir backward)
  (helixel--with-movement-surround
   (helixel--forward-end 'helixel-WORD -1)))

(helixel-define-command helixel-forward-symbol-start
    (:category movement :subcat symbol :dir forward)
  (helixel--with-movement-surround
   (helixel--forward-beginning 'helixel-symbol)))

(helixel-define-command helixel-forward-symbol-end
    (:category movement :subcat symbol :dir forward)
  (helixel--with-movement-surround
   (helixel--forward-end 'helixel-symbol)))

(helixel-define-command helixel-backward-symbol-start
    (:category movement :subcat symbol :dir backward)
  (helixel--with-movement-surround
   (helixel--forward-beginning 'helixel-symbol -1)))

(helixel-define-command helixel-backward-symbol-end
    (:category movement :subcat symbol :dir backward)
  (helixel--with-movement-surround
   (helixel--forward-end 'helixel-symbol -1)))

(helixel-define-command helixel-go-beginning-buffer
    (:category movement :subcat goto)
  (if current-prefix-arg
      (goto-line (prefix-numeric-value current-prefix-arg))
    (call-interactively #'beginning-of-buffer)))

(helixel-define-command helixel-goto-line
    (:category movement :subcat goto :params (&optional arg))
  (interactive "P")
  (goto-line (if arg
                 (prefix-numeric-value arg)
               (goto-line-read-args))))


(helixel-define-command helixel-select-line
    (:category movement :subcat lineselect :dir forward
               :params (&optional count) :clear-highlights nil)
  (interactive "p")
  (let ((n (or count 1))
        (extending (and (region-active-p) (eolp)))
        (current-prefix-arg nil))
    (if extending
        (dotimes (_ n)
          (call-interactively #'next-line)
          (end-of-line))
      (beginning-of-line)
      (push-mark-command t t)
      (end-of-line)
      (dotimes (_ (1- n))
        (call-interactively #'next-line)
        (end-of-line)))
    (setq helixel--selection-type 'line)
    (let* ((prev-count (helixel-sel-count helixel--repeat-sel-ctx))
           (new-count (if extending (+ prev-count n) n)))
      (setq helixel--repeat-sel-ctx
            (helixel-sel-create 'line `(:dir forward :count ,new-count)
                                #'helixel--recreate-line
                                (if (> new-count 1)
                                    (format "Lx%d" new-count)
                                  "L"))))))

(helixel-define-command helixel-select-line-up
    (:category movement :subcat lineselect :dir backward
               :params (&optional count) :clear-highlights nil)
  (interactive "p")
  (let ((n (or count 1))
        (extending (and (region-active-p) (bolp)))
        (current-prefix-arg nil))
    (if extending
        (dotimes (_ n)
          (call-interactively #'previous-line)
          (beginning-of-line))
      (end-of-line)
      (push-mark-command t t)
      (beginning-of-line)
      (dotimes (_ (1- n))
        (call-interactively #'previous-line)
        (beginning-of-line)))
    (setq helixel--selection-type 'line)
    (let* ((prev-count (helixel-sel-count helixel--repeat-sel-ctx))
           (new-count (if extending (+ prev-count n) n)))
      (setq helixel--repeat-sel-ctx
            (helixel-sel-create 'line `(:dir backward :count ,new-count)
                                #'helixel--recreate-line
                                (if (> new-count 1)
                                    (format "L^x%d" new-count)
                                  "L^"))))))

(helixel-define-command helixel-select-rectangle
    (:category movement :subcat rectselect
               :params (&optional count) :clear-highlights nil)
  (interactive "p")
  (let ((n (or count 1))
        (extending rectangle-mark-mode)
        (current-prefix-arg nil))
    (if extending
        (dotimes (_ n)
          (if (or (> (point) (mark))
                  (and (= (point) (mark))
                       (eq last-command 'helixel-select-rectangle)))
              (forward-line 1)
            (forward-line -1))
          (rectangle--reset-point-crutches))
      (helixel--switch-state 'visual)
      (push-mark (point) t t)
      (rectangle-mark-mode 1)
      (dotimes (_ (1- n))
        (forward-line 1)
        (rectangle--reset-point-crutches)))
    (setq helixel--selection-type 'rect)
    (let* ((prev-count (helixel-sel-count helixel--repeat-sel-ctx))
           (new-count (if extending (+ prev-count n) n)))
      (setq helixel--repeat-sel-ctx
            (helixel-sel-create 'rect `(:count ,new-count)
                                #'helixel--recreate-rect
                                (if (> new-count 1)
                                    (format "rx%d" new-count)
                                  "r"))))))

;;; Line-wise helpers

(defun helixel--selection-type ()
  "Return current selection type, or nil.
Validates that the region actually matches the claimed type.
Supports `line' and `rect'."
  (when (region-active-p)
    (cond
     ((eq helixel--selection-type 'rect)
      (when rectangle-mark-mode 'rect))
     ((eq helixel--selection-type 'line)
      (let ((beg (region-beginning))
            (end (region-end)))
        (when (and (save-excursion (goto-char beg) (bolp))
                   (save-excursion (goto-char end) (or (eolp) (eobp))))
          'line)))
     ((eq helixel--selection-type 'textobj)
      'textobj))))

(defun helixel--yank-handler-line-wise (text)
  "Insert TEXT as a complete line.
Dispatches on `this-command' to decide insertion position."
  (cond
   ((member this-command '(helixel-yank helixel-replace))
    (end-of-line)
    (newline)
    (insert (string-trim-right text "\n"))
    (beginning-of-line)
    (back-to-indentation))
   ((eq this-command 'helixel-yank-before)
    (beginning-of-line)
    (save-excursion
      (insert text)
      (unless (bolp) (newline)))
    (back-to-indentation))
   (t
    (insert text))))

(defun helixel--linewise-text (text)
  "Return a copy of TEXT propertized with line-wise yank-handler.
Ensures TEXT ends with a newline."
  (let ((s (if (and (> (length text) 0)
                    (/= (aref text (1- (length text))) ?\n))
               (concat text "\n")
             text)))
    (propertize s 'yank-handler '(helixel--yank-handler-line-wise nil t))))

(defun helixel--linewise-kill-p (&optional text)
  "Return non-nil if TEXT (default: top of kill ring) was killed line-wise."
  (when-let* ((s (or text (and kill-ring (current-kill 0 t)))))
    (eq (car-safe (get-text-property 0 'yank-handler s))
        'helixel--yank-handler-line-wise)))

(defun helixel--line-bounds-of-region ()
  "Return (BEG . END) expanded to full line boundaries.
BEG is at bol of `region-beginning', END includes the trailing newline."
  (when (use-region-p)
    (let ((beg (save-excursion (goto-char (region-beginning)) (pos-bol)))
          (end (save-excursion (goto-char (region-end))
                               (if (bolp) (point)
                                 (min (1+ (pos-eol)) (point-max))))))
      (cons beg end))))

;;; Rect-wise helpers

(defun helixel--yank-handler-rect-wise (lines)
  "Insert LINES as a rectangle at point."
  (insert-rectangle lines))

(defun helixel--rect-wise-text (strings)
  "Return a propertized string from STRINGS, a list of rect lines.
Tags the text with a rect-wise yank-handler for proper pasting."
  (let ((text (mapconcat #'identity strings "\n")))
    (propertize text 'yank-handler
                (list 'helixel--yank-handler-rect-wise strings t))))

(defun helixel--rect-wise-kill-p (&optional text)
  "Return non-nil if TEXT was killed as a rectangle."
  (when-let* ((s (or text (and kill-ring (current-kill 0 t)))))
    (eq (car-safe (get-text-property 0 'yank-handler s))
        'helixel--yank-handler-rect-wise)))

(defun helixel--rect-bounds-of-region ()
  "Return the rectangle bounds as a list of cons cells (BEG . END).
One per line of the rectangle."
  (when (and (use-region-p) rectangle-mark-mode)
    (extract-rectangle-bounds (region-beginning) (region-end))))

;;; Rect change with replay

(defun helixel--rect-change ()
  "Kill rectangle content, enter insert mode.
Replay typed text on all rectangle lines."
  (let* ((beg (region-beginning))
         (end (region-end))
         (line-count (count-lines beg end))
         (col (save-excursion (goto-char beg) (current-column)))
         (lines (extract-rectangle beg end)))
    (delete-rectangle beg end)
    (kill-new (helixel--rect-wise-text lines))
    (goto-char beg)
    (setq helixel--rect-replay-marker (point-marker))
    (setq helixel--rect-replay-data `(:col ,col :line-count ,line-count))
    (helixel--enter-insert)))

(defun helixel--rect-replay ()
  "Replay inserted text from rect change on remaining rectangle lines."
  (when (and helixel--rect-replay-data helixel--rect-replay-marker)
    (let* ((col (plist-get helixel--rect-replay-data :col))
           (line-count (plist-get helixel--rect-replay-data :line-count))
           (text (buffer-substring helixel--rect-replay-marker (point))))
      (save-excursion
        (dotimes (_ (1- line-count))
          (forward-line 1)
          (move-to-column col t)
          (insert text)))
      (setq helixel--rect-replay-data nil)
      (when helixel--rect-replay-marker
        (set-marker helixel--rect-replay-marker nil)
        (setq helixel--rect-replay-marker nil)))))

(defun helixel--delete-selection ()
  "Delete current region or char at point, pushing to `kill-ring'.
Does NOT record an edit and does NOT clear selection data.
Used as the shared kill core by `helixel-kill-thing-at-point',
`helixel-change-thing-at-point', and `helixel--repeat-change-core'."
  (cond
   ((not (use-region-p))
    (delete-char 1))
   ((eq (helixel--selection-type) 'rect)
    (let ((lines (extract-rectangle (region-beginning) (region-end))))
      (delete-rectangle (region-beginning) (region-end))
      (kill-new (helixel--rect-wise-text lines))))
   ((eq (helixel--selection-type) 'line)
    (if-let* ((bounds (helixel--line-bounds-of-region))
              (text (filter-buffer-substring (car bounds) (cdr bounds))))
        (progn
          (kill-new (helixel--linewise-text text))
          (delete-region (car bounds) (cdr bounds)))))
   (t
    (when (and (eolp) (<= (region-beginning) (pos-bol)))
      (forward-visible-line 1))
    (kill-region (region-beginning) (region-end)))))

(helixel-define-command helixel-kill-thing-at-point
    (:category edit :subcat kill :edit-op kill)
  (helixel--delete-selection)
  (helixel--clear-data))

(helixel-define-command helixel-change-thing-at-point
    (:category edit :subcat change :edit-op change)
  (if (and (use-region-p) (eq (helixel--selection-type) 'rect))
      (helixel--rect-change)
    (helixel--delete-selection)
    (setq helixel--change-track-marker (point-marker))
    (helixel--enter-insert)))

(defun helixel-visual-exit ()
  "Exit visual state and return to normal state."
  (interactive)
  (helixel--switch-state (helixel--default-state-for-buffer)))

(defun helixel-begin-selection ()
  "Begin visual selection or exit visual state."
  (interactive)
  (if (eq helixel--current-state 'visual)
      (helixel-visual-exit)
    (when rectangle-mark-mode
      (rectangle-mark-mode -1))
    (helixel--switch-state 'visual)
    (setq helixel--selection-type nil)
    (push-mark-command t t)))

(defun helixel--end-of-line-p ()
  "Return non-nil if current point is at the end of the current line."
  (save-excursion
    (let ((cur (point))
          eol)
      (end-of-line)
      (setq eol (point))
      (= cur eol))))

(helixel-define-command helixel-insert-after
    (:category state :subcat insert)
  (cond
   ;; Search context: refine the search sel with entry-kind
   ((and helixel--repeat-sel-ctx
         (eq (helixel-sel-get-kind helixel--repeat-sel-ctx) 'search))
    (setq helixel--repeat-sel-ctx
          (helixel-sel-update-ctx helixel--repeat-sel-ctx
                                  :entry-kind 'append))
    (goto-char (region-end)))
   ;; Line selection: preserve sel for `.` auto-advance
   ((and helixel--repeat-sel-ctx
         (eq (helixel-sel-get-kind helixel--repeat-sel-ctx) 'line))
    (setq helixel--repeat-sel-ctx
          (helixel-sel-update-ctx helixel--repeat-sel-ctx
                                  :entry-kind 'append))
    (goto-char (region-end)))
   ;; Manual region
   ((use-region-p)
    (setq helixel--repeat-sel-ctx
          (helixel-sel-create
           'insert-selection-end nil
           #'helixel--recreate-insert-selection-end "ie"))
    (goto-char (region-end)))
   ;; No context
   (t
    (unless (helixel--end-of-line-p)
      (forward-char))
    (setq helixel--repeat-sel-ctx nil)))
  (helixel--record-edit 'insert-text)
  (setq helixel--change-track-marker (point-marker))
  (helixel--enter-insert))

(helixel-define-command helixel-insert-beginning-line
    (:category state :subcat insert)
  (beginning-of-line)
  (setq helixel--repeat-sel-ctx
        (helixel-sel-create
         'insert-beginning-line nil
         #'helixel--recreate-insert-beginning-line "I"))
  (helixel--record-edit 'insert-text)
  (setq helixel--change-track-marker (point-marker))
  (helixel--enter-insert))

(helixel-define-command helixel-insert-after-end-line
    (:category state :subcat insert)
  (end-of-line)
  (setq helixel--repeat-sel-ctx
        (helixel-sel-create
         'insert-end-line nil
         #'helixel--recreate-insert-end-line "A"))
  (helixel--record-edit 'insert-text)
  (setq helixel--change-track-marker (point-marker))
  (helixel--enter-insert))

(helixel-define-command helixel-insert-newline
    (:category state :subcat insert :edit-op insert-text)
  (helixel--clear-data)
  (end-of-line)
  (newline-and-indent)
  (setq helixel--change-track-marker (point-marker))
  (helixel--enter-insert))

(helixel-define-command helixel-insert-prevline
    (:category state :subcat insert :edit-op insert-text)
  (helixel--clear-data)
  (beginning-of-line)
  (let ((electric-indent-mode nil))
    (newline nil t)
    (call-interactively #'previous-line)
    (indent-according-to-mode))
  (setq helixel--change-track-marker (point-marker))
  (helixel--enter-insert))

(defun helixel--replace-region (start end text)
  "Replace region from START to END in-place with TEXT."
  (delete-region start end)
  (insert text)
  (helixel--clear-data))

(defun helixel-replace-char (char)
  "Replace selection with CHAR.
If no region is active, replace character at point."
  (interactive "c")
  (helixel-action-start 'edit 'replace-char)
  (helixel--record-edit 'replace-char :char char)
  (if (use-region-p)
      (helixel--replace-region
       (region-beginning) (region-end)
       (make-string (- (region-end) (region-beginning)) char))
    (helixel--replace-region (point) (1+ (point)) char)))

(helixel-define-command helixel-replace
    (:category edit :subcat replace :edit-op replace)
  (if (= 0 (length kill-ring))
      (message "nothing to yank")
    (let* ((text (current-kill 0 t))
           (linewise-p (helixel--linewise-kill-p text))
           (rectwise-p (helixel--rect-wise-kill-p text))
           (bare (string-trim-right (substring-no-properties text) "\n"))
           (_bare-rect (unless (or linewise-p rectwise-p) bare)))
      (cond
       ;; Rect selection
       ((and (use-region-p) (eq (helixel--selection-type) 'rect))
        (let* ((beg (region-beginning))
               (end (region-end))
               (lines (nth 1 (get-text-property 0 'yank-handler text))))
          (delete-rectangle beg end)
          (goto-char beg)
          (if (and rectwise-p lines)
              (insert-rectangle lines)
            (insert bare))))
       ;; Line-wise selection: expand to full line bounds
       ((and (use-region-p) (eq (helixel--selection-type) 'line))
        (when-let* ((bounds (helixel--line-bounds-of-region)))
          (delete-region (car bounds) (cdr bounds))
          (insert (if linewise-p text (concat bare "\n")))))
       ;; Charwise region
       ((use-region-p)
        (delete-region (region-beginning) (region-end))
        (insert (if (or linewise-p rectwise-p)
                    bare
                  (substring-no-properties text))))
       ;; No region — replace char at point
       (t
        (when helixel-replace-delete-char-p
          (delete-char 1))
        (let ((helixel--inhibit-repeat-record t))
          (helixel-yank))))
      (helixel--clear-data))))

(helixel-define-command helixel-kill-ring-save
    (:category edit :subcat copy :edit-op copy)
  (when (use-region-p)
    (cond
     ((eq (helixel--selection-type) 'rect)
      (let ((lines (extract-rectangle (region-beginning) (region-end))))
        (kill-new (helixel--rect-wise-text lines))))
     ((eq (helixel--selection-type) 'line)
      (when-let* ((bounds (helixel--line-bounds-of-region))
                  (text (filter-buffer-substring (car bounds) (cdr bounds))))
        (kill-new (helixel--linewise-text text))))
     (t
      (call-interactively #'kill-ring-save))))
  (helixel--clear-data))

(helixel-define-command helixel-yank
    (:category edit :subcat paste-after :edit-op paste-after
               :params (&optional arg))
  (interactive "*P")
  (cond
   ((helixel--rect-wise-kill-p)
    (let ((lines (nth 1 (get-text-property
                         0 'yank-handler
                         (current-kill 0 t)))))
      (if lines
          (insert-rectangle lines)
        (insert-for-yank (current-kill 0 t)))))
   ((helixel--linewise-kill-p)
    (insert-for-yank (current-kill 0 t)))
   (t
    (yank arg))))

(helixel-define-command helixel-yank-before
    (:category edit :subcat paste-before :edit-op paste-before
               :params (&optional arg))
  (interactive "*P")
  (cond
   ((helixel--rect-wise-kill-p)
    (let ((lines (nth 1 (get-text-property
                         0 'yank-handler
                         (current-kill 0 t)))))
      (if lines
          (insert-rectangle lines)
        (insert-for-yank (current-kill 0 t)))))
   ((helixel--linewise-kill-p)
    (insert-for-yank (current-kill 0 t)))
   (t
    (yank arg))))

(helixel-define-command helixel-indent-left
    (:category edit :subcat indent-left :edit-op indent-left)
  (call-interactively #'indent-rigidly-left)
  (helixel--clear-data))

(helixel-define-command helixel-indent-right
    (:category edit :subcat indent-right :edit-op indent-right)
  (call-interactively #'indent-rigidly-right)
  (helixel--clear-data))

(defun helixel-quit (&optional force)
  "Kill Emacs if only one window, otherwise quit current window.

If FORCE is non-nil, don't prompt for save when killing Emacs."
  (if (one-window-p)
      (if force
          (kill-emacs)
        (call-interactively #'save-buffers-kill-terminal))
    (delete-window)))

(defun helixel-revert-all-buffers-quick ()
  "Execute `revert-buffer-quick' on all file-associated buffers."
  (let ((target-buffers (cl-remove-if-not
                         (lambda (buf)
                           (and
                            (buffer-file-name buf)
                            (file-readable-p (buffer-file-name buf))))
                         (buffer-list))))
    (mapc (lambda (buf)
            (with-current-buffer buf
              (revert-buffer-quick)))
          target-buffers)
    (message "Reverted %s buffers" (length target-buffers))))

(defvar helixel--command-alist
  `((("w" "write") ,#'save-buffer)
    (("q" "quit") ,#'helixel-quit)
    (("q!" "quit!") ,(lambda () (helixel-quit t)))
    (("wq" "write-quit") ,#'save-buffer ,#'helixel-quit)
    (("o" "open" "e" "edit") ,#'find-file)
    (("n" "new") ,#'scratch-buffer)
    (("rl" "reload") ,#'revert-buffer-quick)
    (("reload-all") ,#'helixel-revert-all-buffers-quick)
    (("pwd" "show-directory") ,#'pwd)
    (("vs" "vsplit") ,#'split-window-right)
    (("hs" "hsplit") ,#'split-window-below)
    (("config-open") ,(lambda () (find-file user-init-file))))
  "Alist of commands executed by `helixel-execute-command'.")


(defun helixel-define-ex-command (command callback)
  "Add COMMAND to `helixel--command-alist' that can be invoked via ':<command>'.

Argument CALLBACK is a function, command symbol, or list thereof.
Each element of CALLBACK is executed in order:
- If `commandp' is non-nil, it is called via `call-interactively'.
- Otherwise, it is called via `funcall'.

Example that defines the typable command ':build':
\(helixel-define-ex-command \"build\" #\\='compile)

Example with multiple callbacks:
\(helixel-define-ex-command \"build\" \\='(save-buffer compile))"
  (add-to-list 'helixel--command-alist
               (cons (if (listp command) command (list command))
                     (if (and (listp callback) (not (functionp callback)))
                         callback
                       (list callback)))))

(defun helixel-execute-command (input)
  "Look for INPUT in `helixel--command-alist' and execute it, if present."
  (interactive "s:")
  (let ((command (string-trim input)))
    (if-let* ((callbacks
               (catch 'found
                 (dolist (entry helixel--command-alist)
                   (let ((names (car entry)))
                     (when (member command names)
                       (throw 'found (cdr entry))))))))
        (dolist (cb callbacks)
          (if (and (symbolp cb) (commandp cb))
              (progn
                (call-interactively cb)
                (setq this-command cb))
            (when (symbolp cb)
              (setq this-command cb))
            (funcall cb)))
      (message "no such command '%s'" command))))


(defvar-keymap helixel-goto-map
  :doc "Keymap for Goto mode."
  :full t
  :parent goto-map
  "l" #'helixel-go-end-line
  "h" #'helixel-go-beginning-line
  "s" #'helixel-go-first-nonwhitespace
  "g" #'helixel-go-beginning-buffer
  "e" #'helixel-go-end-buffer
  "j" #'helixel-next-line
  "k" #'helixel-previous-line
  "r" #'xref-find-references
  "d" #'xref-find-definitions
  "y" #'eglot-find-typeDefinition
  "i" #'eglot-find-implementation)

(defvar-keymap helixel-view-map
  :doc "Keymap for View mode."
  :full t
  "z" #'recenter-top-bottom)

(defvar-keymap helixel-space-map
  :doc "Keymap for Space mode."
  :full t
  "f" #'project-find-file
  "b" #'project-switch-to-buffer
  "j" #'project-switch-project
  "/" #'project-find-regexp
  "a" #'eglot-code-action-quickfix
  "r" #'eglot-rename
  "d" #'flymake-show-buffer-diagnostics)

(defvar-keymap helixel-window-map
  :doc "Keymap for Window mode."
  :full t
  "h" #'windmove-left
  "l" #'windmove-right
  "j" #'windmove-down
  "k" #'windmove-up
  "w" #'other-window
  "v" #'split-window-right
  "s" #'split-window-below
  "q" #'delete-window
  "o" #'delete-other-windows)

(defvar-keymap helixel-textobj-map
  :doc "Keymap for textobj mode."
  :parent helixel-textobj-inner-map
  "i" helixel-textobj-inner-map
  "a" helixel-textobj-outer-map
  "s" #'helixel-surround-add
  "t" #'helixel-surround-add-tag
  "d" #'helixel-surround-delete
  "r" #'helixel-surround-replace)

(defvar-keymap helixel-normal-map
  :doc "Keymap for Helixel normal state."
  :full t
  ;; Editing commands
  "c" #'helixel-change-thing-at-point
  "d" #'helixel-kill-thing-at-point
  "y" #'helixel-kill-ring-save
  "r" #'helixel-replace
  "R" #'helixel-replace-char
  ;; ;I think helixel-yank can be replaced by helixel-replace
  ;; when helixel-replace-delete-char-p is nil
  "p" #'helixel-yank
  "P" #'helixel-yank-before
  "." #'helixel-repeat-edit
  "," #'helixel-repeat-selection
  "x" #'helixel-select-line
  "v" #'helixel-backward-word-end
  "C-v" #'helixel-select-rectangle
  "u" #'undo
  "U" #'undo-redo
  "o" #'helixel-insert-newline
  "O" #'helixel-insert-prevline
  "<" #'helixel-indent-left
  ">" #'helixel-indent-right
  ;; State switching
  "i" #'helixel-insert
  "I" #'helixel-insert-beginning-line
  "a" #'helixel-insert-after
  "A" #'helixel-insert-after-end-line
  ":" #'helixel-execute-command
  ;; ESC is defined as the meta-prefix-key, so we can't simply
  ;; rebind "ESC".  Instead, rebind <escape>.  More info:
  ;; https://emacs.stackexchange.com/questions/14755/
  ;; how-to-remove-bindings-to-the-esc-prefix-key
  "<escape>" #'keyboard-quit
  "<DEL>" #'ignoree
  ;; Movement keys
  "h" #'helixel-backward-char
  "l" #'helixel-forward-char
  "j" #'helixel-next-line
  "k" #'helixel-previous-line
  "G" #'helixel-goto-line
  "%" #'mark-whole-buffer
  ";" #'helixel-action-cycle
  "C-o" #'helixel-jump-backward
  "C-i" #'helixel-jump-forward
  "C-f" #'helixel-scroll-up-command
  "C-b" #'helixel-scroll-down-command
  ;; Digit arguments via C-u prefix
  "1" "C-u 1"
  "2" "C-u 2"
  "3" "C-u 3"
  "4" "C-u 4"
  "5" "C-u 5"
  "6" "C-u 6"
  "7" "C-u 7"
  "8" "C-u 8"
  "9" "C-u 9"
  "0" "C-u 0"
  "-" "C-u -"
  "=" #'indent-for-tab-command
  ;; Word movement
  "w" #'helixel-forward-word-start
  "W" #'helixel-forward-WORD-start
  "e" #'helixel-forward-word-end
  "E" #'helixel-forward-WORD-end
  "b" #'helixel-backward-word-start
  "B" #'helixel-backward-WORD
  ;; Unimpaired
  "] d" #'flymake-goto-next-error
  "[ d" #'flymake-goto-prev-error
  ;; Prefix maps
  "m" helixel-textobj-map
  "g" helixel-goto-map
  "z" helixel-view-map
  "SPC" helixel-space-map
  "C-w" helixel-window-map)

(defvar-keymap helixel-visual-map
  :doc "Keymap for Helixel visual state.  Inherits from normal state."
  :parent helixel-normal-map
  "v" #'helixel-visual-exit
  "<escape>" #'helixel-visual-exit)

(defvar-keymap helixel-motion-map
  :doc "Keymap for Helixel motion state."
  :full t)

(defvar-keymap helixel-insert-map
  :doc "Keymap for Helixel insert state."
  "<escape>" #'helixel-insert-exit)

(defvar helixel-state-map-alist
  `((insert . ,helixel-insert-map)
    (normal . ,helixel-normal-map)
    (visual . ,helixel-visual-map)
    (motion . ,helixel-motion-map)
    (textobj . ,helixel-textobj-map)
    (textobj-inner . ,helixel-textobj-inner-map)
    (textobj-outer . ,helixel-textobj-outer-map)
    (view . ,helixel-view-map)
    (goto . ,helixel-goto-map)
    (window . ,helixel-window-map)
    (space . ,helixel-space-map))
  "Alist mapping a state symbol to a Helixel keymap.")

(defun helixel-define-key (state key def &optional mode)
  "Define a Helixel keybinding for KEY to DEF.

When MODE is nil, bind to the keymap associated with STATE from
`helixel-state-map-alist'.  When MODE is provided (e.g.,
\\='dired-mode), store the binding so it takes precedence via
`minor-mode-overriding-map-alist' when that mode is active.

Argument STATE must be one of: insert, normal, motion, visual, view,
goto, window, space, textobj (m prefix), textobj-inner (mi prefix),
textobj-outer (ma prefix).

Argument KEY and DEF follow the same conventions as `define-key'.

Optional argument MODE is a major or minor mode symbol for which to
create mode-specific bindings that override helixel defaults.

Example:
  ;; Standard: bind to Helix's normal state keymap
  (helixel-define-key \\='normal \"s\" #\\='my-command)

  ;; Major-mode specific: override normal state bindings in Dired
  (with-eval-after-load \\='Dired
    (helixel-define-key \\='normal \"j\" #\\='dired-next-line \\='dired-mode)
    (helixel-define-key \\='normal \"k\"
      #\\='dired-previous-line \\='dired-mode))

  ;; Motion state with major-mode specific bindings
  (helixel-define-key \\='motion \"j\" #\\='next-line \\='prog-mode)
  (helixel-define-key \\='motion \"k\" #\\='previous-line \\='prog-mode)

  ;; Mode-specific text object binding (org-mode only)
  (helixel-define-key \\='textobj-inner \"o\"
    #\\='helixel-mark-inner-org-block \\='org-mode)
  (helixel-define-key \\='textobj-outer \"o\"
    #\\='helixel-mark-a-org-block \\='org-mode)"
  (unless (alist-get state helixel-state-map-alist)
    (error "Invalid state %s" state))
  (if mode
      ;; Store binding in helixel--mode-keybindings
      (let* ((alist-key (cons mode state))
             (entry (assoc alist-key helixel--mode-keybindings)))
        (unless entry
          (setq entry (cons alist-key (make-sparse-keymap)))
          (push entry helixel--mode-keybindings))
        (define-key (cdr entry) key def))
    ;; Bind to global state keymap
    (let ((state-keymap (alist-get state helixel-state-map-alist)))
      (define-key state-keymap key def))))

(defun helixel--refresh-overriding-maps ()
  "Rebuild `minor-mode-overriding-map-alist' for the current buffer."
  (let ((state helixel--current-state)
        (state-mode (alist-get helixel--current-state helixel-state-alist))
        (overrides nil))
    (dolist (entry helixel--mode-keybindings)
      (let ((mode (caar entry)))
        (when (and (eq (cdar entry) state)
                   (or (eq mode major-mode)
                       (and (boundp mode) (symbol-value mode))))
          (push (cdr entry) overrides))))
    (setq minor-mode-overriding-map-alist
          (assq-delete-all state-mode minor-mode-overriding-map-alist))
    (when overrides
      (let ((base-keymap (alist-get state helixel-state-map-alist)))
        (push (cons state-mode (make-composed-keymap overrides base-keymap))
              minor-mode-overriding-map-alist)))
    ;; Textobj sub-map mode-specific overrides
    (helixel--refresh-textobj-overrides)))

(defun helixel--refresh-textobj-overrides ()
  "Build mode-specific composed keymaps for textobj inner/outer.
When `helixel--mode-keybindings' contains entries for `textobj-inner'
or `textobj-outer' in the current `major-mode', make
`helixel-textobj-map' buffer-local and point its \"i\"/\"a\" entries
to composed keymaps with mode overrides on top of the base maps."
  (let ((inner-overrides nil)
        (outer-overrides nil))
    (dolist (entry helixel--mode-keybindings)
      (let ((mode (caar entry))
            (sub (cdar entry)))
        (when (or (eq mode major-mode)
                  (and (boundp mode) (symbol-value mode)))
          (cond ((eq sub 'textobj-inner)
                 (push (cdr entry) inner-overrides))
                ((eq sub 'textobj-outer)
                 (push (cdr entry) outer-overrides))))))
    ;; Restore defaults when no overrides
    (unless (or inner-overrides outer-overrides)
      (when (local-variable-p 'helixel-textobj-map)
        (define-key helixel-textobj-map "i" helixel-textobj-inner-map)
        (define-key helixel-textobj-map "a" helixel-textobj-outer-map)
        (kill-local-variable 'helixel-textobj-map)))
    ;; Build composed keymaps with overrides
    (when (or inner-overrides outer-overrides)
      (make-local-variable 'helixel-textobj-map)
      (when inner-overrides
        (define-key helixel-textobj-map "i"
                    (make-composed-keymap inner-overrides
                                          helixel-textobj-inner-map)))
      (when outer-overrides
        (define-key helixel-textobj-map "a"
                    (make-composed-keymap outer-overrides
                                          helixel-textobj-outer-map))))))

(define-minor-mode helixel-insert-state
  "Helixel INSERT state minor mode."
  :lighter " helixel[I]"
  :init-value nil
  :interactive nil
  :global nil
  :keymap helixel-insert-map
  (if helixel-insert-state
      (progn
        (setq-local helixel--current-state 'insert)
        (setq cursor-type 'bar))
    (setq-local helixel--current-state 'normal)))

;;;###autoload
(define-minor-mode helixel-motion-state
  "Helixel MOTION state minor mode for read-only navigation.
Only j, k, g keys are available by default.
Use `helixel-define-key' to add major-mode specific bindings."
  :lighter " helixel[M]"
  :init-value nil
  :interactive nil
  :global nil
  :keymap helixel-motion-map
  (if helixel-motion-state
      (progn
        (setq-local helixel--current-state 'motion)
        (setq cursor-type 'box)
        (helixel--refresh-overriding-maps))
    (setq-local helixel--current-state 'normal)))

(define-minor-mode helixel-visual-state
  "Helixel VISUAL state minor mode."
  :lighter " helixel[V]"
  :init-value nil
  :interactive nil
  :global nil
  :keymap helixel-visual-map
  (if helixel-visual-state
      (progn
        (setq-local helixel--current-state 'visual)
        (setq cursor-type 'box)
        (helixel--refresh-overriding-maps))
    (setq-local helixel--current-state 'normal)))

;;;###autoload
(define-minor-mode helixel-normal-state
  "Helixel NORMAL state minor mode."
  :lighter " helixel[N]"
  :init-value nil
  :interactive t
  :global nil
  :keymap helixel-normal-map
  (if helixel-normal-state
      (progn
        (setq-local helixel--current-state 'normal)
        (setq cursor-type 'box)
        (helixel--refresh-overriding-maps))))

(defun helixel--is-self-insert-p (cmd)
  "Return non-nil if CMD is a self-insert command."
  (and (symbolp cmd)
       (string-match-p "\\`.*self-insert.*\\'"
                       (symbol-name cmd))))

(defun helixel--default-state-for-buffer ()
  "Return the default Helixel state for the current buffer.
Look up the current major mode in `helixel-major-mode-default-states'.
If no entry matches, guess based on key bindings: if letters a-z
are bound to self-insert commands, use `normal', otherwise `motion'."
  (or (cl-some (lambda (cell)
                 (when (derived-mode-p (car cell))
                   (cdr cell)))
               helixel-major-mode-default-states)
      (let* ((state-modes (mapcar #'cdr helixel-state-alist))
             (minor-mode-map-alist
              (cl-remove-if (lambda (x) (memq (car x) state-modes))
                            minor-mode-map-alist))
             (minor-mode-overriding-map-alist
              (cl-remove-if (lambda (x) (memq (car x) state-modes))
                            minor-mode-overriding-map-alist))
             (letters (split-string "abcdefghijklmnopqrstuvwxyz" "" t))
             (any-self-insert (cl-some (lambda (letter)
                                         (helixel--is-self-insert-p
                                          (key-binding letter)))
                                       letters)))
        (if any-self-insert 'normal 'motion))))

(defun helixel-mode-maybe-activate (&optional status)
  "Activate or deactivate Helixel state if `helixel-global-mode' is non-nil.

A positive STATUS activates the default state for the current buffer.
A non-positive STATUS deactivates the current state.
The default state is determined by `helixel--default-state-for-buffer'."
  (when (and (not (minibufferp)) helixel-global-mode)
    (if (and status (<= status 0))
        ;; Deactivate current state
        (let ((mode (alist-get helixel--current-state
                               helixel-state-alist)))
          (funcall mode -1))
      ;; Activate default state
      (let* ((state (helixel--default-state-for-buffer))
             (mode (alist-get state helixel-state-alist)))
        (funcall mode (if status status 1))
        (helixel--refresh-overriding-maps)))))

;;;###autoload
(defun helixel-mode-all (&optional status)
  "Activate Helixel mode in all buffers with their default states.

Argument STATUS is passed through to `helixel-mode-maybe-activate'."
  (interactive)
  (helixel-action-start 'state 'toggle)
  ;; Set global mode to t before iterating over the buffers so that we
  ;; send the status directly to `helixel-normal-state' (which checks for
  ;; a non-nil value of `helixel-global-mode'.
  (setq helixel-global-mode t)
  (mapc (lambda (buf)
          (with-current-buffer buf
            (helixel-mode-maybe-activate status)))
        (buffer-list))
  (setq helixel-global-mode (if status status 1)))

;;;###autoload
(defun helixel-mode ()
  "Toggle global Helixel mode."
  (interactive)
  (helixel-action-start 'state 'toggle)
  (setq helixel-global-mode (not helixel-global-mode))
  (if helixel-global-mode
      (progn
        ;; Ensure \\[keyboard-quit] clears state and breaks session continuity.
        (advice-add #'keyboard-quit :before #'helixel--clear-data)
        (advice-add #'keyboard-quit :before #'helixel--cancel-action)
        (add-hook 'after-change-major-mode-hook #'helixel-mode-maybe-activate)
        (helixel-mode-maybe-activate 1))
    (cond
     (helixel-normal-state (helixel-normal-state -1))
     (helixel-insert-state (helixel-insert-state -1))
     (helixel-motion-state (helixel-motion-state -1))
     (helixel-visual-state (helixel-visual-state -1)))
    (advice-remove #'keyboard-quit #'helixel--clear-data)
    (advice-remove #'keyboard-quit #'helixel--cancel-action)
    (remove-hook 'after-change-major-mode-hook #'helixel-mode-maybe-activate)
    (remove-hook 'helixel-action-push-functions #'helixel--jump-list-push)))

(helixel-define-jump-command 'xref-find-definitions)
(helixel-define-jump-command 'xref-find-references)
(helixel-define-jump-command 'eglot-find-typeDefinition)
(helixel-define-jump-command 'eglot-find-implementation)

(defun helixel--recreate-line (ctx)
  "Replay a linewise selection from CTX.
When :entry-kind is present (insert ops), position cursor
at the appropriate offset on the selected line:
  :entry-kind insert \=`region-beginning' + cursor-offset
  :entry-kind append \=`region-end' + cursor-offset"
  (let ((n (helixel-sel-line-count ctx))
        (entry-kind (plist-get ctx :entry-kind)))
    (if (eq (helixel-sel-line-dir ctx) 'backward)
        (helixel-select-line-up n)
      (helixel-select-line n))
    (when entry-kind
      ;; Position cursor for key/text insertion.
      (goto-char (if (eq entry-kind 'append)
                     (line-end-position)
                   (line-beginning-position)))
      (let ((off (helixel-sel-insert-cursor-offset ctx)))
        (when off (forward-char off))))))

(defun helixel--recreate-rect (ctx)
  "Replay a rectangular selection from CTX."
  (let ((n (helixel-sel-rect-count ctx)))
    (unless rectangle-mark-mode
      (helixel--switch-state 'visual)
      (push-mark (point) t t)
      (rectangle-mark-mode 1))
    (dotimes (_ (1- n))
      (forward-line 1)
      (rectangle--reset-point-crutches))
    (setq helixel--selection-type 'rect)))

(defun helixel--recreate-movement (ctx)
  "Replay movement selection from CTX."
  (let ((helixel--current-state 'visual))
    (dolist (m (reverse (helixel-sel-movement-moves ctx)))
      (dotimes (_ (cdr m))
        (funcall (car m))))))

(defun helixel--recreate-search (ctx)
  "Replay search selection from CTX.
Finds the next match, activates the region on it.
If CTX has :entry-kind (insert or append), positions the cursor
at the appropriate offset within the match for insert-text ops.
For insert operations, skips past a current match if point
sits on the pattern start so chained `.` advances correctly."
  (let* ((pat (helixel-sel-search-pattern ctx))
         (dir (helixel-sel-search-dir ctx)))
    (unless pat
      (user-error "No search pattern to repeat"))
    ;; For insert ops, skip past the current match if point sits on
    ;; or near it.  Insert ops preserve the match text (e.g. iX →
    ;; Xhello still contains "hello"), so `.` would otherwise re-find
    ;; the same match.  Change ops delete the match so no skip needed.
    ;;
    ;; Two cases: point at match-start (i after search) → looking-at
    ;; succeeds; point at match-end (a after search) → looking-at
    ;; fails but a backward search from point finds the match ending
    ;; nearby.
    (when (and (helixel-sel-search-entry-kind ctx)
               (let ((orig (point)))
                 (or (looking-at pat)
                     (save-excursion
                       (condition-case nil
                           (progn
                             (helixel-search--search
                              pat 'backward)
                             (<= (- orig (match-end 0))
                                 (length pat)))
                         (search-failed nil))))))
      (if (eq dir 'backward)
          ;; Backward: go before match-beginning to skip this match.
          (goto-char (max (point-min)
                          (1- (match-beginning 0))))
        ;; Forward: go to match-end to skip this match.
        (goto-char (match-end 0))))
    (condition-case nil
        (helixel-search--search pat dir)
      (search-failed
       (user-error "Search pattern not found: %s" pat)))
    (push-mark (match-beginning 0) t t)
    (goto-char (match-end 0))
    (setq helixel--selection-type 'char)
    ;; For insert operations: position cursor within the match
    (when-let* ((entry-kind (helixel-sel-search-entry-kind ctx)))
      (let* ((base (if (eq entry-kind 'append)
                       (match-end 0)
                     (match-beginning 0)))
             (cursor-offset (or (helixel-sel-search-cursor-offset ctx) 0)))
        (goto-char (+ base cursor-offset))))))

(defun helixel--recreate-insert-selection-start (ctx)
  "Replay insert-selection-start.  CTX holds :cursor-offset (int or nil)."
  (goto-char (region-beginning))
  (let ((off (helixel-sel-insert-cursor-offset ctx)))
    (when off (forward-char off))))

(defun helixel--recreate-insert-selection-end (ctx)
  "Replay insert-selection-end.  CTX holds :cursor-offset (int or nil)."
  (goto-char (region-end))
  (let ((off (helixel-sel-insert-cursor-offset ctx)))
    (when off (forward-char off))))

(defun helixel--recreate-insert-beginning-line (_ctx)
  "Replay insert-beginning-line.  CTX is ignored."
  (beginning-of-line))

(defun helixel--recreate-insert-end-line (_ctx)
  "Replay insert-end-line.  CTX is ignored."
  (end-of-line))

(defun helixel--recreate-insert-search-offset (ctx)
  "Replay insert-search-offset.  CTX holds :offset (integer)."
  (let ((offset (helixel-sel-insert-offset ctx)))
    (goto-char (+ (match-beginning 0) offset))))

;; ---------------------------------------------------------------------------
;; Selection-descriptor producers
;;
;; All producers now create `helixel-sel' structs with stored closures.

;; ---------------------------------------------------------------------------
;; Edit-op runners (registry consumers — see `helixel-edit-defop')
;;
;; Each runner receives the full transaction TX and performs the replay.
;; They are looked up by `helixel--execute-edit' purely through the registry,
;; so this file owns the implementation but `helixel-repeat.el' has zero
;; knowledge of specific operators.

(defun helixel--repeat-change-core (tx)
  "Repeat change TX: delete selection, replay kmacro keys or insert text.
TX is the complete edit transaction (see `helixel-edit-make').
Kmacro keys/commands (primary) capture the full insert-mode keystrokes.
Text (fallback) is used when keys/commands are unavailable (tests).

For rect selections the stored text is replayed on every subsequent
rectangle line via `helixel--rect-replay' — no state-switching side
-effect (avoids an unnecessary helixel-insert-exit during replay)."
  (let* ((keys (helixel--repeat-get-keys tx))
         (cmds (plist-get (helixel-edit-payload tx) :commands))
         (text (plist-get (helixel-edit-payload tx) :inserted-text)))
    (cond
     ((and (use-region-p) (eq (helixel--selection-type) 'rect))
      (helixel--rect-change)
      (if (or keys cmds)
          (helixel--execute-keys keys cmds)
        (when text (insert text)))
      (helixel--rect-replay))
     (t
      (helixel--delete-selection)
      (if (or keys cmds)
          (helixel--execute-keys keys cmds)
        (when text (insert text)))))))

(helixel-edit-defop kill          :display "d" :repeat-advance nil
                    :runner (lambda (_tx) (helixel-kill-thing-at-point)))
(helixel-edit-defop change        :display "c" :repeat-advance nil
                    :runner #'helixel--repeat-change-core)
(helixel-edit-defop copy          :display "y" :repeat-advance 'line
                    :runner (lambda (_tx) (helixel-kill-ring-save)))
(helixel-edit-defop replace       :display "r" :repeat-advance 'line
                    :runner (lambda (_tx) (helixel-replace)))
(helixel-edit-defop replace-char  :repeat-advance 'line
  :display (lambda (tx)
             (let ((c (plist-get (helixel-edit-payload tx) :char)))
               (if c (format "R[%c]" c) "R")))
  :runner (lambda (tx)
            (helixel-replace-char
             (plist-get (helixel-edit-payload tx) :char))))
(helixel-edit-defop paste-after   :display "p" :repeat-advance 'line
                    :runner (lambda (_tx) (helixel-yank)))
(helixel-edit-defop paste-before  :display "P" :repeat-advance 'line
                    :runner (lambda (_tx) (helixel-yank-before)))
(helixel-edit-defop indent-left   :display "<" :repeat-advance 'line
                    :runner (lambda (_tx) (helixel-indent-left)))
(helixel-edit-defop indent-right  :display ">" :repeat-advance 'line
                    :runner (lambda (_tx) (helixel-indent-right)))
(helixel-edit-defop insert-text   :display "i" :repeat-advance 'line
  :runner (lambda (tx)
            (let ((keys (plist-get (helixel-edit-payload tx) :keys))
                  (cmds (plist-get (helixel-edit-payload tx) :commands)))
              (if (or keys cmds)
                  (progn (deactivate-mark)
                         (helixel--execute-keys keys cmds))
                (insert (or (plist-get (helixel-edit-payload tx) :text)
                            ""))))))

(provide 'helixel-common)
;;; helixel-common.el ends here
