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
;; Both selection recreation and op execution dispatch through registries
;; in helixel-edit.el (cl-defgeneric helixel-sel-recreate, op runner table).
;; This module knows nothing about specific kinds or operators.
;;
;; Dependencies: helixel-action (action ring) and helixel-edit (kernel).

;;; Code:

(require 'cl-lib)
(require 'helixel-action)
(require 'helixel-edit)
(require 'helixel-delimiter)

(defvar helixel--inhibit-action-track)

;; ---------------------------------------------------------------------------
;; Selection Context (helixel--repeat-sel-ctx)
;;
;; Set by textobj/line/rect/movement selection commands; consumed by
;; helixel--record-edit when the next edit fires.  Its shape is the
;; *selection descriptor* understood by `helixel-sel-recreate' — see
;; helixel-edit.el for the full schema.

(defvar-local helixel--repeat-sel-ctx nil
  "Selection descriptor for dot-repeat.
Written by selection commands (textobj / line / rect / movement),
consumed by `helixel--record-edit'.  See `helixel-sel-recreate' for
the set of recognised :kind values.")

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

(defcustom helixel-repeat-change-method 'text
  "How `.` replays change/insert operations.
`text' replays the stored text string (default, fast).
`keys' replays the raw key sequence so abbrev, yasnippet,
and electric-indent fire again during repeat."
  :type '(choice (const text) (const keys))
  :group 'helixel)

(defvar-local helixel--insert-keys nil
  "List of key-vectors recorded during the current insert session.
Each element is a vector as returned by `this-command-keys-vector'.
Built up by `helixel--record-insert-key' (post-command-hook in
insert state).  Consumed by `helixel-insert-exit' to populate the
:keys payload field.")

(defun helixel--record-insert-key ()
  "Post-command-hook: push `this-command-keys-vector' onto `helixel--insert-keys'.
No-op when `helixel--insert-keys' is nil (not recording).
The first call converts the sentinel t into a real list."
  (when helixel--insert-keys
    (if (eq helixel--insert-keys t)
        (setq helixel--insert-keys (list (this-command-keys-vector)))
      (push (this-command-keys-vector) helixel--insert-keys))))

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
;; Recording (called by editing commands in helixel-common)

(defun helixel--record-edit (operator &rest extra)
  "Record edit OPERATOR with current selection context and EXTRA payload.
Consumes `helixel--repeat-sel-ctx'.  Builds a transaction via
`helixel-edit-make', pushes it onto `helixel--edit-ring', and stores
it as `helixel--last-tx'.  Also notifies the action ring so `;'
jumping picks up the new edit.

NOTE: Caller is responsible for calling `helixel-action-start' first.
The `helixel-define-command' macro handles this automatically."
  (unless helixel--inhibit-repeat-record
    (let ((tx (apply #'helixel-edit-make operator
                     helixel--repeat-sel-ctx extra)))
      (setq helixel--repeat-sel-ctx nil
            helixel--last-tx tx)
      (helixel--edit-ring-push tx)
      (helixel--live-edit-set tx)
      (helixel-action-commit))))

;; ---------------------------------------------------------------------------
;; Selection Replay

(defun helixel--recreate-selection (sel-ctx)
  "Recreate a selection from SEL-CTX at the current point.
Thin wrapper around `helixel-sel-recreate' — dispatches on (:kind ...)."
  (when sel-ctx
    (helixel-sel-recreate (plist-get sel-ctx :kind) sel-ctx)))

;; ---------------------------------------------------------------------------
;; Insert-keys accessor (consumed by helixel-common.el's op runners)

(defsubst helixel--repeat-get-keys (tx)
  "Return the :keys key-sequence vector from TX payload, or nil."
  (plist-get (helixel-edit-payload tx) :keys))

(defun helixel--execute-keys (keys)
  "Execute KEYS (a key-sequence vector) in an insert-mode context.
Handles self-inserting characters and common editing keys (return,
backspace).  Works around an Emacs 32 `execute-kbd-macro' batch-mode
bug.  Abbrev, yasnippet, and electric-indent fire because we go
through `call-interactively'."
  (let ((helixel--inhibit-repeat-record t)
        (helixel--inhibit-action-track t))
    (dolist (key (append keys nil))
      (setq last-command-event key)
      (let ((cmd (key-binding (vector key) t)))
        (if (and cmd (not (eq cmd 'undefined)))
            (call-interactively cmd)
          (setq last-command-event key)
          (call-interactively #'self-insert-command))))))

;; ---------------------------------------------------------------------------
;; Execution dispatcher — single entry point for replay
;;
;; All op runners live in their owning modules and self-register via
;; `helixel-edit-defop'.  This module knows nothing about specific ops.

(defun helixel--execute-edit (tx)
  "Execute transaction TX on the current buffer.
Does NOT record, does NOT switch state.
Dispatches via the op registry in `helixel-edit'."
  (when-let* ((runner (helixel-edit-op-runner (helixel-edit-op tx))))
    (funcall runner tx)))

;; ---------------------------------------------------------------------------
;; Replay (bound to `.`)

(defun helixel-repeat-edit (&optional count)
  "Repeat the last editing operation at point (bound to `.`).
With numeric prefix COUNT, replay COUNT times.
Failure during replay is reported but does not discard the stored edit."
  (interactive "p")
  (unless helixel--last-tx
    (user-error "No previous edit to repeat"))
  (let ((tx helixel--last-tx)
        (helixel--inhibit-repeat-record t)
        (helixel--inhibit-action-track t)
        (n (or count 1)))
    (condition-case err
        (dotimes (_ n)
          (helixel--recreate-selection (helixel-edit-sel tx))
          (helixel--execute-edit tx))
      ((error quit)
       (message "helixel-repeat-edit aborted: %s" (error-message-string err))))))

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
