;;; helixel-register.el --- Named registers  -*- lexical-binding: t; -*-

;; Copyright (C) 2026  jixiuf

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

;; Named register support for helixel-mode, bridging Emacs `register-alist'.
;;
;; Usage:
;;   \"ay  — copy to register a
;;   \"ap  — paste from register a
;;   \"ad  — delete to register a
;;   \"ac  — change to register a
;;   \"ar  — replace with register a
;;   \"\"y  — copy to default register (kill-ring, same as y)
;;
;; Register names: a-z (Emacs `register-alist'), \" (kill-ring),
;; + (system clipboard), * (primary selection).
;;
;; This module is required by `helixel-state' so the wrappers are
;; available everywhere in the helixel dependency tree.

;;; Code:

(defvar helixel--current-register nil
  "Character identifying the register for the next operator.
Set by `helixel-select-register' (bound to `\"' in normal mode).
Consumed and cleared by each operator that uses it.
When nil or `?\"', the default kill-ring is used.")

;; ── Register selection (bound to `\"' in normal mode) ──

(defun helixel-select-register ()
  "Read a register name for the next operator.
Valid register names: a-z (named), \" (unnamed/`kill-ring'),
+ (system clipboard), * (primary selection).
Press \\[keyboard-quit] to cancel."
  (interactive)
  (let ((char (read-char "Register: ")))
    (if (= char ?\e)
        (progn
          (setq helixel--current-register nil)
          (message "Register cancelled"))
      (setq helixel--current-register char)
      ;; Show the register name in echo area so user knows
      ;; it's pending (e.g. \"a).
      (message "\"%c" char))))

;; ── Register I/O ──

(defun helixel-register-get (char)
  "Return text contents of register CHAR, or nil if empty.
CHAR: a-z (Emacs `register-alist'), \" (kill-ring top),
+ (clipboard), * (primary selection)."
  (cond
   ((and (>= char ?a) (<= char ?z))
    (get-register char))
   ((= char ?\")
    (and kill-ring (current-kill 0 t)))
   ((= char ?+)
    (and (display-graphic-p)
         (gui-get-selection 'CLIPBOARD)))
   ((= char ?*)
    (and (display-graphic-p)
         (gui-get-selection 'PRIMARY)))
   (t (get-register char))))

(defun helixel-register-set (char text)
  "Store TEXT in register CHAR.
CHAR: a-z (Emacs `register-alist'), \" (push to `kill-ring'),
+ (clipboard), * (primary selection).
TEXT is a string preserving any yank-handler properties."
  (cond
   ((and (>= char ?a) (<= char ?z))
    (set-register char text))
   ((= char ?\")
    (kill-new text))
   ((= char ?+)
    (gui-set-selection 'CLIPBOARD text))
   ((= char ?*)
    (gui-set-selection 'PRIMARY text))
   (t (set-register char text))))

;; ── Register-aware kill-ring wrappers ──
;;
;; These replace direct `kill-new' / `current-kill' / `yank' calls
;; throughout the codebase.  When `helixel--current-register' is a
;; non-default register (not nil and not `?\"'), they redirect
;; to `register-alist'.  When nil or `?\"', they use the real
;; kill-ring.

(defun helixel--register-active-p ()
  "Return non-nil when a non-default named register is selected."
  (and helixel--current-register
       (not (eq helixel--current-register ?\"))))

(defun helixel--register-consume ()
  "Return and clear `helixel--current-register'."
  (prog1 helixel--current-register
    (setq helixel--current-register nil)))


(defun helixel-register-rotate-delete (text)
  "Rotate delete registers 1-9 and store TEXT in register 1.
Old register 8 shifts to 9, 7 to 8, ..., 1 to 2."
  (dotimes (i 8)
    (let ((src (+ ?1 (- 7 i))))
      (set-register (+ src 1) (get-register src))))
  (set-register ?1 text))

(defun helixel--kill-new (text &optional kind)
  "Like `kill-new', but also populates numbered registers.
TEXT is a string with optional yank-handler text properties.
KIND is :copy for yank operations (sets register 0), otherwise
a delete (rotates registers 1-9, sets register - for small deletes).
When a named register is active, TEXT is also stored there.
Does NOT clear the register -- callers should call
`helixel--register-consume' separately when done."
  ;; Always push to kill-ring (unnamed register).
  (kill-new text)
  ;; Numbered / special registers.
  (if (eq kind :copy)
      ;; Register 0 -- last yank (copy).
      (set-register ?0 text)
    ;; Rotate delete registers 1-9, new text goes to 1.
    (helixel-register-rotate-delete text)
    ;; Register - (small delete, no newline).
    (when (and text (not (string-match-p "\n" text)))
      (set-register ?- text)))
  ;; Named register selected by user (e.g. "a).
  (when (helixel--register-active-p)
    (helixel-register-set helixel--current-register text)))

(defun helixel--current-kill (n &optional no-move)
  "Like `current-kill', but reads from named register when active.
N is the `kill-ring' index (unused when reading from register).
NO-MOVE is passed to `current-kill' as DO-NOT-MOVE when using `kill-ring'.
Returns the text or nil.  Does NOT alter the `kill-ring' yanking-point
when reading from a register."
  (if (helixel--register-active-p)
      (or (helixel-register-get helixel--current-register)
          (current-kill 0 t))
    (current-kill n no-move)))

(defun helixel--yank (&optional arg)
  "Like `yank', but reads from named register when active.
ARG is passed through to `yank' when using the `kill-ring'."
  (if (helixel--register-active-p)
      (let ((text (helixel-register-get helixel--current-register)))
        (if text
            (insert-for-yank text)
          (message "Register \"%c is empty" helixel--current-register)))
    (yank arg)))

(provide 'helixel-register)
;;; helixel-register.el ends here
