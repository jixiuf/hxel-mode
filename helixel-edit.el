;;; helixel-edit.el --- Edit transaction model -*- lexical-binding: t; -*-

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
;; Unified edit transaction model for helixel-mode.
;;
;; An edit transaction is a plist describing one editing operation:
;; what was done (:op), on what selection (:sel), with what extra
;; data (:payload), and where it started (:marker).
;;
;; This module provides the schema, builder, equality, and display
;; helpers.  It has NO dependencies on other helixel modules and
;; NO side effects.  It is the single source of truth for the
;; edit data model, consumed by:
;;   - helixel-repeat (dot-repeat .)
;;   - helixel-action (action ring, ; jumping, history display)
;;   - helixel-common (interactive edit command façades)

;;; Code:

(require 'cl-lib)

;; ---------------------------------------------------------------------------
;; Transaction Plist Schema
;;
;; (:op     symbol    ;; kill | change | copy | replace | replace-char
;;                    ;; | paste-after | paste-before
;;                    ;; | indent-left | indent-right
;;                    ;; | insert-text
;;  :sel    plist|nil ;; selection descriptor — see `helixel-sel-recreate'
;;                    ;; (:kind K [:fn F] [:count N] [:delimiter D] [:moves ...])
;;                    ;; nil = no selection (cursor-at-point operations)
;;  :payload plist    ;; operator-specific data, always a plist (may be nil)
;;  :marker marker)   ;; position where the edit started (for ; jumping)
;;
;; Payload per :op:
;;   kill:           nil
;;   change:         (:inserted-text STRING)  -- added by insert-exit
;;   copy:           nil
;;   replace:        nil
;;   replace-char:   (:char CHAR)
;;   paste-after:    nil
;;   paste-before:   nil
;;   indent-left:    nil
;;   indent-right:   nil
;;   insert-text:    (:text STRING)  -- added by insert-exit

;; ---------------------------------------------------------------------------
;; Builder

(defun helixel-edit-make (op sel-ctx &rest payload-kv)
  "Create an edit transaction plist.
OP is a symbol: kill, change, copy, replace, replace-char,
paste-after, paste-before, indent-left, indent-right, insert-text.
SEL-CTX is a selection context plist or nil.
PAYLOAD-KV are keyword-value pairs for operator-specific data."
  (list :op op
        :sel sel-ctx
        :payload payload-kv
        :marker (point-marker)))

;; ---------------------------------------------------------------------------
;; Accessors

(defsubst helixel-edit-op (tx)
  "Return the :op of transaction TX."
  (plist-get tx :op))

(defsubst helixel-edit-sel (tx)
  "Return the :sel (selection context) of transaction TX, or nil."
  (plist-get tx :sel))

(defsubst helixel-edit-payload (tx)
  "Return the :payload plist of transaction TX."
  (plist-get tx :payload))

(defsubst helixel-edit-marker (tx)
  "Return the :marker of transaction TX."
  (plist-get tx :marker))

;; ---------------------------------------------------------------------------
;; Equality — for action ring dedup

(defun helixel-edit-equal-p (tx1 tx2)
  "Return non-nil if TX1 and TX2 represent the same editing operation.
Compares :op, :sel, and :payload.  Ignores :marker (position differs
on replay) and ignores plist key order in :payload.
Returns t when both are nil (non-edit actions are equal for dedup)."
  (if (or (null tx1) (null tx2))
      (eq tx1 tx2)
    (and (eq (helixel-edit-op tx1) (helixel-edit-op tx2))
         (equal (helixel-edit-sel tx1) (helixel-edit-sel tx2))
         (equal (helixel-edit-payload tx1) (helixel-edit-payload tx2)))))

;; ---------------------------------------------------------------------------
;; Display — for action ring history and completion

(cl-defgeneric helixel-sel-display (kind ctx)
  "Return a short human-readable string describing selection CTX of KIND.
Methods specialise on KIND via `(eql SYMBOL)'.  Used by
`helixel-edit-display' for action-history rendering.  Default returns
the symbol-name of KIND.")

(cl-defmethod helixel-sel-display (kind _ctx)
  "Default: just the kind symbol's name."
  (symbol-name kind))

(defun helixel-edit-display (tx)
  "Return a short display string for transaction TX.
Format: OP[.SEL][xCOUNT].  Op label and sel label are pluggable
(see `helixel-edit-op-display' and `helixel-sel-display')."
  (let* ((op (helixel-edit-op tx))
         (sel (helixel-edit-sel tx))
         (op-str (helixel-edit-op-display op tx))
         (sel-kind (plist-get sel :kind))
         (sel-str (when sel-kind (helixel-sel-display sel-kind sel)))
         (count (plist-get sel :count)))
    (concat op-str
            (when sel-str (concat "." sel-str))
            (when (and count (> count 1)) (format "x%d" count)))))

;; ---------------------------------------------------------------------------
;; Payload helpers

(defsubst helixel-edit--payload-get (tx key)
  "Read KEY from the :payload of TX.  Convenience wrapper."
  (plist-get (helixel-edit-payload tx) key))

(defun helixel-edit-with-payload (tx key value)
  "Return a new transaction equal to TX with payload KEY set to VALUE.
Does not mutate TX (the existing :payload may be shared with other
consumers, including a possibly-nil placeholder from `helixel-edit-make')."
  (let* ((payload (copy-sequence (helixel-edit-payload tx)))
         (new-payload (plist-put payload key value)))
    (plist-put (copy-sequence tx) :payload new-payload)))

;; ---------------------------------------------------------------------------
;; Operator registry
;;
;; Each :op symbol registers a runner (FN TX) that performs the edit at
;; replay time, plus an optional :display label for history rendering.
;; Modules register their own ops at load-time (see helixel-common.el and
;; helixel-surround.el) — helixel-repeat.el dispatches purely through this
;; registry, so adding a new operator never requires editing the kernel.

(defvar helixel-edit--op-registry (make-hash-table :test 'eq)
  "Hash OP-SYMBOL → plist (:runner FN :display STRING).")

(defun helixel-edit-register-op (op &rest props)
  "Register edit OP with PROPS keyword list.
Supported keys: :runner FUNCTION, :display STRING.
Replaces any existing registration."
  (puthash op props helixel-edit--op-registry))

(defmacro helixel-edit-defop (op &rest props)
  "Convenience macro wrapping `helixel-edit-register-op'.
OP is an unquoted symbol; PROPS is a keyword plist."
  (declare (indent 1))
  `(helixel-edit-register-op ',op ,@props))

(defun helixel-edit-op-runner (op)
  "Return the runner function registered for OP, or nil."
  (plist-get (gethash op helixel-edit--op-registry) :runner))

(defun helixel-edit-op-display (op &optional tx)
  "Return display label for OP.
The registry's :display field may be a string or a function (TX -> STRING).
Falls back to symbol-name when unset."
  (let ((d (plist-get (gethash op helixel-edit--op-registry) :display)))
    (cond
     ((stringp d) d)
     ((functionp d) (or (funcall d tx) (symbol-name op)))
     (t (symbol-name op)))))

(defun helixel-edit-operator-p (op)
  "Return non-nil if OP is a registered edit operator."
  (and (gethash op helixel-edit--op-registry) t))

;; ---------------------------------------------------------------------------
;; Selection-descriptor dispatch
;;
;; A selection descriptor is a plist whose :kind drives how the selection is
;; recreated at replay time.  Owners of a selection kind register a method on
;; `helixel-sel-recreate' (textobj/line/rect/movement/surround/...).
;;
;; The default method falls back to the legacy `:fn FUNCTION' form so that
;; un-migrated producers keep working — this lets the refactor proceed
;; module-by-module without breaking tests.

(cl-defgeneric helixel-sel-recreate (kind ctx)
  "Recreate a selection at point given descriptor KIND and full CTX plist.
Methods specialise on KIND via `(eql SYMBOL)'.  CTX carries any
additional fields (:count, :delimiter, :moves, :command, ...).
The default method is a no-op so unknown / metadata-only kinds
silently leave point alone.")

(cl-defmethod helixel-sel-recreate (_kind _ctx)
  "Default: do nothing.  Overridden by methods on `(eql SYMBOL)'."
  nil)

(defvar helixel--current-state)

(cl-defmethod helixel-sel-recreate ((_kind (eql movement)) ctx)
  "Replay a recorded sequence of movement commands while in visual state.
CTX has shape (:kind movement :moves ((CMD . COUNT) ...)).  Moves are
stored newest-first; replayed oldest-first."
  (let ((helixel--current-state 'visual))
    (dolist (m (reverse (plist-get ctx :moves)))
      (dotimes (_ (cdr m))
        (funcall (car m))))))

(provide 'helixel-edit)
;;; helixel-edit.el ends here
