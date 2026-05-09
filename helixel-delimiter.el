;;; helixel-delimiter.el --- Delimiter protocol  -*- lexical-binding: t; -*-

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
;; Unified delimiter descriptor for text objects and surround operations.
;;
;; A delimiter plist describes a delimited region (pair of brackets, a
;; quoted string, XML tags, mode-specific blocks, or regex-defined
;; blocks).  It carries enough information for both text-object selection
;; and surround add/delete/replace.
;;
;; Schema:
;;   (:type    pair|quote|tag|block|regex
;;    :open    char|string   ;; opening delimiter
;;    :close   char|string   ;; closing delimiter
;;    :finder  function      ;; (fn dir) → 0|N, moves point, sets match-data
;;    :nl-p    boolean)      ;; t → add/delete handles adjacent newlines
;;
;; This module has ZERO dependencies on other helixel modules and
;; NO side effects.  It is the single source of truth for delimiter
;; data, consumed by helixel-textobj and helixel-surround.

;;; Code:

(require 'cl-lib)

;; ---------------------------------------------------------------------------
;; Accessors
;; ---------------------------------------------------------------------------

(defsubst helixel-delimiter-type (d)
  "Return the :type of delimiter D."
  (plist-get d :type))

(defsubst helixel-delimiter-open (d)
  "Return the :open delimiter character or string of D."
  (plist-get d :open))

(defsubst helixel-delimiter-close (d)
  "Return the :close delimiter character or string of D."
  (plist-get d :close))

(defsubst helixel-delimiter-finder (d)
  "Return the :finder function of delimiter D."
  (plist-get d :finder))

(defsubst helixel-delimiter-nl-p (d)
  "Return non-nil if delimiter D uses newline handling."
  (plist-get d :nl-p))

;; ---------------------------------------------------------------------------
;; Shared helpers
;; ---------------------------------------------------------------------------

(defvar-local helixel--block-chosen-spec nil)

(defun helixel--find-equal-char (char dir)
  "Like `helixel-up-paren' but for equal open/close CHAR (quotes).
DIR +1 forward, -1 backward.  Returns 0 on success, 1 on failure."
  (if (> dir 0)
      (if (search-forward (string char) nil t) 0 1)
    (if (search-backward (string char) nil t) 0 1)))

(defun helixel-delimiter-find (d dir)
  "Find delimiter D in DIR (+1 forward, -1 backward).
Returns 0 on success, non-zero on failure.  Moves point and sets `match-data'."
  (funcall (helixel-delimiter-finder d) dir))

(defun helixel-delimiter-bounds (d)
  "Return ((OB . OE) . (CB . CE)) for the innermost delimiter D at point.
OB, OE: open delimiter beg/end.  CB, CE: close delimiter beg/end."
  (let* ((type (helixel-delimiter-type d))
         (close (helixel-delimiter-close d)))
    (when (eobp) (skip-chars-backward " \t\n\r"))
    (when (and (characterp close) (> (point) 1) (= (char-before) close))
      (backward-char))
    (unwind-protect
        (progn
          (unless (zerop (helixel-delimiter-find d -1))
            (user-error "No enclosing delimiter"))
          (let ((ob (match-beginning 0)) (oe (match-end 0)))
            (goto-char oe)
            (unless (zerop (helixel-delimiter-find d 1))
              (user-error "No enclosing delimiter"))
            (let ((cb (match-beginning 0)) (ce (match-end 0)))
              (cons (cons ob oe) (cons cb ce)))))
      (setq helixel--block-chosen-spec nil))))

(defun helixel--strip-adjacent-newlines (open-end close-beg)
  "Adjust OPEN-END and CLOSE-BEG to exclude adjacent newlines.
Returns (OPEN-END . CLOSE-BEG)."
  (cons (if (eq (char-after open-end) ?\n) (1+ open-end) open-end)
        (if (eq (char-before close-beg) ?\n) (1- close-beg) close-beg)))

;; ---------------------------------------------------------------------------
;; Builder — construct delimiter plists for each type
;; ---------------------------------------------------------------------------

(declare-function helixel-up-paren "helixel-textobj")
(declare-function helixel-up-xml-tag "helixel-textobj")
(declare-function helixel-up-block-at-point "helixel-textobj")
(declare-function helixel-up-regex-block "helixel-textobj")

(defun helixel--make-pair-delimiter (open close)
  "Create a pair delimiter for OPEN and CLOSE characters."
  (let ((equal-p (= open close)))
    (list :type (if equal-p 'quote 'pair)
          :open open :close close
          :finder (if equal-p
                      `(lambda (dir) (helixel--find-equal-char ,open dir))
                    `(lambda (dir) (helixel-up-paren ,open ,close dir)))
          :nl-p nil)))

(defun helixel--make-tag-delimiter ()
  "Create a tag delimiter."
  (list :type 'tag
        :finder (lambda (dir) (helixel-up-xml-tag dir))
        :nl-p t))

(defun helixel--make-block-delimiter (&optional open close)
  "Create a block delimiter for OPEN and CLOSE strings.
If OPEN/CLOSE are nil, the finder resolves the spec at runtime."
  (list :type 'block
        :open open :close close
        :finder (lambda (dir) (helixel-up-block-at-point dir))
        :nl-p t))

(defun helixel--make-regex-delimiter (begin-re end-re &optional name-group)
  "Create a regex delimiter for BEGIN-RE and END-RE.
Optional NAME-GROUP specifies the match group index for the name."
  (list :type 'regex
        :open begin-re :close end-re
        :begin-re begin-re :end-re end-re
        :name-group name-group
        :finder `(lambda (dir)
                   (helixel-up-regex-block ,begin-re ,end-re dir ,name-group))
        :nl-p t))

(provide 'helixel-delimiter)
;;; helixel-delimiter.el ends here
