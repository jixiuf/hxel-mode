;;; helixel-repeat.el --- Repeat last edit (vim .) for helixel -*- lexical-binding: t; -*-

;; Copyright (C) 2025  jixiuf

;; Author: jixiuf
;; Keywords: convenience
;; Package-Requires: ((emacs "29.1"))

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;;; Commentary:
;;
;; Implements vim-like "." repeat for helixel-mode.
;;
;; A single `post-command-hook' records each command's key sequence
;; along with metadata: whether the buffer was modified, the command
;; symbol, the modal state transition, and whether the region was
;; visibly active after the command.
;;
;; When `helixel-repeat-execute' is invoked, the recorded history is
;; scanned for the last editing session (operator + selection-building
;; + insert-mode typing + exit) using an algorithm based on the
;; repeat-fu meow preset.

;;; Code:

(require 'helixel-common)
(eval-when-compile (require 'cl-lib))

;; ---------------------------------------------------------------------------
;; Custom

(defgroup helixel-repeat nil
  "Repeat last edit for helixel."
  :group 'helixel)

(defcustom helixel-repeat-max-entries 256
  "Maximum number of command entries to keep in the repeat history."
  :type 'natnum)

;; ---------------------------------------------------------------------------
;; Ring Buffer

(defvar-local helixel--repeat-entries nil
  "Command history buffer, newest first.
Each element is (keys-vector . meta-vector).")

(defvar-local helixel--repeat-prev-tick nil
  "`buffer-chars-modified-tick' from the previous post-command-hook run.")
(defvar-local helixel--repeat-prev-state nil
  "`helixel--current-state' from the previous post-command-hook run.")
(defvar-local helixel--repeat-prev-active nil
  "Whether region was visible from the previous post-command-hook run.")

(defvar helixel--repeat-recording-p t
  "When nil, `helixel--repeat-post-hook' skips recording.
Bound to nil during `helixel-repeat-execute' to avoid recording the replay.")

;; -- meta-vector indices --
;; [change-p cmd-symbol state-pair active-p]
;;  0        1          2          3
;; change-p:     t if buffer-chars-modified-tick changed
;; cmd-symbol:   this-command
;; state-pair:   (prev . curr) if state changed, else curr
;; active-p:     region was active AND deactivate-mark was nil

(eval-and-compile
  (defconst helixel--repeat-meta-change 0)
  (defconst helixel--repeat-meta-cmd 1)
  (defconst helixel--repeat-meta-state 2)
  (defconst helixel--repeat-meta-active 3))

(defsubst helixel--repeat-meta-change-p (m) (aref m helixel--repeat-meta-change))
(defsubst helixel--repeat-meta-cmd (m) (aref m helixel--repeat-meta-cmd))
(defsubst helixel--repeat-meta-state (m) (aref m helixel--repeat-meta-state))
(defsubst helixel--repeat-meta-active-p (m) (aref m helixel--repeat-meta-active))

(defun helixel--repeat-state-post (meta)
  "Return the post-command state from META."
  (let ((s (helixel--repeat-meta-state meta)))
    (if (consp s) (cdr s) s)))

(defun helixel--repeat-state-pre (meta)
  "Return the pre-command state from META."
  (let ((s (helixel--repeat-meta-state meta)))
    (if (consp s) (car s) s)))

;; ---------------------------------------------------------------------------
;; Snapshots (called once per command in post-command-hook)

(defun helixel--repeat-snapshot-tick ()
  "Return non-nil if the buffer was modified since the last snapshot."
  (not (eq helixel--repeat-prev-tick (buffer-chars-modified-tick))))

(defun helixel--repeat-snapshot-active ()
  "Return non-nil if the region is visibly active."
  (and (region-active-p) (not deactivate-mark)))

(defun helixel--repeat-state-pair ()
  "Return a state representation for this command."
  (if (eq helixel--repeat-prev-state helixel--current-state)
      helixel--current-state
    (cons helixel--repeat-prev-state helixel--current-state)))

;; ---------------------------------------------------------------------------
;; Push / Hook

(defun helixel--repeat-push (keys meta)
  "Push (KEYS . META) onto the ring buffer, trimming old entries."
  (push (cons keys meta) helixel--repeat-entries)
  (let ((tail (nthcdr helixel-repeat-max-entries helixel--repeat-entries)))
    (when tail
      (setcdr tail nil))))

(defun helixel--repeat-post-hook ()
  "Record the command that just finished."
  (when (and helixel--repeat-recording-p
             (not (eq this-command 'helixel-repeat-execute)))
    (let ((changed (helixel--repeat-snapshot-tick))
          (active (helixel--repeat-snapshot-active))
          (state (helixel--repeat-state-pair)))
      (helixel--repeat-push
       (this-command-keys-vector)
       (vector changed this-command state active))
      (setq helixel--repeat-prev-tick (buffer-chars-modified-tick)
            helixel--repeat-prev-state helixel--current-state
            helixel--repeat-prev-active active))))

(defun helixel--repeat-reset-snapshot ()
  "Reset captured state to current values."
  (setq helixel--repeat-prev-tick (buffer-chars-modified-tick)
        helixel--repeat-prev-state helixel--current-state
        helixel--repeat-prev-active (helixel--repeat-snapshot-active)))

;; ---------------------------------------------------------------------------
;; Extraction

(defvar helixel--repeat-skip-change
  '(undo undo-redo undo-only)
  "Commands whose buffer change is ignored when locating the edit to repeat.")

(defvar helixel--repeat-skip-selection
  '(helixel-search-forward
    helixel-search-backward
    helixel-search-at-point-next
    helixel-search-at-point-prev)
  "Search commands that set the region but should not anchor a selection chain.
The search result depends on the cursor position at the time of the search,
so replaying from a different position would yield unpredictable results.")

(defun helixel--repeat-extract ()
  "Extract repeat macros from recorded history.
Returns a list of three key vectors:
  [full-macro no-selection-macro insert-only-macro]
or nil if nothing is found."
  (cl-block helixel--repeat-extract
    (let* ((entries helixel--repeat-entries)
           (n (length entries))
           (n-1 (1- n))
           (skip-change helixel--repeat-skip-change)
           (skip-selection helixel--repeat-skip-selection)
           (change-idx -1)
           idx-min idx-max idx-min-active
           idx-min-insert idx-max-insert
           scan-active)

    (when (zerop n)
      (cl-return-from helixel--repeat-extract nil))

    ;; 1. Find the most recent buffer-changing command (skip undo/redo).
    (let ((i 0))
      (while (< i n)
        (when (helixel--repeat-meta-change-p (cdr (nth i entries)))
          (unless (memq (helixel--repeat-meta-cmd (cdr (nth i entries)))
                        skip-change)
            (setq change-idx i)
            (setq i n)))
        (cl-incf i)))

    (when (= change-idx -1)
      (cl-return-from helixel--repeat-extract nil))

    (setq idx-min change-idx)
    (setq idx-max change-idx)
    (setq scan-active t)

    ;; 2. If the change entered insert state, expand to include all
    ;;    consecutive commands whose post-state is `insert'.
    (when (eq 'insert (helixel--repeat-state-post (cdr (nth change-idx entries))))
      (while (and (< idx-max n-1)
                  (eq 'insert
                      (helixel--repeat-state-post (cdr (nth (1+ idx-max) entries)))))
        (cl-incf idx-max))
      (while (and (> idx-min 0)
                  (eq 'insert
                      (helixel--repeat-state-post (cdr (nth (1- idx-min) entries)))))
        (cl-decf idx-min))

      (setq idx-min-insert idx-min)
      (setq idx-max-insert idx-max)

      ;; Exclude the "enter insert" command from the insert-only range.
      (unless (eq 'insert (helixel--repeat-state-pre (cdr (nth idx-max-insert entries))))
        (cl-decf idx-max-insert))

      (unless (helixel--repeat-meta-change-p (cdr (nth idx-max entries)))
        ;; Entering insert mode did not itself change the buffer
        ;; (e.g. `i' without a preceding `c').  Don't include any
        ;; prior selection-building commands.
        (setq scan-active nil)))

    ;; 3. Include the exit-from-insert command (if any) before the range.
    (when (and (> idx-min 0)
               (eq (helixel--repeat-meta-cmd (cdr (nth (1- idx-min) entries)))
                   'helixel-insert-exit))
      (cl-decf idx-min))

    ;; 4. Save the range that excludes selection-building commands.
    (setq idx-min-active idx-max)

    ;; 5. Scan backward (toward older entries) for selection-building
    ;;    commands.  The region must have been visibly active after each
    ;;    such command, and we stop at another change or a skip-selection
    ;;    command.
    (when scan-active
      (let ((orig idx-max)
            (ok t))
        (while (and (< idx-max n-1) ok
                    (helixel--repeat-meta-active-p (cdr (nth (1+ idx-max) entries))))
          (cl-incf idx-max)
          (when (or (helixel--repeat-meta-change-p (cdr (nth idx-max entries)))
                    (memq (helixel--repeat-meta-cmd (cdr (nth idx-max entries)))
                          skip-selection))
            (setq idx-max orig)
            (setq ok nil)))))

    ;; 6. Build the three candidate macros (oldest-first key order).
    (let ((result [])
          (result-no-active [])
          (result-insert-only []))
      (cl-loop for i from idx-max downto idx-min
               do (setq result (vconcat result (car (nth i entries)))))
      (if (= idx-max idx-min-active)
          (setq result-no-active result)
        (cl-loop for i from idx-min-active downto idx-min
                 do (setq result-no-active (vconcat result-no-active (car (nth i entries))))))
      (when idx-min-insert
        (cl-loop for i from idx-max-insert downto idx-min-insert
                 do (setq result-insert-only (vconcat result-insert-only (car (nth i entries))))))
      (list result result-no-active result-insert-only)))))

;; ---------------------------------------------------------------------------
;; Execute

;;;###autoload
(defun helixel-repeat-execute (&optional arg)
  "Repeat the last editing action, like vim's `.`.
With prefix ARG, repeat that many times."
  (interactive "p")
  (unless helixel--repeat-entries
    (user-error "Nothing to repeat"))
  (let ((macros (helixel--repeat-extract)))
    (unless macros
      (user-error "Nothing to repeat"))
    (let* ((macro
            (nth (cond
                  ((eq helixel--current-state 'insert) 2)
                  ((region-active-p) 1)
                  (t 0))
                 macros))
           (helixel--repeat-recording-p nil))
      (unless (and macro (> (length macro) 0))
        (user-error "Nothing to repeat"))
      (condition-case nil
          (with-undo-amalgamate
            (execute-kbd-macro macro arg))
        (error
         (message "helixel-repeat: replay failed"))))))

;; ---------------------------------------------------------------------------
;; Enable / Disable

;;;###autoload
(defun helixel-repeat-enable ()
  "Start recording commands for repeat."
  (interactive)
  (helixel--repeat-reset-snapshot)
  (add-hook 'post-command-hook #'helixel--repeat-post-hook nil t))

;;;###autoload
(defun helixel-repeat-disable ()
  "Stop recording commands for repeat."
  (interactive)
  (remove-hook 'post-command-hook #'helixel--repeat-post-hook t)
  (setq helixel--repeat-entries nil))

(provide 'helixel-repeat)
;;; helixel-repeat.el ends here
