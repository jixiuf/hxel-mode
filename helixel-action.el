;;; helixel-action.el --- Action tracking & ring  -*- lexical-binding: t; -*-

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
;; Action data model for helixel-mode.
;;
;; Every editing operation (movement, search, find-char, textobj) records
;; an *action* — a plist with keys like :category, :subcat, :dir, :marker.
;;
;; The live action (`helixel--action') tracks the current operation.
;; Completed actions are pushed to `helixel--action-ring' for:
;;   - session jumping (`;')
;;   - repeat detection (`n' / `N')
;;   - history browsing (`C-u n' / `C-u N')
;;
;; Note: direction for n/N repeat is managed by `helixel--repeat-dir'
;; in helixel-search.el — NOT by `helixel--action :dir'.  The :dir key
;; on actions is set at creation and never mutated after commit; it
;; serves as a historical record for display purposes only.
;;
;; ── KEY INVARIANT ──
;; Ring entries are INDEPENDENT from the live action.  Every push goes
;; through `helixel-action--ring-push' which deep-copies and deduplicates.
;; You may freely `plist-put' on `helixel--action' without affecting any
;; ring entry.
;; ── END ──

;;; Code:

(require 'cl-lib)

;; ── Custom group ──

(defgroup helixel nil
  "Custom group for Helixel."
  :group 'helixel)

(defcustom helixel-action-ring-max 50
  "Maximum number of actions stored in `helixel--action-ring'."
  :type 'integer
  :group 'helixel)

(defcustom helixel-action-cycle-categories
  '(movement textobj search find-char)
  "Action :category symbols that `;' (`helixel-action-cycle') navigates.
Categories not listed here are invisible during cycling (e.g. `state'
for cancel sentinels).  They remain in the ring for dedup purposes."
  :type '(repeat (choice
                  (const :tag "Movement" movement)
                  (const :tag "Text object" textobj)
                  (const :tag "Search" search)
                  (const :tag "Find char" find-char)))
  :group 'helixel)

;; ── Buffer-local state ──

(defvar-local helixel--action nil
  "Current active action plist.

Data structure — actions are plists.  Universal keys plus one
category-specific sub-plist keyed by :category symbol:

  Universal (all actions):
    :category  symbol   movement | search | find-char | textobj | state
    :subcat    symbol   char|line|word|WORD|goto|next|till|pair|quote|etc.
    :marker    marker   Session start position (for `;' jump).
    :display   boolean  t = committed to ring (history listing).

  Category sub-plists (optional, key matches :category):
    :search    plist    (:pattern \"regexp\" :dir forward|backward)
    :find-char plist    (:type next|till :char CHAR :dir forward|backward)
    :movement  plist    (:dir forward|backward)

External code must use the accessor functions below instead of
direct `plist-get'/`plist-put' on this variable:
  (helixel--live-get :category)                  ;; flat read
  (helixel--live-put :display t)                 ;; flat write
  (helixel--live-cat-get :type)                  ;; cat sub-plist read (live)
  (helixel--live-search-set pattern dir)         ;; set :search on live
  (helixel--live-find-char-set type char dir)    ;; set :find-char on live
  (helixel--live-cat-set-dir dir)                ;; set :dir on live
  (helixel--action-get ring-entry :subcat)       ;; flat read from ring
  (helixel--action-cat-get ring-entry :dir)      ;; cat read from ring

Internal helixel-action.el code may use plist-get/put directly.")

(defvar-local helixel--action-ring nil
  "Ring of actions, most recent first.  Each entry is a plist.
Shared by session jump (`;'), repeat (`n'/`N'), and history (`C-u n').
Capped at `helixel-action-ring-max'.")

(defvar-local helixel--action-pos nil
  "Ring position for `;' cycling: nil=live, 0=newest, 1=next, ...")

;; ── Accessor API ──
;;
;; External code (search, common) must use these instead of raw
;; plist-get/plist-put on helixel--action.

(defsubst helixel--live-get (key)
  "Read KEY from the live action `helixel--action'."
  (plist-get helixel--action key))

(defun helixel--live-put (key value)
  "Set KEY to VALUE on the live action `helixel--action'.
Safe: the live action is never aliased to ring entries."
  (plist-put helixel--action key value))

(defsubst helixel--action-get (action key)
  "Read KEY from ACTION plist (a ring entry or repeat-data plist)."
  (plist-get action key))

(defun helixel--live-cat-get (key)
  "Read KEY from the live action's category sub-plist.
The sub-plist is keyed by the keyword form of :category'."
  (let ((cat (plist-get helixel--action :category)))
    (when cat
      (plist-get (plist-get helixel--action
                            (intern (format ":%s" cat)))
                 key))))

;; ── Atomic data setters ──
;;
;; Each setter requires ALL fields for its category — the function
;; signature IS the contract.  No generic key-value writer exists.

(defun helixel--live-search-set (pattern dir)
  "Set :search sub-plist on the live action.  PATTERN and DIR required."
  (plist-put helixel--action :search `(:pattern ,pattern :dir ,dir)))

(defun helixel--live-find-char-set (type char dir)
  "Set :find-char sub-plist.  TYPE, CHAR, and DIR all required."
  (plist-put helixel--action :find-char `(:type ,type :char ,char :dir ,dir)))

(defun helixel--live-cat-set-dir (dir)
  "Set direction to DIR in the live action's category sub-plist.
:dir is the only field shared across search, find-char, and movement."
  (let ((cat (plist-get helixel--action :category)))
    (when cat
      (let* ((kwd (intern (format ":%s" cat)))
             (sub (plist-get helixel--action kwd)))
        (plist-put helixel--action kwd (plist-put sub :dir dir))))))

(defsubst helixel--action-cat-get (action key)
  "Read KEY from ACTION's category sub-plist."
  (let ((cat (plist-get action :category)))
    (when cat
      (plist-get (plist-get action
                            (intern (format ":%s" cat)))
                 key))))

;; ── Content comparison ──

(defun helixel-action--same-content-p (a1 a2)
  "Return non-nil if actions A1 and A2 have identical key content.
Compares universal keys and category sub-plists."
  (and a1 a2
       (eq (plist-get a1 :category) (plist-get a2 :category))
       (equal (plist-get a1 :subcat) (plist-get a2 :subcat))
       (equal (plist-get a1 :search) (plist-get a2 :search))
       (equal (plist-get a1 :find-char) (plist-get a2 :find-char))
       (equal (plist-get a1 :movement) (plist-get a2 :movement))))

;; ── Ring push (UNIFIED) ──
;;
;; All ring mutations go through this function.  It deep-copies,
;; deduplicates, and caps.  Callers never push or copy-tree directly.

(defun helixel-action--ring-cap ()
  "Truncate `helixel--action-ring' to `helixel-action-ring-max' entries.
Releases markers of evicted entries to prevent leaks."
  (when (> (length helixel--action-ring) helixel-action-ring-max)
    (let ((old (nthcdr helixel-action-ring-max helixel--action-ring)))
      (dolist (a old)
        (let ((m (plist-get a :marker)))
          (when (markerp m) (set-marker m nil)))))
    (setcdr (nthcdr (1- helixel-action-ring-max) helixel--action-ring) nil)))

(defun helixel-action--ring-push (action)
  "Push ACTION to `helixel--action-ring' with deep-copy and dedup.
Skips the push if the ring front already has identical key content
\(same universal keys and same category sub-plists).
Returns non-nil if the push actually happened."
  (when action
    (let ((entry (copy-tree action))
          (dup (car helixel--action-ring)))
      ;; copy-tree does NOT deep-copy markers — ensure ring entries
      ;; get independent marker objects so the source can be freed safely.
      (let ((m (plist-get entry :marker)))
        (when (markerp m)
          (plist-put entry :marker
                     (copy-marker m (marker-insertion-type m)))))
      (unless (and dup (helixel-action--same-content-p dup entry))
        (push entry helixel--action-ring)
        (helixel-action--ring-cap)
        t))))

;; ── Ring commit ──

(defun helixel-action-commit ()
  "Commit `helixel--action' to `helixel--action-ring'.
Sets :display to t so the entry appears in history completion.
Uses `helixel-action--ring-push' which deep-copies and deduplicates."
  (when helixel--action
    (plist-put helixel--action :display t)
    (helixel-action--ring-push helixel--action)))

;; ── Validation ──

(defvar helixel--action-required-keys
  '((search . :search)
    (find-char . :find-char))
  "Alist mapping action :category to its required sub-plist key.
An action is invalid (not worth keeping) if its required sub-plist is nil.
Categories not listed here are always considered valid.")

(defun helixel--action-valid-p (action)
  "Return non-nil if ACTION has the required keys for its category.
Uses `helixel--action-required-keys' to determine what each category needs."
  (let* ((cat (plist-get action :category))
         (req (cdr (assq cat helixel--action-required-keys))))
    (or (null req)
        (plist-get action req))))

;; ── Display ──

(defun helixel-action-display (action)
  "Format ACTION plist for display in completion.
Returns \"/pat/\" or \"?pat?\" for search, \"f→X\" etc. for find-char,
and \"cat.subcat\" for other actions."
  (let ((cat (plist-get action :category)))
    (cond
     ((eq cat 'search)
      (let* ((sub (plist-get action :search))
             (dir (plist-get sub :dir))
             (pat (plist-get sub :pattern))
             (c (if (eq dir 'backward) ?? ?/)))
        (format "%c%s%c" c pat c)))
     ((eq cat 'find-char)
      (let* ((sub (plist-get action :find-char))
             (type (plist-get sub :type))
             (char (plist-get sub :char))
             (dir (plist-get sub :dir)))
        (format "%c→%c"
                (if (eq type 'next)
                    (if (eq dir 'forward) ?f ?F)
                  (if (eq dir 'forward) ?t ?T))
                char)))
     ((and (eq cat 'state) (eq (plist-get action :subcat) 'cancel))
      "C-g")
     (t (format "%s.%s" cat (plist-get action :subcat))))))

;; ── Start / continue an action ──

(defun helixel-action-start (category subcat)
  "Start or continue an action of CATEGORY and SUBCAT.

Pushes the current `helixel--action' to ring if the type
\(category subcat) changed.  Returns the new action plist.

When continuing the same type, preserves the original :marker.
Otherwise creates a fresh marker at point.
Callers that need a specific marker (e.g. `find-repeat',
`from-history') should call `helixel--live-put :marker' afterward.

RING SAFETY: Old actions are deep-copied before pushing.
The new live action is a fresh plist, never aliased to any
ring entry."
  (let* ((prev-type (when helixel--action
                      (cons (plist-get helixel--action :category)
                            (plist-get helixel--action :subcat))))
         (this-type (cons category subcat))
         (continuing (equal prev-type this-type))
         (marker (or (and continuing (plist-get helixel--action :marker))
                     (point-marker)))
         (action `(:category ,category :subcat ,subcat :marker ,marker)))
    ;; Push old action to ring when type changes, unless meaningless.
    (when (and helixel--action (not (equal prev-type this-type))
               (helixel--action-valid-p helixel--action))
      (helixel-action--ring-push helixel--action))
    ;; Replace live action
    (setq helixel--action action
          helixel--action-pos nil)
    action))

;; ── Marker jump ──

(defun helixel--jump-to-marker (marker)
  "Set mark at MARKER (session start), keeping point unchanged.
MARKER must be a live marker (has a buffer).  Dead markers (e.g. from
killed buffers) are silently ignored."
  (when (and (markerp marker) (marker-buffer marker))
    (push-mark marker t t)))

;; ─── ; cycle helpers ───

(defun helixel-action--cycle-visible-p (action)
  "Return non-nil if ACTION should be visible during `;' cycling."
  (memq (plist-get action :category) helixel-action-cycle-categories))

(defun helixel-action--cycle-visible-index (pos ring)
  "Return index of the first visible entry starting at POS in RING, or nil."
  (cl-loop for i from pos below (length ring)
           when (helixel-action--cycle-visible-p (nth i ring))
           return i))

(defun helixel-action--cycle-visible-count (ring)
  "Count visible entries in RING for `;' cycling."
  (cl-loop for a in ring
           when (helixel-action--cycle-visible-p a)
           count 1))

(defun helixel-action--cycle-display (action pos ring)
  "Format cycling message: [POS/MAX] with display string for ACTION.
POS is a raw ring index in RING; displayed position is 1-based
within visible entries."
  (let* ((total (helixel-action--cycle-visible-count ring))
         (display-pos (1+ (cl-loop for i from 0 below pos
                                   count (helixel-action--cycle-visible-p
                                          (nth i ring))))))
    (format "[%d/%d] %s" display-pos total
            (helixel-action-display action))))

(defun helixel-action--cycle-find (pos direction ring)
  "Find index of next visible entry in RING from POS in DIRECTION.
DIRECTION: +1 = older (toward end), -1 = newer (toward 0).
Returns the index or nil."
  (let ((len (length ring)))
    (cl-loop for i from (+ pos direction) by direction
             while (if (> direction 0) (< i len) (>= i 0))
             when (helixel-action--cycle-visible-p (nth i ring))
             return i)))

(defun helixel-action--cycle-show (pos ring)
  "Show the action at RING index POS as current cycling target."
  (let ((action (nth pos ring)))
    (setq helixel--action-pos pos)
    (helixel--jump-to-marker (plist-get action :marker))
    (message "%s" (helixel-action--cycle-display action pos ring))))

(defun helixel-action--cycle-commit ()
  "Commit live action to ring if valid, discard otherwise.
Frees marker for invalid actions.  Returns t if pushed."
  (when helixel--action
    (prog1
        (if (helixel--action-valid-p helixel--action)
            (progn (helixel-action--ring-push helixel--action) t)
          (let ((m (plist-get helixel--action :marker)))
            (when (markerp m) (set-marker m nil)))
          nil)
      (setq helixel--action nil))))

;; ── Session cycling (`;') ──

(defun helixel-action-cycle (&optional arg)
  "Cycle through visible entries in `helixel--action-ring'.
Point stays unchanged — mark moves to show where each session started.
Filters via `helixel-action-cycle-categories' (e.g. state/cancel hidden).
Without prefix ARG: go to older action.
With prefix ARG (`C-u'): go to newer action or restore live session.
Bound to `;' in normal mode."
  (interactive "P")
  (if arg
      ;; C-u ; → go forward (newer)
      (cond
       ((and helixel--action-pos (> helixel--action-pos 0))
        (let ((pos (helixel-action--cycle-find
                    helixel--action-pos -1 helixel--action-ring)))
          (if pos
              (helixel-action--cycle-show pos helixel--action-ring)
            (message "At newest"))))
       ((eq helixel--action-pos 0)
        (if helixel--action
            (progn
              (setq helixel--action-pos nil)
              (helixel--jump-to-marker (plist-get helixel--action :marker))
              (message "[live] %s" (helixel-action-display helixel--action)))
          (message "At newest")))
       (t (message "At newest")))
    ;; ; → go back (older)
    (cond
     (helixel--action-pos
      (let ((pos (helixel-action--cycle-find
                  helixel--action-pos 1 helixel--action-ring)))
        (if pos
            (helixel-action--cycle-show pos helixel--action-ring)
          (message "No more"))))
     (helixel--action
      (helixel-action--cycle-commit)
      (let ((pos (helixel-action--cycle-visible-index
                  0 helixel--action-ring)))
        (if pos
            (helixel-action--cycle-show pos helixel--action-ring)
          (message "No saved actions"))))
     (helixel--action-ring
      (let ((pos (helixel-action--cycle-visible-index
                  0 helixel--action-ring)))
        (if pos
            (helixel-action--cycle-show pos helixel--action-ring)
          (message "No saved actions"))))
     (t (message "No saved actions")))))

;; ── Cancel action (C-g) ──

(defun helixel--cancel-action ()
  "Called on \\[keyboard-quit] to break session continuity.
Pushes the current meaningful action to ring (deep-copied), then resets it.
Also pushes a `state/cancel' sentinel to enable natural dedup: the next
same-type command won't be dedup'd against the previous session."
  (when helixel--action
    (when (helixel--action-valid-p helixel--action)
      (helixel-action--ring-push helixel--action))
    (let ((m (plist-get helixel--action :marker)))
      (when (markerp m) (set-marker m nil)))
    (setq helixel--action nil))
  ;; Push cancel sentinel — acts as session boundary for dedup.
  ;; Not visible in `;' cycling (state ∉ cycle-categories).
  (helixel-action--ring-push
   `(:category state :subcat cancel :marker ,(point-marker))))

(provide 'helixel-action)
;;; helixel-action.el ends here
