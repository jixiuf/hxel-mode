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


(defcustom helixel-major-mode-default-states '((calc-mode . insert))
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


(defvar helixel-state-mode-alist
  `((insert . helixel-insert-mode)
    (normal . helixel-normal-mode)
    (visual . helixel-visual-mode)
    (motion . helixel-motion-mode))
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

;; These Helixel Minor keymap modes are assigned keymaps during
;; `helixel-normal-mode' initialization.
(defvar helixel-goto-map nil "Keymap for Goto mode.")
(defvar helixel-view-map nil "Keymap for View mode.")
(defvar helixel-space-map nil "Keymap for Space mode.")
(defvar helixel-window-map nil "Keymap for Window mode.")
(defvar helixel-textobj-map nil "Keymap for textobj mode.")
;; Forward declaration - defined later with keymap initializers
(defvar helixel--state-to-keymap-alist)

(defvar helixel--mode-keybindings nil
  "Alist of ((MODE . STATE) . sparse-keymap).
MODE is a major or minor mode symbol.  STATE is a helixel state symbol.
Stores mode-specific helixel bindings registered via `helixel-define-key'.")

;; Wire textobj hooks for action recording and visual state detection.
(setq helixel-textobj-action-function #'helixel-action-start)
(setq helixel-textobj-visual-state-p-function
      (lambda () (eq helixel--current-state 'visual)))

(defun helixel--unload-current-state ()
  "Deactivate the minor mode described by `helixel--current-state'."
  (let ((mode (alist-get helixel--current-state helixel-state-mode-alist)))
    (funcall mode -1)))

(defun helixel--switch-state (state)
  "Switch to STATE."
  (unless (eq state helixel--current-state)
    (helixel--unload-current-state)
    (helixel--clear-data)
    (setq-local helixel--current-state state)
    (let ((mode (alist-get state helixel-state-mode-alist)))
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
Accumulates consecutive same-command moves by incrementing count."
  (when (eq helixel--current-state 'visual)
    (let ((ctx helixel--repeat-sel-ctx)
          (entry (cons cmd 1)))
      (if (and ctx (eq (plist-get ctx :kind) 'movement))
          (let* ((moves (plist-get ctx :moves))
                 (last (car moves)))
            (if (and last (eq (car last) cmd))
                (setcdr last (1+ (cdr last)))
              (plist-put ctx :moves (cons entry moves))))
        (setq helixel--repeat-sel-ctx
              `(:kind movement :moves (,entry)))))))

(defun helixel-insert ()
  "Switch to insert state at the beginning of the selection."
  (interactive)
  (helixel-action-start 'state 'insert)
  (helixel--record-edit 'insert-text)
  (if (use-region-p)
      (goto-char (region-beginning)))
  (setq helixel--change-track-marker (point-marker))
  (helixel--switch-state 'insert))

(defun helixel-insert-exit ()
  "Switch to normal state."
  (interactive)
  (helixel-action-start 'state 'exit)
  (when (and helixel--change-track-marker
             (member (helixel-edit-op helixel--last-tx)
                     '(change insert-text)))
    (let ((text (buffer-substring helixel--change-track-marker (point)))
          (payload (helixel-edit-payload helixel--last-tx)))
      (plist-put payload
                 (if (eq (helixel-edit-op helixel--last-tx) 'change)
                     :inserted-text :text)
                 text))
    (set-marker helixel--change-track-marker nil)
    (setq helixel--change-track-marker nil))
  (when helixel--rect-replay-data
    (helixel--rect-replay))
  (let ((state (helixel--default-state-for-buffer)))
    (when (eq state 'insert)
      (setq state 'normal))
    (helixel--switch-state state)))

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

Wrapper mode (default):
  (helixel-define-movement helixel-forward-char forward-char char :dir forward)

Advice mode:
  (helixel-define-movement nil forward-char char :dir forward :advice)

Without highlights clearing:
  (helixel-define-movement helixel-scroll-up scroll-up-command scroll
                        :clear-highlights nil)"
  (declare (indent 1))
  (let* ((dir (plist-get options :dir))
         (advicep (plist-get options :advice))
         (clear-highlights (if (plist-member options :clear-highlights)
                               (plist-get options :clear-highlights)
                             t)))
    (if advicep
        `(advice-add #',builtin :before
                     (lambda (&rest _)
                       ,(format "Helixel %s movement advice." type)
                       (helixel-action-start 'movement ',type)
                       ,(when dir
                          `(helixel--live-cat-set-dir ',dir))
                       ,@(when clear-highlights
                           '((helixel--clear-highlights)))))
      `(defun ,name ()
         ,(format "Helixel movement wrapping `%s'." builtin)
         (interactive)
         (helixel-action-start 'movement ',type)
         ,(when dir `(helixel--live-cat-set-dir ',dir))
         ,@(when clear-highlights
             '((helixel--clear-highlights)))
         (call-interactively #',builtin)
         (helixel--track-visual-move #',name)))))

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

If a region is already active, no new region is created."
  `(progn
     (helixel--clear-highlights)
     (let ((current (point)))
       ,@body
       (unless (use-region-p)
         (push-mark current t 'activate))
       (helixel--track-visual-move this-command))))

(defun helixel-forward-word-start ()
  "Move to start of the next word."
  (interactive)
  (helixel-action-start 'movement 'word)
  (helixel--live-cat-set-dir 'forward)
  (helixel--with-movement-surround
   (helixel--forward-beginning 'helixel-word)))

(defun helixel-forward-word-end ()
  "Move to the end of the current word."
  (interactive)
  (helixel-action-start 'movement 'word)
  (helixel--live-cat-set-dir 'forward)
  (helixel--with-movement-surround
   (helixel--forward-end 'helixel-word)))

(defun helixel-backward-word-start ()
  "Move to previous word."
  (interactive)
  (helixel-action-start 'movement 'word)
  (helixel--live-cat-set-dir 'backward)
  (helixel--with-movement-surround
   (helixel--forward-beginning 'helixel-word -1)))

(defun helixel-backward-word-end ()
  "Move to previous word."
  (interactive)
  (helixel-action-start 'movement 'word)
  (helixel--live-cat-set-dir 'backward)
  (helixel--with-movement-surround
   (helixel--forward-end 'helixel-word -1)))

(defun helixel-forward-WORD-start ()
  "Move to start of the next long word."
  (interactive)
  (helixel-action-start 'movement 'WORD)
  (helixel--live-cat-set-dir 'forward)
  (helixel--with-movement-surround
   (helixel--forward-beginning 'helixel-WORD)))

(defun helixel-forward-WORD-end ()
  "Move to end of this long word."
  (interactive)
  (helixel-action-start 'movement 'WORD)
  (helixel--live-cat-set-dir 'forward)
  (helixel--with-movement-surround
   (helixel--forward-end 'helixel-WORD)))

(defun helixel-backward-WORD ()
  "Move to previous long word."
  (interactive)
  (helixel-action-start 'movement 'WORD)
  (helixel--live-cat-set-dir 'backward)
  (helixel--with-movement-surround
   (helixel--forward-beginning 'helixel-WORD -1)))


(defun helixel-backward-WORD-end ()
  "Move to previous long word."
  (interactive)
  (helixel-action-start 'movement 'WORD)
  (helixel--live-cat-set-dir 'backward)
  (helixel--with-movement-surround
   (helixel--forward-end 'helixel-WORD -1)))

(defun helixel-forward-symbol-start ()
  "Move to start of the next symbol."
  (interactive)
  (helixel-action-start 'movement 'symbol)
  (helixel--live-cat-set-dir 'forward)
  (helixel--with-movement-surround
   (helixel--forward-beginning 'helixel-symbol)))

(defun helixel-forward-symbol-end ()
  "Move to the end of the current symbol."
  (interactive)
  (helixel-action-start 'movement 'symbol)
  (helixel--live-cat-set-dir 'forward)
  (helixel--with-movement-surround
   (helixel--forward-end 'helixel-symbol)))

(defun helixel-backward-symbol-start ()
  "Move to previous symbol."
  (interactive)
  (helixel-action-start 'movement 'symbol)
  (helixel--live-cat-set-dir 'backward)
  (helixel--with-movement-surround
   (helixel--forward-beginning 'helixel-symbol -1)))

(defun helixel-backward-symbol-end ()
  "Move to previous symbol."
  (interactive)
  (helixel-action-start 'movement 'symbol)
  (helixel--live-cat-set-dir 'backward)
  (helixel--with-movement-surround
   (helixel--forward-end 'helixel-symbol -1)))

(defun helixel-go-beginning-buffer ()
  "Go to beginning of buffer, or go to line N if a numeric prefix arg is given."
  (interactive)
  (helixel-action-start 'movement 'goto)
  (helixel--clear-highlights)
  (if current-prefix-arg
      (goto-line (prefix-numeric-value current-prefix-arg))
    (call-interactively #'beginning-of-buffer))
  (helixel--track-visual-move this-command))

(defun helixel-goto-line (&optional arg)
  "Go to line ARG, recording session."
  (interactive "P")
  (helixel-action-start 'movement 'goto)
  (goto-line (if arg (prefix-numeric-value arg) (goto-line-read-args)))
  (helixel--track-visual-move this-command))


(defun helixel-select-line ()
  "Select the current line, moving the cursor to the end."
  (interactive)
  (helixel-action-start 'movement 'lineselect)
  (helixel--live-cat-set-dir 'forward)
  (if (and (region-active-p) (eolp))
      (progn
        (call-interactively #'next-line)
        (end-of-line))
    (beginning-of-line)
    (push-mark-command t t)
    (end-of-line))
  (setq helixel--selection-type 'line)
  (setq helixel--repeat-sel-ctx (list :fn this-command :kind 'line)))

(defun helixel-select-line-up ()
  "Select the current line, extending upward on every subsequent call."
  (interactive)
  (helixel-action-start 'movement 'lineselect)
  (helixel--live-cat-set-dir 'backward)
  (if (and (region-active-p) (bolp))
      (progn
        (call-interactively #'previous-line)
        (beginning-of-line))
    (end-of-line)
    (push-mark-command t t)
    (beginning-of-line))
  (setq helixel--selection-type 'line)
  (setq helixel--repeat-sel-ctx (list :fn this-command :kind 'line)))

(defun helixel-select-rectangle ()
  "Start or extend rectangle selection.
If `rectangle-mark-mode' is already active, extend the rectangle
down one line.  Otherwise, start a rectangle selection at point."
  (interactive)
  (helixel-action-start 'movement 'rectselect)
  (if rectangle-mark-mode
      (progn
        (if (or (> (point) (mark))
                (and (= (point) (mark))
                     (eq last-command 'helixel-select-rectangle)))
            (forward-line 1)
          (forward-line -1))
        (rectangle--reset-point-crutches))
    (helixel--switch-state 'visual)
    (push-mark (point) t t)
    (rectangle-mark-mode 1))
  (setq helixel--selection-type 'rect)
  (setq helixel--repeat-sel-ctx (list :fn this-command :kind 'rect)))

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
    (helixel--switch-state 'insert)))

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

(defun helixel-kill-thing-at-point ()
   "Kill current region or delete char at point.
When selection is line-wise, tag the killed text with a line-wise yank-handler.
When selection is rect, tag with a rect-wise yank-handler."
   (interactive)
   (helixel--record-edit 'kill)
   (helixel--delete-selection)
   (helixel--clear-data))

(defun helixel-change-thing-at-point ()
  "Remove the current region or current point and enter insert-mode.
When selection is rect, replay inserted text on all rect lines."
  (interactive)
  (helixel--record-edit 'change)
  (if (and (use-region-p) (eq (helixel--selection-type) 'rect))
      (helixel--rect-change)
    (helixel--delete-selection)
    (setq helixel--change-track-marker (point-marker))
    (helixel--switch-state 'insert)))

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

(defun helixel-insert-after ()
  "Swap to insert mode at the end of the selection."
  (interactive)
  (helixel--record-edit 'insert-text)
  (if (use-region-p)
      (goto-char (region-end))
    (unless (helixel--end-of-line-p)
      (forward-char)))
  (setq helixel--change-track-marker (point-marker))
  (helixel--switch-state 'insert))

(defun helixel-insert-beginning-line ()
  "Move current point to the beginning of line and enter insert mode."
  (interactive)
  (helixel--record-edit 'insert-text)
  (beginning-of-line)
  (setq helixel--change-track-marker (point-marker))
  (helixel--switch-state 'insert))

(defun helixel-insert-after-end-line ()
  "Move current point to the end of line and enter insert mode."
  (interactive)
  (helixel--record-edit 'insert-text)
  (end-of-line)
  (setq helixel--change-track-marker (point-marker))
  (helixel--switch-state 'insert))

(defun helixel-insert-newline ()
  "Insert newline and change `helixel--current-state' to INSERT mode."
  (interactive)
  (helixel--record-edit 'insert-text)
  (helixel--clear-data)
  (end-of-line)
  (newline-and-indent)
  (setq helixel--change-track-marker (point-marker))
  (helixel--switch-state 'insert))

(defun helixel-insert-prevline ()
  "Insert line above and change `helixel--current-state' to INSERT mode."
  (interactive)
  (helixel--record-edit 'insert-text)
  (helixel--clear-data)
  (beginning-of-line)
  (let ((electric-indent-mode nil))
    (newline nil t)
    (call-interactively #'previous-line)
    (indent-according-to-mode))
  (setq helixel--change-track-marker (point-marker))
  (helixel--switch-state 'insert))

(defun helixel--replace-region (start end text)
  "Replace region from START to END in-place with TEXT."
  (delete-region start end)
  (insert text)
  (helixel--clear-data))

(defun helixel-replace-char (char)
  "Replace selection with CHAR.
If no region is active, replace character at point."
  (interactive "c")
  (helixel--record-edit 'replace-char :char char)
  (if (use-region-p)
      (helixel--replace-region
       (region-beginning) (region-end)
       (make-string (- (region-end) (region-beginning)) char))
    (helixel--replace-region (point) (1+ (point)) char)))

(defun helixel-replace ()
  "Replace selection with the last stretch of killed text.
Handles line-wise and rect content appropriately."
  (interactive)
  (helixel--record-edit 'replace)
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

(defun helixel-kill-ring-save ()
  "Save region to `kill-ring' and clear Helixel selection data.
When selection is line-wise, tag the text with a line-wise yank-handler.
When selection is rect, tag with a rect-wise yank-handler."
  (interactive)
  (helixel--record-edit 'copy)
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

(defun helixel-yank (&optional arg)
  "Paste from kill ring after point.
Line-wise kills are pasted below the current line.
Rect kills are pasted as a rectangle.
Otherwise behaves like `yank'.

ARG is passed to `yank'."
  (interactive "*P")
  (helixel--record-edit 'paste-after)
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

(defun helixel-yank-before (&optional arg)
  "Paste from kill ring before point.
Line-wise kills are pasted above the current line.
Rect kills are pasted as a rectangle.
Otherwise behaves like `yank'.

ARG is passed to `yank'."
  (interactive "*P")
  (helixel--record-edit 'paste-before)
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

(defun helixel-indent-left ()
  "Indent region leftward and clear Helixel selection data."
  (interactive)
  (helixel--record-edit 'indent-left)
  (call-interactively #'indent-rigidly-left)
  (helixel--clear-data))

(defun helixel-indent-right ()
  "Indent region rightward and clear Helixel selection data."
  (interactive)
  (helixel--record-edit 'indent-right)
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
                     (if (listp callback) callback (list callback)))))

(defun helixel-execute-command (input)
  "Look for INPUT in `helixel--command-alist' and execute it, if present."
  (interactive "s:")
  (let ((command (string-trim input)))
    (if-let* ((callbacks
               (alist-get command helixel--command-alist nil nil
                          (lambda (a b) (member b a)))))
        (dolist (cb callbacks)
          (if (commandp cb)
              (progn
                (call-interactively cb)
                (setq this-command cb))
            (when (symbolp cb)
              (setq this-command cb))
            (funcall cb)))
      (message "no such command '%s'" command))))

(defvar helixel-normal-state-keymap
  (let ((keymap (make-keymap)))
    (define-prefix-command 'helixel-goto-map)
    (define-prefix-command 'helixel-view-map)
    (define-prefix-command 'helixel-space-map)
    (define-prefix-command 'helixel-window-map)
    (define-prefix-command 'helixel-textobj-map)

    (suppress-keymap keymap t)

    ;; Editing commands
    (define-key keymap "c" #'helixel-change-thing-at-point)
    (define-key keymap "d" #'helixel-kill-thing-at-point)
    (define-key keymap "y" #'helixel-kill-ring-save)
    (define-key keymap "r" #'helixel-replace)
    (define-key keymap "R" #'helixel-replace-char)
    ;; ;I think helixel-yank can be replaced by helixel-replace
    ;; when helixel-replace-delete-char-p is nil
    (define-key keymap "p" #'helixel-yank)
    (define-key keymap "P" #'helixel-yank-before)
    (define-key keymap "." #'helixel-repeat-edit)

    (define-key keymap "x" #'helixel-select-line)
    (define-key keymap "v" #'helixel-begin-selection)
    (define-key keymap (kbd "C-v") #'helixel-select-rectangle)
    (define-key keymap "u" #'undo)
    (define-key keymap "U" #'undo-redo)
    (define-key keymap "o" #'helixel-insert-newline)
    (define-key keymap "O" #'helixel-insert-prevline)
    (define-key keymap "<" #'helixel-indent-left)
    (define-key keymap ">" #'helixel-indent-right)


    ;; State switching
    (define-key keymap "i" #'helixel-insert)
    (define-key keymap "I" #'helixel-insert-beginning-line)
    (define-key keymap "a" #'helixel-insert-after)
    (define-key keymap "A" #'helixel-insert-after-end-line)
    (define-key keymap ":" #'helixel-execute-command)
    ;; ESC is defined as the meta-prefix-key, so we can't simply
    ;; rebind "ESC".  Instead, rebind [escape].  More info:
    ;; https://emacs.stackexchange.com/questions/14755/
    ;; how-to-remove-bindings-to-the-esc-prefix-key
    (define-key keymap [escape] #'keyboard-quit)
    (define-key keymap (kbd "DEL") (lambda () (interactive)))

    ;; Movement keys
    (define-key keymap "h" #'helixel-backward-char)
    (define-key keymap "l" #'helixel-forward-char)
    (define-key keymap "j" #'helixel-next-line)
    (define-key keymap "k" #'helixel-previous-line)
    (define-key keymap "G" #'helixel-goto-line)
    (define-key keymap "%" #'mark-whole-buffer)
    (define-key keymap ";" #'helixel-action-cycle)
    (define-key keymap (kbd "C-f") #'helixel-scroll-up-command)
    (define-key keymap (kbd "C-b") #'helixel-scroll-down-command)
    (define-key keymap (kbd "1") (kbd "C-u 1"))
    (define-key keymap (kbd "2") (kbd "C-u 2"))
    (define-key keymap (kbd "3") (kbd "C-u 3"))
    (define-key keymap (kbd "4") (kbd "C-u 4"))
    (define-key keymap (kbd "5") (kbd "C-u 5"))
    (define-key keymap (kbd "6") (kbd "C-u 6"))
    (define-key keymap (kbd "7") (kbd "C-u 7"))
    (define-key keymap (kbd "8") (kbd "C-u 8"))
    (define-key keymap (kbd "9") (kbd "C-u 9"))
    (define-key keymap (kbd "0") (kbd "C-u 0"))

    (define-key keymap "w" #'helixel-forward-word-start)
    (define-key keymap "W" #'helixel-forward-WORD-start)
    (define-key keymap "e" #'helixel-forward-word-end)
    (define-key keymap "E" #'helixel-forward-WORD-end)
    (define-key keymap "b" #'helixel-backward-word-start)
    (define-key keymap "B" #'helixel-backward-WORD)
    (define-key keymap "v" #'helixel-backward-word-end)

    ;; Unimpared
    (define-key keymap (kbd "]d") #'flymake-goto-next-error)
    (define-key keymap (kbd "[d") #'flymake-goto-prev-error)
    
    (set-keymap-parent helixel-textobj-map helixel-textobj-inner-map)
    (define-key helixel-textobj-map "i" helixel-textobj-inner-map)
    (define-key helixel-textobj-map "a" helixel-textobj-outer-map)
    (define-key helixel-textobj-map "s" #'helixel-surround-add)
    (define-key helixel-textobj-map "t" #'helixel-surround-add-tag)
    (define-key helixel-textobj-map "d" #'helixel-surround-delete)
    (define-key helixel-textobj-map "r" #'helixel-surround-replace)
    (define-key keymap (kbd "m") 'helixel-textobj-map)

    ;; Goto mode
    (define-key keymap "g" 'helixel-goto-map)
    (define-key helixel-goto-map "l" #'helixel-go-end-line)
    (define-key helixel-goto-map "h" #'helixel-go-beginning-line)
    (define-key helixel-goto-map "s" #'helixel-go-first-nonwhitespace)
    (define-key helixel-goto-map "g" #'helixel-go-beginning-buffer)
    (define-key helixel-goto-map "e" #'helixel-go-end-buffer)
    (define-key helixel-goto-map "j" #'helixel-next-line)
    (define-key helixel-goto-map "k" #'helixel-previous-line)
    (define-key helixel-goto-map "r" #'xref-find-references)
    (define-key helixel-goto-map "d" #'xref-find-definitions)
    (define-key helixel-goto-map "y" #'eglot-find-typeDefinition)
    (define-key helixel-goto-map "i" #'eglot-find-implementation)


    ;; View mode
    (define-key keymap "z" 'helixel-view-map)
    (define-key helixel-view-map "z" #'recenter-top-bottom)

    ;; Space mode
    (define-key keymap (kbd "SPC") 'helixel-space-map)
    (define-key helixel-space-map "f" #'project-find-file)
    (define-key helixel-space-map "b" #'project-switch-to-buffer)
    (define-key helixel-space-map "j" #'project-switch-project)
    (define-key helixel-space-map "/" #'project-find-regexp)
    (define-key helixel-space-map "a" #'eglot-code-action-quickfix)
    (define-key helixel-space-map "r" #'eglot-rename)
    (define-key helixel-space-map "d" #'flymake-show-buffer-diagnostics)

    ;; Window mode
    (define-key keymap (kbd "C-w") 'helixel-window-map)
    (define-key helixel-window-map "h" #'windmove-left)
    (define-key helixel-window-map "l" #'windmove-right)
    (define-key helixel-window-map "j" #'windmove-down)
    (define-key helixel-window-map "k" #'windmove-up)
    (define-key helixel-window-map "w" #'other-window)
    (define-key helixel-window-map "v" #'split-window-right)
    (define-key helixel-window-map "s" #'split-window-below)
    (define-key helixel-window-map "q" #'delete-window)
    (define-key helixel-window-map "o" #'delete-other-windows)

    keymap)
  "Keymap for Helixel normal state.")

(defvar helixel-visual-state-keymap
  (let ((keymap (make-sparse-keymap)))
    (set-keymap-parent keymap helixel-normal-state-keymap)
    (define-key keymap "v" #'helixel-visual-exit)
    (define-key keymap [escape] #'helixel-visual-exit)
    keymap)
  "Keymap for Helixel visual state.  Inherits from normal state keymap.")

(defvar helixel-motion-state-keymap
  (let ((keymap (make-keymap)))
    (suppress-keymap keymap t)
    keymap)
  "Keymap for Helixel motion state.")

(defvar helixel-insert-state-keymap
  (let ((keymap (make-keymap)))
    (define-key keymap [escape] #'helixel-insert-exit)
    keymap)
  "Keymap for Helixel insert state.")

(defvar helixel--state-to-keymap-alist
  `((insert . ,helixel-insert-state-keymap)
    (normal . ,helixel-normal-state-keymap)
    (visual . ,helixel-visual-state-keymap)
    (motion . ,helixel-motion-state-keymap)
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
`helixel--state-to-keymap-alist'.  When MODE is provided (e.g.,
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
  (unless (alist-get state helixel--state-to-keymap-alist)
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
    (let ((state-keymap (alist-get state helixel--state-to-keymap-alist)))
      (define-key state-keymap key def))))

(defun helixel--refresh-overriding-maps ()
  "Rebuild `minor-mode-overriding-map-alist' for the current buffer."
  (let ((state helixel--current-state)
        (state-mode (alist-get helixel--current-state helixel-state-mode-alist))
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
      (let ((base-keymap (alist-get state helixel--state-to-keymap-alist)))
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
          (make-composed-keymap inner-overrides helixel-textobj-inner-map)))
      (when outer-overrides
        (define-key helixel-textobj-map "a"
          (make-composed-keymap outer-overrides helixel-textobj-outer-map))))))

(define-minor-mode helixel-insert-mode
  "Helixel INSERT state minor mode."
  :lighter " helixel[I]"
  :init-value nil
  :interactive nil
  :global nil
  :keymap helixel-insert-state-keymap
  (if helixel-insert-mode
      (progn
        (setq-local helixel--current-state 'insert)
        (setq cursor-type 'bar))
    (setq-local helixel--current-state 'normal)))

;;;###autoload
(define-minor-mode helixel-motion-mode
  "Helixel MOTION state minor mode for read-only navigation.
Only j, k, g keys are available by default.
Use `helixel-define-key' to add major-mode specific bindings."
  :lighter " helixel[M]"
  :init-value nil
  :interactive nil
  :global nil
  :keymap helixel-motion-state-keymap
  (if helixel-motion-mode
      (progn
        (setq-local helixel--current-state 'motion)
        (setq cursor-type 'box)
        (helixel--refresh-overriding-maps))
    (setq-local helixel--current-state 'normal)))

(define-minor-mode helixel-visual-mode
  "Helixel VISUAL state minor mode."
  :lighter " helixel[V]"
  :init-value nil
  :interactive nil
  :global nil
  :keymap helixel-visual-state-keymap
  (if helixel-visual-mode
      (progn
        (setq-local helixel--current-state 'visual)
        (setq cursor-type 'box)
        (helixel--refresh-overriding-maps))
    (setq-local helixel--current-state 'normal)))

;;;###autoload
(define-minor-mode helixel-normal-mode
  "Helixel NORMAL state minor mode."
  :lighter " helixel[N]"
  :init-value nil
  :interactive t
  :global nil
  :keymap helixel-normal-state-keymap
  (if helixel-normal-mode
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
      (let* ((letters (split-string "abcdefghijklmnopqrstuvwxyz" "" t))
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
                               helixel-state-mode-alist)))
          (funcall mode -1))
      ;; Activate default state
      (let* ((state (helixel--default-state-for-buffer))
             (mode (alist-get state helixel-state-mode-alist)))
        (funcall mode (if status status 1))
        (helixel--refresh-overriding-maps)))))

;;;###autoload
(defun helixel-mode-all (&optional status)
  "Activate Helixel mode in all buffers with their default states.

Argument STATUS is passed through to `helixel-mode-maybe-activate'."
  (interactive)
  (helixel-action-start 'state 'toggle)
  ;; Set global mode to t before iterating over the buffers so that we
  ;; send the status directly to `helixel-normal-mode' (which checks for
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
     (helixel-normal-mode (helixel-normal-mode -1))
     (helixel-insert-mode (helixel-insert-mode -1))
     (helixel-motion-mode (helixel-motion-mode -1))
     (helixel-visual-mode (helixel-visual-mode -1)))
    (advice-remove #'keyboard-quit #'helixel--clear-data)
    (advice-remove #'keyboard-quit #'helixel--cancel-action)
    (remove-hook 'after-change-major-mode-hook #'helixel-mode-maybe-activate)))

(provide 'helixel-common)
;;; helixel-common.el ends here
