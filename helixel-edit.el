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

(defun helixel-edit-display (tx)
  "Return a short display string for transaction TX.
Format: operator symbol, optionally suffixed with selection kind.
e.g. \"d.textobj\", \"c.line\", \"p\", \"R\", \"<\"."
  (let* ((op (helixel-edit-op tx))
         (sel (helixel-edit-sel tx))
         (op-str (cl-case op
                   (kill "d") (change "c") (copy "y")
                   (replace "r") (paste-after "p") (paste-before "P")
                   (indent-left "<") (indent-right ">")
                   (replace-char "R") (insert-text "i")
                   (surround-add "ms") (surround-add-tag "mt")
                   (surround-delete "md") (surround-replace "mr")
                   (t (symbol-name op))))
         (sel-kind (plist-get sel :kind)))
    (if sel-kind
        (format "%s.%s" op-str sel-kind)
      op-str)))

;; ---------------------------------------------------------------------------
;; Payload helpers

(defsubst helixel-edit--payload-get (tx key)
  "Read KEY from the :payload of TX.  Convenience wrapper."
  (plist-get (helixel-edit-payload tx) key))

;; ---------------------------------------------------------------------------
;; Operator classification (for repeat / history filtering)

(defvar helixel-edit-operator-names
  '(kill change copy replace replace-char
    paste-after paste-before indent-left indent-right insert-text
    surround-add surround-add-tag surround-delete surround-replace)
  "All known edit operators.")

(defun helixel-edit-operator-p (op)
  "Return non-nil if OP is a known edit operator."
  (memq op helixel-edit-operator-names))

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
additional fields (:count, :delimiter, :moves, ...).")

(cl-defmethod helixel-sel-recreate (_kind ctx)
  "Default: legacy `:fn' descriptor.  Calls (FN COUNT) when present."
  (when-let* ((fn (plist-get ctx :fn)))
    (funcall fn (or (plist-get ctx :count) 1))))

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
