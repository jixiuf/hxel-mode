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
;; Dot-repeat (`.`) infrastructure for helixel-mode.
;;
;; Records the last editing operation as a *transaction* — operator
;; plus selection context — and replays it on demand.
;;
;; Architecture:
;;   Selection commands → set helixel--repeat-sel-ctx
;;   Editing commands  → helixel--record-edit → helixel--last-edit
;;   `.` key           → helixel-repeat-edit → replay
;;
;; Dependencies: helixel-action (for action ring integration).
;; Editing commands used during replay live in helixel-common,
;; loaded at runtime via declare-function.

;;; Code:

(require 'cl-lib)
(require 'helixel-action)
(require 'helixel-edit)
(require 'helixel-delimiter)

(defvar helixel--inhibit-action-track)

;; ---------------------------------------------------------------------------
;; Selection Context (helixel--repeat-sel-ctx)
;;
;; Set by textobj/line/rect/movement selection commands.
;; Consumed by helixel--record-edit when an edit command executes.
;;
;; Schema is the *selection descriptor* understood by
;; `helixel-sel-recreate' — see helixel-edit.el.  Any plist with a
;; recognised :kind (or legacy :fn) works; replay dispatches via
;; cl-defmethod.

(defvar-local helixel--repeat-sel-ctx nil
  "Selection context for dot-repeat.
Set by textobj / linewise / rect selection commands, and accumulated
by movement commands during visual mode.  Read and consumed by
`helixel--record-edit'.

Keys:
  :fn    function       ;; For textobj/line/rect: call to create selection
  :kind  symbol         ;; textobj | line | rect | movement
  :moves ((CMD . COUNT) ...)  ;; For movement: accumulated command sequence")

;; ---------------------------------------------------------------------------
;; Last Edit Transaction (stored as helixel--last-tx)

(defvar-local helixel--last-tx nil
  "The most recent edit transaction (:op :sel :payload :marker).
Built by `helixel-edit-make', stored by `helixel--record-edit-tx'.
Replace `helixel--last-edit' — unified schema shared by repeat,
action ring, and edit commands.

Mirrors `(car helixel--edit-ring)'.  See `helixel-edit.el' for the
full transaction schema.")

(defcustom helixel-edit-ring-max 64
  "Maximum number of past edit transactions retained in the ring.
Older entries are discarded.  Set to 0 or nil to disable the ring
(`helixel--last-tx' still works)."
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

(provide 'helixel-repeat)
;;; helixel-repeat.el ends here
