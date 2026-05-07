;;; helixel-repeat.el --- Repeat edit (`.`) infrastructure  -*- lexical-binding: t; -*-

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

(require 'helixel-action)

;; ---------------------------------------------------------------------------
;; Selection Context (helixel--repeat-sel-ctx)
;;
;; Set by textobj/line/rect/movement selection commands.
;; Consumed by helixel--record-edit when an edit command executes.
;;
;; Schema:
;;   (:fn FUNCTION :kind textobj|line|rect)     -- textobj / line / rect
;;   (:kind movement :moves ((CMD . COUNT) ...)) -- visual-mode moves
;;
;; Replay is dispatched through a unified
;; helixel--recreate-selection function.

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
;; Last Edit Transaction

(defvar-local helixel--last-edit nil
  "Plist describing the last edit for dot-repeat (`.`).
Updated on every edit, held in a single buffer-local slot.

Keys:
  :operator     symbol    ;; kill|change|copy|replace|paste-after|paste-before
                          ;; |indent-left|indent-right|replace-char|insert-text
  :sel-ctx      plist|nil ;; Selection context, or nil
  :change-text  string|nil ;; Text inserted during change/insert
  :replace-char char|nil  ;; Char for replace-char")

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
  "Record edit OPERATOR with current `helixel--repeat-sel-ctx'.
EXTRA: additional keyword-value pairs (:change-text, :replace-char, ...).
Consumes `helixel--repeat-sel-ctx' (sets to nil).
Also creates an edit action in the ring (for `;' jumping)."
  (unless helixel--inhibit-repeat-record
    (let ((edit (append `(:operator ,operator
                          :sel-ctx ,helixel--repeat-sel-ctx)
                        extra)))
      (setq helixel--last-edit edit
            helixel--repeat-sel-ctx nil)
      (helixel-action-start 'edit operator)
      (apply #'helixel--live-edit-set operator
             (plist-get (plist-get edit :sel-ctx) :kind)
             (plist-get (plist-get edit :sel-ctx) :fn)
             extra)
      (helixel-action-commit))))

;; ---------------------------------------------------------------------------
;; Selection Replay

(defun helixel--recreate-selection (sel-ctx)
  "Recreate a selection from SEL-CTX at the current point.
Dispatches on :kind to use the appropriate replay strategy."
  (when sel-ctx
    (let ((kind (plist-get sel-ctx :kind)))
      (cond
       ((plist-get sel-ctx :fn)
        (funcall (plist-get sel-ctx :fn)))
       ((eq kind 'movement)
        (let ((helixel--current-state 'visual))
          (dolist (m (reverse (plist-get sel-ctx :moves)))
            (dotimes (_ (cdr m))
              (funcall (car m))))))))))

;; ---------------------------------------------------------------------------
;; Replay (bound to `.`)

(declare-function helixel-kill-thing-at-point "helixel-common")
(declare-function helixel-kill-ring-save "helixel-common")
(declare-function helixel-replace "helixel-common")
(declare-function helixel-replace-char "helixel-common")
(declare-function helixel-yank "helixel-common")
(declare-function helixel-yank-before "helixel-common")
(declare-function helixel-indent-left "helixel-common")
(declare-function helixel-indent-right "helixel-common")
(declare-function helixel--rect-change "helixel-common")
(declare-function helixel-insert-exit "helixel-common")
(declare-function helixel--delete-selection "helixel-common")

(defun helixel--repeat-change-core ()
  "Repeat change: kill selection, insert stored :change-text."
  (let ((text (plist-get helixel--last-edit :change-text)))
    (cond
     ((and (use-region-p) (eq (helixel--selection-type) 'rect))
      (helixel--rect-change)
      (when text (insert text))
      (helixel-insert-exit))
     (t
      (helixel--delete-selection)
      (when text (insert text))))))

(defun helixel-repeat-edit ()
  "Repeat the last editing operation at point (bound to `.`)."
  (interactive)
  (unless helixel--last-edit
    (user-error "No previous edit to repeat"))
  (let* ((op (plist-get helixel--last-edit :operator))
         (sel-ctx (plist-get helixel--last-edit :sel-ctx))
         (helixel--inhibit-repeat-record t))
    (helixel--recreate-selection sel-ctx)
    (pcase op
      ('kill (helixel-kill-thing-at-point))
      ('copy (helixel-kill-ring-save))
      ('replace (helixel-replace))
      ('replace-char (helixel-replace-char
                      (plist-get helixel--last-edit :replace-char)))
      ('paste-after (helixel-yank))
      ('paste-before (helixel-yank-before))
      ('indent-left (helixel-indent-left))
      ('indent-right (helixel-indent-right))
      ('change (helixel--repeat-change-core))
      ('insert-text (insert (or (plist-get helixel--last-edit :change-text) ""))))))

(provide 'helixel-repeat)
;;; helixel-repeat.el ends here
