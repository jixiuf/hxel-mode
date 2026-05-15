;;; helixel-repeat.el --- Repeat edit (`.`) system -*- lexical-binding: t; -*-

;; Copyright (C) 2026  jixiuf

;; Author: jixiuf
;; Keywords: convenience

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
;;
;; Dot-repeat (`.') infrastructure for helixel-mode.
;;
;; Records every editing operation as a *transaction* (see helixel-edit.el)
;; into a per-buffer ring; `.' replays the head transaction, optionally with
;; a numeric prefix.  `helixel-repeat-edit-pick' chooses an older entry from
;; the ring via completing-read.
;;
;; Architecture:
;;   Selection commands  → set helixel--repeat-sel-ctx (selection descriptor)
;;   Editing commands    → helixel--record-edit → helixel--last-tx + ring
;;   `.'                 → helixel-repeat-edit → sel-recreate + op-runner
;;
;; Both selection recreation and op execution use the `helixel-sel' struct
;; closures and the operator symbol-property registry in helixel-edit.el.
;; This module knows nothing about specific kinds or operators.
;;
;; Dependencies: helixel-action (action ring) and helixel-edit (kernel).

;;; Code:

(require 'cl-lib)
(require 'helixel-action)
(require 'helixel-edit)
(require 'helixel-delimiter)

(defvar helixel--inhibit-action-track)
(defvar helixel--selection-type)
(declare-function helixel-search--search "helixel-search"
                  (pattern dir &optional bound noerror))

;; ---------------------------------------------------------------------------
;; Selection Context (helixel--repeat-sel-ctx)
;;
;; Set by textobj/line/rect/movement selection commands; consumed by
;; helixel--record-edit when the next edit fires.  Its shape is the
;; *selection descriptor* understood by `helixel-sel-call-recreate' — see
;; helixel-edit.el for the `helixel-sel' struct schema.

(defvar-local helixel--repeat-sel-ctx nil
  "Selection descriptor for dot-repeat.
Written by selection commands (textobj / line / rect / movement),
consumed by `helixel--record-edit'.  See `helixel-sel' struct in
helixel-edit.el for the set of recognised :kind values.")

;; ---------------------------------------------------------------------------
;; Last Edit Transaction (stored as helixel--last-tx)

(defvar helixel--last-tx nil
  "The most recent edit transaction (see `helixel-edit-make').
Cross-buffer: `.` replays the last edit regardless of which buffer
it was recorded in.  Is `eq' to `(car helixel--edit-ring)' within
the recording buffer, but may differ after a buffer switch.
May be re-pointed by `helixel-repeat-edit-pick' to replay an older entry.")

(defcustom helixel-edit-ring-max 64
  "Maximum number of past edit transactions retained in the ring.
Older entries are discarded.  Set to 0 or nil to disable the ring
\(`helixel--last-tx' still works)."
  :type 'integer
  :group 'helixel)

(defvar-local helixel--edit-ring nil
  "List of recent edit transactions, newest first.
`helixel--last-tx' is always `eq' to `(car helixel--edit-ring)'
while both are non-nil.  Maintained by `helixel--edit-ring-push'.")

(defun helixel--edit-ring-push (tx)
  "Push TX onto the edit ring, deduplicating against the current head.
Trims to `helixel-edit-ring-max'."
  (when tx
    (unless (and helixel--edit-ring
                 (helixel-edit-equal-p tx (car helixel--edit-ring)))
      (push tx helixel--edit-ring)
      (when (and helixel-edit-ring-max
                 (> (length helixel--edit-ring) helixel-edit-ring-max))
        (setcdr (nthcdr (1- helixel-edit-ring-max) helixel--edit-ring)
                nil)))))


(defvar-local helixel--change-track-marker nil
  "Marker at position before entering insert during a change/insert operation.
Set by change and insert-entry commands.  Read in `helixel-insert-exit'
to extract :change-text.")

(defvar helixel--inhibit-repeat-record nil
  "When non-nil, `helixel--record-edit' is a no-op.
Bound during `helixel-repeat-edit' to prevent re-recording.
Also bound in compound commands (e.g. `helixel-replace' calling
`helixel-yank') to avoid double-recording.")

;; ---------------------------------------------------------------------------
;; Kmacro-based insert recorder
;;
;; Records insert-mode keystrokes via `start-kbd-macro' /
;; `end-kbd-macro'.  Also records the *commands* executed for each
;; key via `pre-command-hook', so replay can call the exact same
;; commands regardless of keymap differences (normal vs insert mode).

(defvar-local helixel--insert-commands nil
  "List of commands executed during insert-mode recording.
Recorded by `helixel--on-insert-command' via `pre-command-hook'.
Cleared and returned by `helixel--insert-finish'.")

(defun helixel--on-insert-command ()
  "Pre-command-hook: record `this-command' during insert recording.
Skips `helixel-insert-exit' (the exit command itself)."
  (when helixel--insert-commands
    (unless (eq this-command 'helixel-insert-exit)
      (push this-command helixel--insert-commands))))

(defun helixel--insert-begin ()
  "Start insert-mode recording via kmacro.
Caller must also switch state to insert.

Does NOT call `helixel--switch-state' — that stays in helixel-common.el
because helixel-repeat.el does not depend on helixel-common.el."
  (unless (or defining-kbd-macro executing-kbd-macro)
    (let ((inhibit-message t))
      (start-kbd-macro nil)))
  (setq helixel--insert-commands nil)
  (add-hook 'pre-command-hook #'helixel--on-insert-command nil t))

(defun helixel--insert-finish ()
  "End insert-mode kmacro recording.
Returns (KEYS . COMMANDS).  KEYS is the captured key sequence vector
or nil.  COMMANDS is the list of executed commands (oldest first),
or nil.  Strips trailing ESC from keys on Emacs versions that include it."
  (remove-hook 'pre-command-hook #'helixel--on-insert-command t)
  (let ((keys (if defining-kbd-macro
                  (let ((inhibit-message t))
                    (end-kbd-macro nil)
                    (let ((raw last-kbd-macro))
                      (prog1 (cond ((= (length raw) 0) nil)
                                   ((= (aref raw (1- (length raw))) ?\e)
                                    (if (> (length raw) 1)
                                        (substring raw 0 -1)
                                      nil))
                                   (t raw))
                        (setq last-kbd-macro nil))))
                nil))
        (cmds (nreverse helixel--insert-commands)))
    (setq helixel--insert-commands nil)
    (cons keys cmds)))

;; ---------------------------------------------------------------------------
;; Recording (called by editing commands in helixel-common)

(defun helixel--record-edit (operator &rest extra)
  "Record edit OPERATOR with current selection context and EXTRA payload.
Consumes `helixel--repeat-sel-ctx'.  Looks up the runner and display
from the operator registry and stores them in the transaction so
`helixel--execute-edit' can dispatch without registry lookups.
Builds a transaction via `helixel-edit-make', pushes it onto
`helixel--edit-ring', and stores it as `helixel--last-tx'.
Also notifies the action ring so `;' jumping picks up the new edit.

NOTE: Caller is responsible for calling `helixel-action-start' first.
The `helixel-define-command' macro handles this automatically."
  (unless (or helixel--inhibit-repeat-record executing-kbd-macro)
    (let* ((runner (helixel-edit-op-runner operator))
           (tx (apply #'helixel-edit-make operator
                      helixel--repeat-sel-ctx
                      :runner runner
                      extra)))
      (let ((new-tx (copy-helixel-edit tx)))
        (setf (helixel-edit-display-field new-tx)
              (helixel-edit-op-display operator tx))
        (setq tx new-tx))
      (setq helixel--repeat-sel-ctx nil
            helixel--last-tx tx)
      (helixel--edit-ring-push tx)
      (helixel--live-edit-set tx)
      (helixel-action-commit))))

;; ---------------------------------------------------------------------------
;; Selection Replay

(defun helixel--recreate-selection (sel-ctx)
  "Recreate a selection from SEL-CTX at the current point.
Thin wrapper around `helixel-sel-call-recreate' —
dispatches on struct closures."
  (when sel-ctx
    (helixel-sel-call-recreate sel-ctx)))

;; ---------------------------------------------------------------------------
;; Insert-keys accessor (consumed by helixel-common.el's op runners)

(defsubst helixel--repeat-get-keys (tx)
  "Return the :keys key-sequence vector from TX payload, or nil."
  (plist-get (helixel-edit-payload tx) :keys))

(defun helixel--execute-keys (keys &optional commands)
  "Execute recorded KEYS with optional COMMANDS.
When COMMANDS are available (from `pre-command-hook' recording),
call each recorded command directly — keymap-independent.
`self-insert-command' is handled specially via `insert-char' with
the corresponding key (avoids `last-command-event' dependency).
When COMMANDS are nil, fall back to key-based replay."
  (let ((helixel--inhibit-repeat-record t)
        (helixel--inhibit-action-track t))
    (if commands
        ;; Command-based replay: call recorded commands directly
        (cl-loop for cmd in commands
                 for key in (append keys nil)
                 do (if (eq cmd 'self-insert-command)
                        (insert-char key 1 t)
                      (call-interactively cmd)))
      ;; Key-based fallback: insert-char for characters,
      ;; execute-kbd-macro for non-characters.
      (dolist (key (append keys nil))
        (if (characterp key)
            (insert-char key 1 t)
          (let ((win (selected-window)))
            (if (and win (not (eq (window-buffer win)
                                  (current-buffer))))
                (let ((prev-buf (window-buffer win)))
                  (unwind-protect
                      (progn
                        (set-window-buffer win (current-buffer))
                        (execute-kbd-macro (vector key) 1))
                    (set-window-buffer win prev-buf)))
              (execute-kbd-macro (vector key) 1))))))))

;; ---------------------------------------------------------------------------
;; ---------------------------------------------------------------------------
;; Pre-recreation auto-advance (tag-based)

(defun helixel--repeat-do-advance (advance sel)
  "Execute ADVANCE before recreating selection SEL.
ADVANCE is an operator's :repeat-advance property value."
  (when advance
    (let ((kind (and sel (helixel-sel-get-kind sel))))
      (cond
       ((eq advance 'line)
        (when (eq kind 'line)
          (let ((dir (if (eq (helixel-sel-line-dir sel) 'backward)
                         -1 1)))
            (forward-line dir))))
       ((functionp advance)
        (funcall advance sel))))))

;; ---------------------------------------------------------------------------
;; Execution dispatcher — single entry point for replay
;;
;; All op runners live in their owning modules and self-register via
;; `helixel-edit-defop'.  This module knows nothing about specific ops.

(defun helixel--execute-edit (tx)
  "Execute transaction TX on the current buffer.
Does NOT record, does NOT switch state.
Calls the :runner stored in TX (set at record time by
`helixel-edit-op-runner').  If :runner is missing,
falls back to the operator registry."
  (when-let* ((runner (or (helixel-edit-runner tx)
                         (helixel-edit-op-runner (helixel-edit-op tx)))))
    (funcall runner tx)))

;; ---------------------------------------------------------------------------
;; Replay (bound to `.`)

(defvar-local helixel--repeat-has-preview nil
  "Set to t by `helixel-repeat-selection', consumed by `helixel-repeat-edit'.
When t, `helixel-repeat-edit' uses the active region directly
instead of recreating the selection, so the preview is honoured.")

(defun helixel-repeat-edit (&optional raw-prefix)
  "Repeat the last editing operation at point (bound to `.`).

Prefix RAW-PREFIX semantics with search-based selections:
  3.          -> 3 times in stored direction
  0.          -> all remaining matches in stored direction
  \\[universal-argument] - 3 . -> 3 times, opposite direction
  \\[universal-argument] .    -> all matches in entire buffer

For line selections, 0. and \\[universal-argument] . replay on all
remaining / entire buffer lines respectively.

All iterations are amalgamated into a single undo step.
During keyboard macro recording `executing-kbd-macro' is non-nil
this command replays the current `helixel--last-tx' but does not
record a new edit (edit recording is inhibited during kmacro).
Failure during replay is reported but does not discard the stored edit."
  (interactive "P")
  ;; During keyboard macro playback, silently ignore . if there
  ;; is no stored edit to replay (the macro was likely recorded
  ;; in a different context).
  (when (and executing-kbd-macro (not helixel--last-tx))
    (user-error "No previous edit to repeat (kmacro playback)"))
  (unless helixel--last-tx
    (user-error "No previous edit to repeat"))
  (let* ((tx helixel--last-tx)
         (helixel--inhibit-repeat-record t)
         (helixel--inhibit-action-track t)
         (all-buffer-p (consp raw-prefix))        ; C-u . -> (4)
         (all-dir-p    (and (integerp raw-prefix)
                            (eql raw-prefix 0)))   ; 0. -> 0
         (reverse-p    (and (integerp raw-prefix)
                            (< raw-prefix 0)))     ; C-u -3 . -> -3
         (n            (cond ((not raw-prefix) 1)
                             ((consp raw-prefix)
                              (abs (prefix-numeric-value raw-prefix)))
                             (t (abs raw-prefix))))
         (use-preview helixel--repeat-has-preview)
         (sel (helixel-edit-sel tx))
         (search-sel-p (and sel
                            (eq (helixel-sel-get-kind sel) 'search)))
         (line-sel-p   (and sel
                            (eq (helixel-sel-get-kind sel) 'line))))
    (setq helixel--repeat-has-preview nil)
    (condition-case err
        (undo-amalgamate-change-group
          (cond
           ;; --- Entire buffer: point-min -> forward, all matches ---
           ((and all-buffer-p search-sel-p)
            (goto-char (point-min))
            (let ((pat (helixel-sel-search-pattern sel))
                  (entry-kind (helixel-sel-search-entry-kind sel)))
              (if entry-kind
                  ;; Insert ops: simple search+insert, guard
                  ;; against double-insert on original match.
                  (let ((txt (or (plist-get
                                  (helixel-edit-payload tx)
                                  :inserted-text)
                                 (plist-get
                                  (helixel-edit-payload tx)
                                  :text)
                                 "")))
                    (while (helixel-search--search
                            pat 'forward nil 'noerror)
                      (let* ((is-insert (eq entry-kind 'insert))
                             (pos (if is-insert
                                      (match-beginning 0)
                                    (match-end 0)))
                             ;; For insert, txt sits *before* the
                             ;; match; for append, right *after*.
                             (guard-pos (if is-insert
                                            (- pos (length txt))
                                          pos)))
                        (unless (save-excursion
                                  (goto-char guard-pos)
                                  (looking-at
                                   (regexp-quote txt)))
                          (goto-char pos)
                          (insert txt)
                          (when is-insert
                            (goto-char (match-end 0)))))))
                ;; Change/delete ops: region + runner.
                (while (helixel-search--search
                        pat 'forward nil 'noerror)
                  (push-mark (match-beginning 0) t t)
                  (goto-char (match-end 0))
                  (setq helixel--selection-type 'char)
                  (helixel--execute-edit tx)))))
           ;; --- Entire buffer: point-min -> forward, all lines ---
           ((and all-buffer-p line-sel-p)
            (goto-char (point-min))
            (let* ((advance (helixel-edit-op-advance
                             (helixel-edit-op tx))))
              (when (eq advance 'line)
                (forward-line 1))
              (condition-case nil
                  (while t
                    (helixel--recreate-selection sel)
                    (helixel--execute-edit tx)
                    (if (eq advance 'line)
                        (when (/= (forward-line 1) 0)
                          (signal 'user-error nil))
                      (when (eobp)
                        (signal 'user-error nil))))
                (user-error nil))))
           ;; --- All remaining matches in stored direction ---
           ((and all-dir-p search-sel-p)
            ;; recreate-selection handles skip logic, signals
            ;; user-error on search-failed -> silent stop.
            (condition-case nil
                (while t
                  (helixel--recreate-selection sel)
                  (helixel--execute-edit tx))
              (user-error nil)
              (search-failed nil)))
           ;; --- All remaining lines in stored direction ---
           ((and all-dir-p line-sel-p)
            (let* ((line-dir (if (eq (helixel-sel-line-dir sel)
                                     'backward)
                                 -1 1))
                   (advance (helixel-edit-op-advance
                             (helixel-edit-op tx))))
              (when (eq advance 'line)
                (forward-line line-dir))
              (condition-case nil
                  (while t
                    (helixel--recreate-selection sel)
                    (helixel--execute-edit tx)
                    (if (eq advance 'line)
                        (when (/= (forward-line line-dir) 0)
                          (signal 'user-error nil))
                      (when (if (eq line-dir -1) (bobp) (eobp))
                        (signal 'user-error nil))))
                (user-error nil))))
           ;; --- Reverse direction |N| times ---
           ((and reverse-p search-sel-p)
            (let* ((orig-dir (helixel-sel-search-dir sel))
                   (flipped-dir (if (eq orig-dir 'forward)
                                    'backward 'forward))
                   (flipped (helixel-sel-update-ctx sel
                              :dir flipped-dir)))
              (condition-case nil
                  (dotimes (_ n)
                    (helixel--recreate-selection flipped)
                    (helixel--execute-edit tx))
                (user-error nil)
                (search-failed nil))))
           ;; --- Non-search sel (not line), 0 or C-u: fall back to once ---
           ((and (or all-dir-p all-buffer-p) sel
                 (not line-sel-p))
            (helixel--recreate-selection sel)
            (helixel--execute-edit tx))
           ;; --- Normal N times (preview path) ---
           (use-preview
            (dotimes (_ n)
              (helixel--execute-edit tx)))
           ;; --- Normal N times (recreate + execute) ---
            (t
             (when (and sel (eq (helixel-sel-get-kind sel) 'textobj))
               (deactivate-mark))
             (let ((advance (helixel-edit-op-advance
                             (helixel-edit-op tx))))
               (dotimes (_ n)
                 (helixel--repeat-do-advance advance sel)
                 (helixel--recreate-selection sel)
                 (helixel--execute-edit tx))))))
      ((error quit)
       (message "helixel-repeat-edit aborted: %s"
                (error-message-string err))))))

;; ---------------------------------------------------------------------------
;; Repeat Selection (bound to `,`)

(defun helixel-repeat-selection (&optional count)
  "Repeat the last selection without applying any edit (bound to `,`).
Extracts the selection descriptor from `helixel--last-tx' and
replays it at point.  In visual state extends the current selection;
in normal state recreates it from scratch.
With COUNT, passes it as the count for line/rect/textobj selections.

Sets `helixel--repeat-has-preview' so a subsequent `.` uses this
region directly instead of recreating."
  (interactive "p")
  (unless helixel--last-tx
    (user-error "No previous edit"))
  (let ((sel-ctx (helixel-edit-sel helixel--last-tx)))
    (unless sel-ctx
      (user-error (concat "Previous edit has no selection to repeat."
                          "  Use a textobj (e.g. ciw)"
                          " or line/rect selection first")))
    (let ((n (or count 1)))
      (let ((ctx (if (> n 1)
                     (helixel-sel-update-ctx sel-ctx :count n)
                   sel-ctx)))
        (helixel--recreate-selection ctx)
        (setq helixel--repeat-has-preview t)))))

(defun helixel-repeat-edit-pick ()
  "Choose a past edit from `helixel--edit-ring' and replay it.
The chosen entry becomes the new `helixel--last-tx'."
  (interactive)
  (unless helixel--edit-ring
    (user-error "Edit ring is empty"))
  (let* ((items (cl-loop for tx in helixel--edit-ring
                         for i from 0
                         collect (cons (format "%3d  %s" i
                                               (helixel-edit-display tx))
                                       tx)))
         (choice (completing-read "Repeat edit: " items nil t))
         (tx (cdr (assoc choice items))))
    (when tx
      (setq helixel--last-tx tx)
      (helixel-repeat-edit))))

(defun helixel-repeat-debug ()
  "Pretty-print `helixel--last-tx' and the head of `helixel--edit-ring'.
Intended for development — inspect what dot-repeat would replay next."
  (interactive)
  (require 'pp)
  (let ((buf (get-buffer-create "*helixel-repeat-debug*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (emacs-lisp-mode)
        (insert ";; helixel--last-tx (display: "
                (or (and helixel--last-tx
                         (helixel-edit-display helixel--last-tx))
                    "<none>")
                ")\n")
        (pp helixel--last-tx (current-buffer))
        (insert "\n;; helixel--edit-ring ("
                (number-to-string (length helixel--edit-ring))
                " entries):\n")
        (dolist (tx helixel--edit-ring)
          (insert (format ";;   %s\n" (helixel-edit-display tx))))
        (goto-char (point-min))))
    (display-buffer buf)))

(provide 'helixel-repeat)
;;; helixel-repeat.el ends here
