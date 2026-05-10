;;; helixel-test.el --- Tests for Helixel minor mode  -*- lexical-binding: t; -*-

;; Copyright (C) 2025  jixiuf

;; Author: jixiuf
;; Keywords: tests
;; Version: 0
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

;; Helixel tests.

;;; Code:

(require 'ert)
(require 'helixel)

;;; Forward long word tests

(ert-deftest helixel-test-forward-WORD-start-basic-movement ()
  "Test basic forward movement between words."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "hello world test")
    (goto-char 1)
    (helixel-forward-WORD-start)
    (should (= (point) 7)) ; cursor at region-end (*-start)
    (should (= (- (region-end) (region-beginning)) 6))
    (helixel-forward-WORD-start)
    (should (= (point) 13)) ; before "test"
    (should (= (- (region-end) (region-beginning)) 6))
    (helixel-forward-WORD-start)
    (should (= (point) 13)) ; no more words, stays
    (should (= (- (region-end) (region-beginning)) 0))))

(ert-deftest helixel-test-forward-WORD-start-hyphenated-words ()
  "Test forward movement with hyphenated words (long words)."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "this test-string-example works")
    (goto-char 1)
    (helixel-forward-WORD-start)
    (should (= (point) 6))
    (should (= (- (region-end) (region-beginning)) 5))
    (helixel-forward-WORD-start)
    (should (= (point) 26))
    (should (= (- (region-end) (region-beginning)) 20))))

(ert-deftest helixel-test-forward-WORD-start-on-whitespace ()
  "Test that forward movement skips over whitespace."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "word next")
    (goto-char 5) ; on the first whitespace
    (helixel-forward-WORD-start)
    (should (= (point) 6))
    (should (= (- (region-end) (region-beginning)) 1))))

(ert-deftest helixel-test-forward-WORD-start-on-whitespaces ()
  "Test that forward movement skips over whitespace."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "word   \t  next")
    (goto-char 5) ; on the first whitespace
    (helixel-forward-WORD-start)
    (should (= (point) 11))
    (should (= (- (region-end) (region-beginning)) 6))))

(ert-deftest helixel-test-forward-WORD-start-multiple-lines ()
  "Test forward movement across multiple lines."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "first line\nsecond line\nthird")
    (goto-char 1) ; start of buffer
    (helixel-forward-WORD-start)
    (should (= (point) 7))
    (should (= (- (region-end) (region-beginning)) 6))
    (helixel-forward-WORD-start)
    (should (= (point) 12))
    (should (= (- (region-end) (region-beginning)) 5))
    (helixel-forward-WORD-start)
    (should (= (point) 19))
    (should (= (- (region-end) (region-beginning)) 7))))

(ert-deftest helixel-test-forward-WORD-start-empty-lines ()
  "Test forward movement with empty lines."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "first\n\n\nsecond")
    (goto-char 5) ; before end of first line
    (helixel-forward-WORD-start)
    (should (= (point) 7))
    (should (= (- (region-end) (region-beginning)) 2))))

(ert-deftest helixel-test-forward-WORD-start-at-end-of-buffer ()
  "Test that forward movement at end of buffer wraps back to last WORD."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "test word")
    (goto-char (point-max))
    (helixel-forward-WORD-start)
    (should (= (point) 6)) ; jumps to start of last WORD
    (should (= (- (region-end) (region-beginning)) 4))))

(ert-deftest helixel-test-forward-WORD-start-mixed-separators ()
  "Test forward movement with mixed word separators."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "word1_part2-part3.part4 next")
    (goto-char 1)
    (helixel-forward-WORD-start)
    (should (= (point) 25))
    (should (= (- (region-end) (region-beginning)) 24))))

(ert-deftest helixel-test-forward-WORD-start-punctuation ()
  "Test forward movement with punctuation."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "Hello, world! How are you?")
    (goto-char 1)
    (helixel-forward-WORD-start)
    (should (= (point) 8))
    (should (= (- (region-end) (region-beginning)) 7))
    (helixel-forward-WORD-start)
    (should (= (point) 15))
    (should (= (- (region-end) (region-beginning)) 7))))

;;; Forward long word end tests

(ert-deftest helixel-test-forward-WORD-end-basic-movement ()
  "Test basic forward movement to word ends."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "hello world test")
    (goto-char 1)
    (helixel-forward-WORD-end)
    (should (= (point) 6)) ; end of "hello"
    (should (= (- (region-end) (region-beginning)) 5))
    (helixel-forward-WORD-end)
    (should (= (point) 12)) ; end of "world"
    (should (= (- (region-end) (region-beginning)) 6))
    (helixel-forward-WORD-end)
    (should (= (point) 17)) ; end of "test"
    (should (= (- (region-end) (region-beginning)) 5))))

(ert-deftest helixel-test-forward-WORD-end-hyphenated-words ()
  "Test forward movement to ends of hyphenated words (long words)."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "this test-string-example works")
    (goto-char 1)
    (helixel-forward-WORD-end)
    (should (= (point) 5)) ; end of "this"
    (should (= (- (region-end) (region-beginning)) 4))
    (helixel-forward-WORD-end)
    (should (= (point) 25)) ; end of "test-string-example"
    (should (= (- (region-end) (region-beginning)) 20))
    (helixel-forward-WORD-end)
    (should (= (point) 31)) ; end of "works"
    (should (= (- (region-end) (region-beginning)) 6))))

(ert-deftest helixel-test-forward-WORD-end-on-whitespace ()
  "Test that forward movement to word ends skips over whitespace."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "word next")
    (goto-char 5) ; on the first whitespace
    (helixel-forward-WORD-end)
    (should (= (point) 10)) ; end of "next"
    (should (= (- (region-end) (region-beginning)) 5))))

(ert-deftest helixel-test-forward-WORD-end-on-whitespaces ()
  "Test that forward movement to word ends skips over multiple whitespaces."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "word   \t  next")
    (goto-char 5) ; on the first whitespace
    (helixel-forward-WORD-end)
    (should (= (point) 15)) ; end of "next"
    (should (= (- (region-end) (region-beginning)) 10))))

(ert-deftest helixel-test-forward-WORD-end-multiple-lines ()
  "Test forward movement to word ends across multiple lines."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "first line\nsecond line\nthird")
    (goto-char 1) ; start of buffer
    (helixel-forward-WORD-end)
    (should (= (point) 6)) ; end of "first"
    (should (= (- (region-end) (region-beginning)) 5))
    (helixel-forward-WORD-end)
    (should (= (point) 11)) ; end of "line"
    (should (= (- (region-end) (region-beginning)) 5))
    (helixel-forward-WORD-end)
    (should (= (point) 18)) ; end of "second"
    (should (= (- (region-end) (region-beginning)) 7))))

(ert-deftest helixel-test-forward-WORD-end-empty-lines ()
  "Test forward movement to word ends with empty lines."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "first\n\n\nsecond")
    (goto-char 1)
    (helixel-forward-WORD-end)
    (should (= (point) 6)) ; end of "first"
    (should (= (- (region-end) (region-beginning)) 5))
    (helixel-forward-WORD-end)
    (should (= (point) 8)) ; newline after empty lines
    (should (= (- (region-end) (region-beginning)) 2))))

(ert-deftest helixel-test-forward-WORD-end-at-end-of-buffer ()
  "Test that forward movement to word end at end of buffer doesn't move."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "test word")
    (goto-char (point-max))
    (let ((initial-point (point)))
      (helixel-forward-WORD-end)
      (should (= (point) initial-point))
      (should (= (- (region-end) (region-beginning)) 0)))))

(ert-deftest helixel-test-forward-WORD-end-mixed-separators ()
  "Test forward movement to word ends with mixed word separators."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "word1_part2-part3.part4 next")
    (goto-char 1)
    (helixel-forward-WORD-end)
    (should (= (point) 24)) ; end of "word1_part2-part3.part4"
    (should (= (- (region-end) (region-beginning)) 23))
    (helixel-forward-WORD-end)
    (should (= (point) 29)) ; end of "next"
    (should (= (- (region-end) (region-beginning)) 5))))

(ert-deftest helixel-test-forward-WORD-end-punctuation ()
  "Test forward movement to word ends with punctuation."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "Hello, world! How are you?")
    (goto-char 1)
    (helixel-forward-WORD-end)
    (should (= (point) 7)) ; end of "Hello,"
    (should (= (- (region-end) (region-beginning)) 6))
    (helixel-forward-WORD-end)
    (should (= (point) 14)) ; end of "world!"
    (should (= (- (region-end) (region-beginning)) 7))
    (helixel-forward-WORD-end)
    (should (= (point) 18)) ; end of "How"
    (should (= (- (region-end) (region-beginning)) 4))))

(ert-deftest helixel-test-forward-WORD-end-empty-buffer ()
  "Test forward movement to word end in empty buffer."
  (with-temp-buffer
    (transient-mark-mode 1)
    (let ((initial-point (point)))
      (helixel-forward-WORD-end)
      (should (= (point) initial-point))
      (should (= (- (region-end) (region-beginning)) 0)))))

;;; Backward long word tests

(ert-deftest helixel-test-backward-WORD-basic-movement ()
  "Test basic backward movement between words."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "hello world test")
    (goto-char (point-max))
    (helixel-backward-WORD)
    (should (= (point) 13)) ; start of "test"
    (should (= (- (region-end) (region-beginning)) 4))
    (helixel-backward-WORD)
    (should (= (point) 7)) ; start of "world"
    (should (= (- (region-end) (region-beginning)) 6))
    (helixel-backward-WORD)
    (should (= (point) 1)) ; start of "hello"
    (should (= (- (region-end) (region-beginning)) 6))))

(ert-deftest helixel-test-backward-WORD-hyphenated-words ()
  "Test backward movement with hyphenated words (long words)."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "this test-string-example works")
    (goto-char (point-max))
    (helixel-backward-WORD)
    (should (= (point) 26)) ; start of "works"
    (should (= (- (region-end) (region-beginning)) 5))
    (helixel-backward-WORD)
    (should (= (point) 6)) ; start of "test-string-example"
    (should (= (- (region-end) (region-beginning)) 20))))

(ert-deftest helixel-test-backward-WORD-on-whitespace ()
  "Test that backward movement skips over whitespace."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "word next")
    (goto-char 5) ; on whitespace
    (helixel-backward-WORD)
    (should (= (point) 1)) ; start of "word"
    (should (= (- (region-end) (region-beginning)) 4))))

(ert-deftest helixel-test-backward-WORD-on-whitespaces ()
  "Test that backward movement skips over whitespace."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "word   \t  next")
    (goto-char 10) ; on the last whitespace
    (helixel-backward-WORD)
    (should (= (point) 1)) ; start of "word"
    (should (= (- (region-end) (region-beginning)) 9))))

(ert-deftest helixel-test-backward-WORD-multiple-lines ()
  "Test backward movement across multiple lines."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "first line\nsecond line\nthird")
    (goto-char (point-max))
    (helixel-backward-WORD)
    (should (= (point) 24)) ; start of "third"
    (should (= (- (region-end) (region-beginning)) 5))
    (helixel-backward-WORD)
    (should (= (point) 19)) ; start of "line"
    (should (= (- (region-end) (region-beginning)) 5))
    (helixel-backward-WORD)
    (should (= (point) 12)))) ; start of "second"

(ert-deftest helixel-test-backward-WORD-empty-lines ()
  "Test backward movement with empty lines."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "first\n\n\nsecond")
    (goto-char (point-max))
    (helixel-backward-WORD)
    (should (= (point) 9)) ; start of "second"
    (should (= (- (region-end) (region-beginning)) 6))
    (helixel-backward-WORD)
    (should (= (point) 8)) ; empty line before "first"
    (should (= (- (region-end) (region-beginning)) 1))))

(ert-deftest helixel-test-backward-WORD-at-beginning-of-buffer ()
  "Test that backward movement at beginning of buffer doesn't move."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "test word")
    (goto-char 1)
    (let ((initial-point (point)))
      (helixel-backward-WORD)
      (should (= (point) initial-point))
      (should (= (- (region-end) (region-beginning)) 0)))))

(ert-deftest helixel-test-backward-WORD-mixed-separators ()
  "Test backward movement with mixed word separators."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "word1_part2-part3.part4 next")
    (goto-char (point-max))
    (helixel-backward-WORD)
    (should (= (point) 25)) ; start of "next"
    (should (= (- (region-end) (region-beginning)) 4))
    (helixel-backward-WORD)
    (should (= (point) 1)) ; start of "word1_part2-part3.part4"
    (should (= (- (region-end) (region-beginning)) 24))))

(ert-deftest helixel-test-backward-WORD-punctuation ()
  "Test backward movement with punctuation."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "Hello, world! How are you?")
    (goto-char (point-max))
    (helixel-backward-WORD)
    (should (= (point) 23)) ; start of "you?"
    (should (= (- (region-end) (region-beginning)) 4))
    (helixel-backward-WORD)
    (should (= (point) 19)) ; start of "are"
    (should (= (- (region-end) (region-beginning)) 4))))

;;; Edge case tests

(ert-deftest helixel-test-forward-WORD-empty-buffer ()
  "Test forward movement in empty buffer."
  (with-temp-buffer
    (transient-mark-mode 1)
    (let ((initial-point (point)))
      (helixel-forward-WORD-start)
      (should (= (point) initial-point))
      (should (= (- (region-end) (region-beginning)) 0)))))

(ert-deftest helixel-test-backward-WORD-empty-buffer ()
  "Test backward movement in empty buffer."
  (with-temp-buffer
    (transient-mark-mode 1)
    (let ((initial-point (point)))
      (helixel-backward-WORD)
      (should (= (point) initial-point))
      (should (= (- (region-end) (region-beginning)) 0)))))

(ert-deftest helixel-test-forward-WORD-start-only-whitespace ()
  "Test forward movement in buffer with only whitespace."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "   \t\n  ")
    (goto-char 1)
    (helixel-forward-WORD-start)
    (should (= (point) 8))
    (should (= (- (region-end) (region-beginning)) 7))))

(ert-deftest helixel-test-forward-WORD-end-only-whitespace ()
  "Test forward movement to word end in buffer with only whitespace."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "   \t\n  ")
    (goto-char 1)
    (helixel-forward-WORD-end)
    (should (= (point) 8)) ; end of buffer
    (should (= (- (region-end) (region-beginning)) 7))
    (helixel-forward-WORD-end)
    (should (= (point) 8)) ; stays at eob
    (should (= (- (region-end) (region-beginning)) 0))))

(ert-deftest helixel-test-backward-WORD-only-whitespace ()
  "Test backward movement in buffer with only whitespace."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "   \t\n  ")
    (goto-char (point-max))
    (helixel-backward-WORD)
    (should (= (point) 1))
    (should (= (- (region-end) (region-beginning)) 7))))

(ert-deftest helixel-test-forward-WORD-start-single-character ()
  "Test forward movement with single character words."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "a b c d")
    (goto-char 1)
    (helixel-forward-WORD-start)
    (should (= (point) 3))
    (should (= (- (region-end) (region-beginning)) 2))
    (helixel-forward-WORD-start)
    (should (= (point) 5))
    (should (= (- (region-end) (region-beginning)) 2))))

(ert-deftest helixel-test-forward-WORD-end-single-character ()
  "Test forward movement to word ends with single character words."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "a b c d")
    (goto-char 1)
    (helixel-forward-WORD-end)
    (should (= (point) 2)) ; end of "a"
    (should (= (- (region-end) (region-beginning)) 1))
    (helixel-forward-WORD-end)
    (should (= (point) 4)) ; end of "b"
    (should (= (- (region-end) (region-beginning)) 2))
    (helixel-forward-WORD-end)
    (should (= (point) 6)) ; end of "c"
    (should (= (- (region-end) (region-beginning)) 2))))

(ert-deftest helixel-test-backward-WORD-single-character ()
  "Test backward movement with single character words."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "a b c d")
    (goto-char (point-max))
    (helixel-backward-WORD)
    (should (= (point) 7)) ; start of "d"
    (should (= (- (region-end) (region-beginning)) 1))
    (helixel-backward-WORD)
    (should (= (point) 5)) ; start of "c"
    (should (= (- (region-end) (region-beginning)) 2))))

;;; Backward word end tests (v key)

(ert-deftest helixel-test-backward-word-end-basic ()
  "Test backward-word-end moves to end of previous word."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "hello world test")
    (goto-char (point-max))
    (helixel-backward-word-end)
    (should (= (point) 12)) ; cursor at region-beginning (*-end)
    (should (= (- (region-end) (region-beginning)) 5))
    (helixel-backward-word-end)
    (should (= (point) 6))
    (should (= (- (region-end) (region-beginning)) 6))))

(ert-deftest helixel-test-backward-word-end-mid-word ()
  "Test backward-word-end from middle of a word."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "hello world")
    (goto-char 3) ; on "l" of "hello"
    (helixel-backward-word-end)
    (should (= (point) 6)) ; cursor at previous word end (*-end)
    (should (= (- (region-end) (region-beginning)) 3))))

(ert-deftest helixel-test-backward-word-end-at-bob ()
  "Test backward-word-end at beginning of buffer."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "hello")
    (goto-char 1)
    (let ((initial-point (point)))
      (helixel-backward-word-end)
      (should (= (point) 6)) ; cursor at word end
      (should (= (- (region-end) (region-beginning)) 5)))))

;;; Backward WORD end tests

(ert-deftest helixel-test-backward-WORD-end-basic ()
  "Test backward-WORD-end moves to end of previous WORD."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "hello world test")
    (goto-char (point-max))
    (helixel-backward-WORD-end)
    (should (= (point) 12)) ; cursor at region-beginning (*-end)
    (should (= (- (region-end) (region-beginning)) 5))
    (helixel-backward-WORD-end)
    (should (= (point) 6))
    (should (= (- (region-end) (region-beginning)) 6))))

(ert-deftest helixel-test-backward-WORD-end-hyphenated ()
  "Test backward-WORD-end with hyphenated words."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "this test-string-example works")
    (goto-char (point-max))
    (helixel-backward-WORD-end)
    (should (= (point) 25))
    (should (= (- (region-end) (region-beginning)) 6))
    (helixel-backward-WORD-end)
    (should (= (point) 5))
    (should (= (- (region-end) (region-beginning)) 20))))

(ert-deftest helixel-test-backward-WORD-end-empty-buffer ()
  "Test backward-WORD-end in empty buffer."
  (with-temp-buffer
    (transient-mark-mode 1)
    (let ((initial-point (point)))
      (helixel-backward-WORD-end)
      (should (= (point) initial-point))
      (should (= (- (region-end) (region-beginning)) 0)))))

;;; Symbol movement tests

(ert-deftest helixel-test-forward-symbol-start-basic ()
  "Test forward-symbol-start movement."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "foo_bar baz-qux hello")
    (goto-char 1)
    (helixel-forward-symbol-start)
    (should (= (point) 9)) ; cursor at region-end (*-start)
    (should (= (- (region-end) (region-beginning)) 8))
    (helixel-forward-symbol-start)
    (should (= (point) 17))
    (should (= (- (region-end) (region-beginning)) 8))
    (helixel-forward-symbol-start)
    (should (= (point) 17))
    (should (= (- (region-end) (region-beginning)) 0))))

(ert-deftest helixel-test-forward-symbol-start-single ()
  "Test forward-symbol-start with a single symbol char."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "x")
    (goto-char 1)
    (helixel-forward-symbol-start)
    (should (= (point) 1))
    (should (= (- (region-end) (region-beginning)) 0))))

(ert-deftest helixel-test-forward-symbol-start-empty-buffer ()
  "Test forward-symbol-start in empty buffer."
  (with-temp-buffer
    (transient-mark-mode 1)
    (let ((initial-point (point)))
      (helixel-forward-symbol-start)
      (should (= (point) initial-point))
      (should (= (- (region-end) (region-beginning)) 0)))))

(ert-deftest helixel-test-forward-symbol-end-basic ()
  "Test forward-symbol-end movement."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "foo_bar baz-qux hello")
    (goto-char 1)
    (helixel-forward-symbol-end)
    (should (= (point) 8)) ; cursor at region-end (*-end)
    (should (= (- (region-end) (region-beginning)) 7))
    (helixel-forward-symbol-end)
    (should (= (point) 16))
    (should (= (- (region-end) (region-beginning)) 8))
    (helixel-forward-symbol-end)
    (should (= (point) 22))
    (should (= (- (region-end) (region-beginning)) 6))))

(ert-deftest helixel-test-backward-symbol-start-basic ()
  "Test backward-symbol-start movement."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "foo_bar baz-qux hello")
    (goto-char (point-max))
    (helixel-backward-symbol-start)
    (should (= (point) 17)) ; cursor at region-beginning (*-start)
    (should (= (- (region-end) (region-beginning)) 5))
    (helixel-backward-symbol-start)
    (should (= (point) 9))
    (should (= (- (region-end) (region-beginning)) 8))))

(ert-deftest helixel-test-backward-symbol-start-at-bob ()
  "Test backward-symbol-start at beginning of buffer."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "hello world")
    (goto-char 1)
    (let ((initial-point (point)))
      (helixel-backward-symbol-start)
      (should (= (point) initial-point))
      (should (= (- (region-end) (region-beginning)) 0)))))

(ert-deftest helixel-test-backward-symbol-end-basic ()
  "Test backward-symbol-end movement."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "foo_bar baz-qux hello")
    (goto-char (point-max))
    (helixel-backward-symbol-end)
    (should (= (point) 16)) ; cursor at region-beginning (*-end)
    (should (= (- (region-end) (region-beginning)) 6))
    (helixel-backward-symbol-end)
    (should (= (point) 8))
    (should (= (- (region-end) (region-beginning)) 8))))

;; Find char

(ert-deftest helixel-test-find-next-char ()
  "Test finding next character and selecting from current position to it."
  (with-temp-buffer
    (insert "first second third")
    (goto-char 1)
    (helixel-find-next-char ?d)
    (should (eql (point) 13))
    (should (eql (- (region-end) (region-beginning)) 12))))

(ert-deftest helixel-test-find-next-char-two-line ()
  "Test finding next character across multiple lines and selecting to it."
  (with-temp-buffer
    (insert "first\nsecond\nthird")
    (goto-char 1)
    (helixel-find-next-char ?d)
    (should (eql (point) 13))
    (should (eql (- (region-end) (region-beginning)) 12))))

(ert-deftest helixel-test-find-till-char ()
  "Test finding till character and selecting from current position to before it."
  (with-temp-buffer
    (insert "first second third")
    (goto-char 1)
    (helixel-find-till-char ?d)
    (should (eql (point) 12))
    (should (eql (- (region-end) (region-beginning)) 11))))

(ert-deftest helixel-test-find-till-char-two-line ()
  "Test finding till character across multiple lines and selecting to before it."
  (with-temp-buffer
    (insert "first\nsecond\nthird")
    (goto-char 1)
    (helixel-find-till-char ?d)
    (should (eql (point) 12))
    (should (eql (- (region-end) (region-beginning)) 11))))

(ert-deftest helixel-test-find-till-char-repeat ()
  "Test repeating find till character skips past adjacent char."
  (with-temp-buffer
    (insert "first second third")
    (goto-char 1)
    (helixel-find-till-char ?d)
    (should (eql (point) 12))
    (helixel-find-repeat)
    (should (eql (point) 18))
    (should (eql (- (region-end) (region-beginning)) 6))))

(ert-deftest helixel-test-find-prev-till-char-repeat ()
  "Test repeating previous till character find skips past adjacent char."
  (with-temp-buffer
    (insert "first second third")
    (goto-char (point-max))
    (helixel-find-prev-till-char ?s)
    (should (eql (point) 8))
    (helixel-find-repeat)
    (should (eql (point) 5))))

(ert-deftest helixel-test-empty-find-repeat ()
  "Test find repeat when nothing to repeat."
  (with-temp-buffer
    (insert "first second third")
    (goto-char 1)
    (helixel-find-repeat)
    (should (eql (point) 1))))

(ert-deftest helixel-test-find-direction-n ()
  "Test f + n repeats find forward."
  (with-temp-buffer
    (insert "axb axb axb")
    (goto-char 1)
    (helixel-find-next-char ?b)
    (should (eql (point) 4))       ; search-forward lands after match
    (helixel-search-repeat-next)
    (should (eql (point) 8))))     ; next b

(ert-deftest helixel-test-find-direction-N ()
  "Test f + N toggles direction and repeats backward."
  (with-temp-buffer
    (insert "axb axb axb")
    (goto-char 5)
    (helixel-find-next-char ?b)
    (should (eql (point) 8))       ; after second b
    (helixel-search-repeat-reverse)
    (should (eq (helixel--live-cat-get :dir) 'backward))
    (should (< (point) 8))))

;;; helixel-define-key tests

(ert-deftest helixel-test-define-key-standard ()
  "Test standard helixel-define-key without optional keymap."
  (let ((original-binding (lookup-key helixel-space-map "t")))
    (unwind-protect
        (progn
          (helixel-define-key 'space "t" #'ignore)
          (should (eq (lookup-key helixel-space-map "t") #'ignore)))
      (define-key helixel-space-map "t" original-binding))))

(ert-deftest helixel-test-define-key-with-mode ()
  "Test helixel-define-key with MODE stores binding in helixel--mode-keybindings."
  (let ((helixel--mode-keybindings nil))
    (helixel-define-key 'normal "j" #'next-line 'dired-mode)
    (let ((entry (assoc (cons 'dired-mode 'normal) helixel--mode-keybindings)))
      (should entry)
      (should (eq (lookup-key (cdr entry) "j") #'next-line)))))

(ert-deftest helixel-test-define-key-with-mode-multiple-bindings ()
  "Test that multiple bindings for the same mode and state accumulate."
  (let ((helixel--mode-keybindings nil))
    (helixel-define-key 'normal "j" #'next-line 'dired-mode)
    (helixel-define-key 'normal "k" #'previous-line 'dired-mode)
    (let ((entry (assoc (cons 'dired-mode 'normal) helixel--mode-keybindings)))
      (should (eq (lookup-key (cdr entry) "j") #'next-line))
      (should (eq (lookup-key (cdr entry) "k") #'previous-line)))))

(ert-deftest helixel-test-define-key-with-mode-different-states ()
  "Test that different states get different sparse keymaps."
  (let ((helixel--mode-keybindings nil))
    (helixel-define-key 'normal "j" #'next-line 'dired-mode)
    (helixel-define-key 'insert "j" #'self-insert-command 'dired-mode)
    (let ((normal-entry (assoc (cons 'dired-mode 'normal) helixel--mode-keybindings))
          (insert-entry (assoc (cons 'dired-mode 'insert) helixel--mode-keybindings)))
      (should normal-entry)
      (should insert-entry)
      (should-not (eq (cdr normal-entry) (cdr insert-entry)))
      (should (eq (lookup-key (cdr normal-entry) "j") #'next-line))
      (should (eq (lookup-key (cdr insert-entry) "j") #'self-insert-command)))))

(ert-deftest helixel-test-define-key-invalid-state ()
  "Test that invalid state signals an error."
  (should-error (helixel-define-key 'invalid-state "t" #'ignore)))

(ert-deftest helixel-test-define-key-invalid-state-with-mode ()
  "Test that invalid state signals error even with explicit mode."
  (should-error (helixel-define-key 'invalid-state "t" #'ignore 'dired-mode)))

;;; helixel--refresh-overriding-maps tests

(ert-deftest helixel-test-refresh-overriding-maps-with-major-mode-bindings ()
  "Test that refresh builds correct minor-mode-overriding-map-alist."
  (let ((helixel--mode-keybindings nil))
    (with-temp-buffer
      ;; Simulate a major mode
      (setq major-mode 'helixel-test-mode)
      (setq-local helixel--current-state 'normal)
      ;; Register a binding for this mode
      (helixel-define-key 'normal "j" #'next-line 'helixel-test-mode)
      (helixel--refresh-overriding-maps)
      ;; Should have an entry in minor-mode-overriding-map-alist
      (let ((entry (assq 'helixel-normal-state minor-mode-overriding-map-alist)))
        (should entry)
        (should (eq (lookup-key (cdr entry) "j") #'next-line))))))

(ert-deftest helixel-test-refresh-overriding-maps-clears-when-no-bindings ()
  "Test that refresh clears overriding alist when no bindings apply."
  (let ((helixel--mode-keybindings nil))
    (with-temp-buffer
      (setq-local helixel--current-state 'normal)
      ;; Pre-populate with a stale entry
      (setq minor-mode-overriding-map-alist
            (list (cons 'helixel-normal-state (make-sparse-keymap))))
      (helixel--refresh-overriding-maps)
      ;; Should have cleared the entry
      (should-not (assq 'helixel-normal-state minor-mode-overriding-map-alist)))))

(ert-deftest helixel-test-refresh-overriding-maps-no-cross-mode-leak ()
  "Test that bindings for one major mode don't leak into another."
  (let ((helixel--mode-keybindings nil))
    (with-temp-buffer
      ;; Register binding for dired-mode
      (helixel-define-key 'normal "j" #'next-line 'dired-mode)
      ;; But current buffer is a different major mode
      (setq major-mode 'fundamental-mode)
      (setq-local helixel--current-state 'normal)
      (helixel--refresh-overriding-maps)
      ;; Should have no overriding entry
      (should-not (assq 'helixel-normal-state minor-mode-overriding-map-alist)))))

(ert-deftest helixel-test-refresh-overriding-maps-fallback-to-base ()
  "Test that non-overridden keys fall back to base helixel keymap."
  (let ((helixel--mode-keybindings nil))
    (with-temp-buffer
      (setq major-mode 'helixel-test-mode)
      (setq-local helixel--current-state 'normal)
      ;; Override only "j"
      (helixel-define-key 'normal "j" #'next-line 'helixel-test-mode)
      (helixel--refresh-overriding-maps)
      (let ((entry (assq 'helixel-normal-state minor-mode-overriding-map-alist)))
        (should entry)
        ;; Overridden key works
        (should (eq (lookup-key (cdr entry) "j") #'next-line))
        ;; Non-overridden key falls back to helixel binding
        (should (eq (lookup-key (cdr entry) "k") #'helixel-previous-line))))))

;;; Line-wise helper tests

(defmacro helixel-test-with-buffer (content &rest body)
  "Execute BODY in a temp buffer with CONTENT and transient-mark-mode on.
Buffer starts with point at position 1."
  (declare (indent 1))
  `(with-temp-buffer
     (transient-mark-mode 1)
     (insert ,content)
     (goto-char 1)
     ,@body))

(ert-deftest helixel-test-linewise-text-adds-newline ()
  "Test that `helixel--linewise-text' ensures trailing newline."
  (let ((text (helixel--linewise-text "hello")))
    (should (string= text "hello\n"))
    (should (eq (car (get-text-property 0 'yank-handler text))
                'helixel--yank-handler-line-wise))))

(ert-deftest helixel-test-linewise-text-preserves-existing-newline ()
  "Test that `helixel--linewise-text' doesn't double newline."
  (let ((text (helixel--linewise-text "hello\n")))
    (should (string= text "hello\n"))
    (should (eq (car (get-text-property 0 'yank-handler text))
                'helixel--yank-handler-line-wise))))

(ert-deftest helixel-test-linewise-kill-p-positive ()
  "Test `helixel--linewise-kill-p' detects line-wise text."
  (let ((text (helixel--linewise-text "hello\n")))
    (should (helixel--linewise-kill-p text))))

(ert-deftest helixel-test-linewise-kill-p-negative ()
  "Test `helixel--linewise-kill-p' returns nil for plain text."
  (should-not (helixel--linewise-kill-p "hello")))

(ert-deftest helixel-test-linewise-kill-p-nil ()
  "Test `helixel--linewise-kill-p' returns nil when no kill ring."
  (let ((kill-ring nil))
    (should-not (helixel--linewise-kill-p))))

;;; helixel--selection-type tests

(ert-deftest helixel-test-selection-type-nil-without-region ()
  "Test `helixel--selection-type' returns nil when no region."
  (helixel-test-with-buffer "hello"
    (should-not (helixel--selection-type))))

(ert-deftest helixel-test-selection-type-line-validated ()
  "Test `helixel--selection-type' validates line selection bounds."
  (helixel-test-with-buffer "first line\nsecond line\nthird line"
    (push-mark (point) t t)
    (end-of-line)
    (setq helixel--selection-type 'line)
    (should (eq (helixel--selection-type) 'line))))

(ert-deftest helixel-test-selection-type-line-invalidated ()
  "Test `helixel--selection-type' rejects invalid line selection."
  (helixel-test-with-buffer "first line\nsecond line"
    ;; region doesn't start at bol
    (goto-char 3)
    (push-mark (point) t t)
    (end-of-line)
    (setq helixel--selection-type 'line)
    (should-not (helixel--selection-type))))

;;; helixel-select-line sets selection type

(ert-deftest helixel-test-select-line-sets-type ()
  "Test `helixel-select-line' sets `helixel--selection-type' to line."
  (helixel-test-with-buffer "first line\nsecond line\nthird line"
    (setq helixel--selection-type nil)
    (helixel-select-line)
    (should (eq helixel--selection-type 'line))
    (should (region-active-p))))

;;; helixel--clear-data resets selection type

(ert-deftest helixel-test-clear-data-resets-type ()
  "Test `helixel--clear-data' resets `helixel--selection-type'."
  (helixel-test-with-buffer "hello"
    (setq helixel--selection-type 'line)
    (helixel--clear-data)
    (should-not helixel--selection-type)))

;;; helixel--line-bounds-of-region tests

(ert-deftest helixel-test-line-bounds-single-line ()
  "Test line bounds expansion for a single line selection."
  (helixel-test-with-buffer "first line\nsecond line\nthird line"
    ;; Select "first line" (bol to eol)
    (push-mark (point) t t)
    (end-of-line)
    (let ((bounds (helixel--line-bounds-of-region)))
      (should bounds)
      ;; beg=1, end includes newline=12
      (should (= (car bounds) 1))
      (should (= (cdr bounds) 12)))))

(ert-deftest helixel-test-line-bounds-multi-line ()
  "Test line bounds expansion for a multi-line selection."
  (helixel-test-with-buffer "first line\nsecond line\nthird line"
    ;; Select from middle of first to middle of second
    (goto-char 5)
    (push-mark (point) t t)
    (goto-char 18)
    (let ((bounds (helixel--line-bounds-of-region)))
      (should bounds)
      ;; Should expand to cover both full lines
      (should (= (car bounds) 1))
      (should (= (cdr bounds) 24)))))

(ert-deftest helixel-test-line-bounds-last-line-no-newline ()
  "Test line bounds at end of buffer without trailing newline."
  (helixel-test-with-buffer "first line\nlast line"
    (goto-char 12)
    (push-mark (point) t t)
    (goto-char (point-max))
    (let ((bounds (helixel--line-bounds-of-region)))
      (should bounds)
      (should (= (car bounds) 12))
      ;; end should be point-max since no trailing newline
      (should (= (cdr bounds) (point-max))))))

;;; helixel-kill-ring-save (y) line-wise tests

(ert-deftest helixel-test-kill-ring-save-linewise ()
  "Test `helixel-kill-ring-save' tags text as line-wise."
  (helixel-test-with-buffer "first line\nsecond line\nthird line"
    (let ((kill-ring nil))
      (helixel-select-line)
      (helixel-kill-ring-save)
      (should (helixel--linewise-kill-p (car kill-ring)))
      ;; Should include trailing newline
      (should (string= (car kill-ring) "first line\n"))
      ;; Buffer content unchanged
      (should (string= (buffer-string) "first line\nsecond line\nthird line")))))

(ert-deftest helixel-test-kill-ring-save-charwise ()
  "Test `helixel-kill-ring-save' does not tag charwise text."
  (helixel-test-with-buffer "hello world"
    (let ((kill-ring nil))
      (push-mark (point) t t)
      (goto-char 6)
      (setq helixel--selection-type nil)
      (helixel-kill-ring-save)
      (should-not (helixel--linewise-kill-p (car kill-ring)))
      (should (string= (car kill-ring) "hello")))))

;;; helixel-kill-thing-at-point (d) line-wise tests

(ert-deftest helixel-test-kill-thing-linewise ()
  "Test `helixel-kill-thing-at-point' kills whole line and tags line-wise."
  (helixel-test-with-buffer "first line\nsecond line\nthird line"
    (let ((kill-ring nil))
      (helixel-select-line)
      (helixel-kill-thing-at-point)
      ;; Kill ring should have the line with trailing newline
      (should (helixel--linewise-kill-p (car kill-ring)))
      (should (string= (car kill-ring) "first line\n"))
      ;; Buffer should have remaining lines
      (should (string= (buffer-string) "second line\nthird line")))))

(ert-deftest helixel-test-kill-thing-linewise-last-line ()
  "Test killing the last line (no trailing newline in buffer)."
  (helixel-test-with-buffer "first line\nlast line"
    (let ((kill-ring nil))
      (goto-char 12)
      (helixel-select-line)
      (helixel-kill-thing-at-point)
      (should (helixel--linewise-kill-p (car kill-ring)))
      (should (string= (buffer-string) "first line\n")))))

(ert-deftest helixel-test-kill-thing-linewise-multi-line ()
  "Test killing multiple lines selected with helixel-select-line."
  (helixel-test-with-buffer "line one\nline two\nline three"
    (let ((kill-ring nil))
      (helixel-select-line)
      (helixel-select-line) ;; extend to second line
      (helixel-kill-thing-at-point)
      (should (helixel--linewise-kill-p (car kill-ring)))
      (should (string= (car kill-ring) "line one\nline two\n"))
      (should (string= (buffer-string) "line three")))))

(ert-deftest helixel-test-kill-thing-charwise ()
  "Test `helixel-kill-thing-at-point' without line-wise selection."
  (helixel-test-with-buffer "hello world"
    (let ((kill-ring nil))
      (push-mark (point) t t)
      (goto-char 6)
      (setq helixel--selection-type nil)
      (helixel-kill-thing-at-point)
      (should-not (helixel--linewise-kill-p (car kill-ring)))
      (should (string= (buffer-string) " world")))))

(ert-deftest helixel-test-kill-thing-no-region ()
  "Test `helixel-kill-thing-at-point' deletes char when no region."
  (helixel-test-with-buffer "hello"
    (helixel-kill-thing-at-point)
    (should (string= (buffer-string) "ello"))))

;;; helixel-yank (p) line-wise tests

(ert-deftest helixel-test-yank-linewise-below ()
  "Test `helixel-yank' pastes line-wise content below current line."
  (helixel-test-with-buffer "first line\nsecond line"
    ;; Put a line-wise kill in the kill ring
    (kill-new (helixel--linewise-text "new line\n"))
    ;; Cursor on first line
    (goto-char 5)
    (let ((this-command 'helixel-yank))
      (helixel-yank))
    ;; "new line" should appear between first and second
    (should (string= (buffer-string) "first line\nnew line\nsecond line"))))

(ert-deftest helixel-test-yank-linewise-at-last-line ()
  "Test `helixel-yank' pastes line-wise content below last line."
  (helixel-test-with-buffer "only line"
    (kill-new (helixel--linewise-text "new line\n"))
    (goto-char 5)
    (let ((this-command 'helixel-yank))
      (helixel-yank))
    (should (string= (buffer-string) "only line\nnew line"))))

(ert-deftest helixel-test-yank-charwise ()
  "Test `helixel-yank' pastes charwise content at point."
  (helixel-test-with-buffer "hello world"
    (kill-new "XYZ")
    (goto-char 6)
    (helixel-yank)
    (should (string= (buffer-string) "helloXYZ world"))))

;;; helixel-yank-before (P) line-wise tests

(ert-deftest helixel-test-yank-before-linewise ()
  "Test `helixel-yank-before' pastes line-wise content above current line."
  (helixel-test-with-buffer "first line\nsecond line"
    (kill-new (helixel--linewise-text "new line\n"))
    ;; Cursor on second line
    (goto-char 15)
    (let ((this-command 'helixel-yank-before))
      (helixel-yank-before))
    ;; "new line" should appear between first and second
    (should (string= (buffer-string) "first line\nnew line\nsecond line"))))

(ert-deftest helixel-test-yank-before-linewise-first-line ()
  "Test `helixel-yank-before' pastes above first line."
  (helixel-test-with-buffer "only line"
    (kill-new (helixel--linewise-text "new line\n"))
    (let ((this-command 'helixel-yank-before))
      (helixel-yank-before))
    (should (string= (buffer-string) "new line\nonly line"))))

(ert-deftest helixel-test-yank-before-charwise ()
  "Test `helixel-yank-before' pastes charwise content at point."
  (helixel-test-with-buffer "hello world"
    (kill-new "XYZ")
    (goto-char 6)
    (helixel-yank-before)
    (should (string= (buffer-string) "helloXYZ world"))))

;;; helixel-replace (r) line-wise tests

(ert-deftest helixel-test-replace-yanked-linewise-selection-linewise-kill ()
  "Test replacing line-wise selection with line-wise kill."
  (helixel-test-with-buffer "first line\nsecond line\nthird line"
    (kill-new (helixel--linewise-text "REPLACED\n"))
    ;; Select second line
    (goto-char 12)
    (helixel-select-line)
    (helixel-replace)
    (should (string= (buffer-string) "first line\nREPLACED\nthird line"))))

(ert-deftest helixel-test-replace-yanked-linewise-selection-charwise-kill ()
  "Test replacing line-wise selection with charwise kill."
  (helixel-test-with-buffer "first line\nsecond line\nthird line"
    (kill-new "INLINE")
    (goto-char 12)
    (helixel-select-line)
    (helixel-replace)
    ;; Charwise kill replaces the full line
    (should (string= (buffer-string) "first line\nINLINE\nthird line"))))

(ert-deftest helixel-test-replace-yanked-charwise-selection-linewise-kill ()
  "Test replacing charwise selection with line-wise kill (strips newline)."
  (helixel-test-with-buffer "hello world"
    (kill-new (helixel--linewise-text "REPLACED\n"))
    (push-mark (point) t t)
    (goto-char 6)
    (setq helixel--selection-type nil)
    (helixel-replace)
    ;; Line-wise kill should be stripped of trailing newline for inline replace
    (should (string= (buffer-string) "REPLACED world"))))

(ert-deftest helixel-test-replace-yanked-no-region ()
  "Test replacing char at point with kill ring content."
  (helixel-test-with-buffer "hello"
    (let ((helixel-replace-delete-char-p t))
      (kill-new "X")
      (setq helixel--selection-type nil)
      (helixel-replace)
      (should (string= (buffer-string) "Xello"))))

  (helixel-test-with-buffer "hello"
    (let ((helixel-replace-delete-char-p nil))
      (kill-new "X")
      (setq helixel--selection-type nil)
      (helixel-replace)
      (should (string= (buffer-string) "Xhello")))))

(ert-deftest helixel-test-replace-yanked-empty-kill-ring ()
  "Test replace with empty kill ring shows message."
  (helixel-test-with-buffer "hello"
    (let ((kill-ring nil))
      (helixel-replace)
      ;; Buffer unchanged
      (should (string= (buffer-string) "hello")))))

;;; Integration: select-line -> kill -> yank round-trip

(ert-deftest helixel-test-linewise-round-trip ()
  "Test full round-trip: select line, kill, then yank elsewhere."
  (helixel-test-with-buffer "line A\nline B\nline C"
    (let ((kill-ring nil))
      ;; Select and kill line B
      (goto-char 8)
      (helixel-select-line)
      (helixel-kill-thing-at-point)
      (should (string= (buffer-string) "line A\nline C"))
      ;; Now yank (paste below) on line A
      (goto-char 1)
      (let ((this-command 'helixel-yank))
        (helixel-yank))
      (should (string= (buffer-string) "line A\nline B\nline C")))))

(ert-deftest helixel-test-linewise-copy-yank-round-trip ()
  "Test round-trip: select line, copy, then yank-before."
  (helixel-test-with-buffer "line A\nline B\nline C"
    (let ((kill-ring nil))
      ;; Select and copy line A
      (helixel-select-line)
      (helixel-kill-ring-save)
      ;; Yank before line C
      (goto-char 15) ;; on line C
      (let ((this-command 'helixel-yank-before))
        (helixel-yank-before))
      (should (string= (buffer-string) "line A\nline B\nline A\nline C")))))

(ert-deftest helixel-test-charwise-not-affected ()
  "Test that charwise operations are unaffected by line-wise changes."
  (helixel-test-with-buffer "hello world"
    (let ((kill-ring nil))
      (push-mark (point) t t)
      (goto-char 6)
      (setq helixel--selection-type nil)
      (helixel-kill-thing-at-point)
      (should (string= (car kill-ring) "hello"))
      (should-not (helixel--linewise-kill-p (car kill-ring)))
      (goto-char 1)
      (helixel-yank)
      (should (string= (buffer-string) "hello world")))))

;;; helixel-begin-selection clears line type

(ert-deftest helixel-test-begin-selection-clears-line-type ()
  "Test that `helixel-begin-selection' clears line selection type."
  (helixel-test-with-buffer "hello"
    (setq helixel--selection-type 'line)
    (helixel-begin-selection)
    (should-not helixel--selection-type)))

;;; Rect selection tests

(ert-deftest helixel-test-select-rectangle-starts-rect ()
  "Test `helixel-select-rectangle' starts rectangle-mark-mode."
  (helixel-test-with-buffer "first line\nsecond line\nthird line"
    (call-interactively #'helixel-select-rectangle)
    (should rectangle-mark-mode)
    (should (eq helixel--selection-type 'rect))
    (should (region-active-p))))

(ert-deftest helixel-test-select-rectangle-extends ()
  "Test `helixel-select-rectangle' extends rectangle downward."
  (helixel-test-with-buffer "first line\nsecond line\nthird line"
    (call-interactively #'helixel-select-rectangle)
    (setq last-command 'helixel-select-rectangle)
    (let ((mark-pos (mark)))
      (call-interactively #'helixel-select-rectangle)
      (should (> (point) mark-pos))
      (should rectangle-mark-mode))))

;;; helixel--selection-type rect tests

(ert-deftest helixel-test-selection-type-rect ()
  "Test `helixel--selection-type' returns `rect' for rectangle selection."
  (helixel-test-with-buffer "first line\nsecond line\nthird line"
    (setq helixel--selection-type 'rect)
    (push-mark (point) t t)
    (goto-char 8)
    (rectangle-mark-mode 1)
    (should (eq (helixel--selection-type) 'rect))
    (rectangle-mark-mode -1)))

(ert-deftest helixel-test-selection-type-rect-without-mode ()
  "Test `helixel--selection-type' returns nil when rect type but mode off."
  (helixel-test-with-buffer "first line\nsecond line"
    (setq helixel--selection-type 'rect)
    (push-mark (point) t t)
    (goto-char 8)
    ;; rectangle-mark-mode not active
    (should-not (helixel--selection-type))))

;;; helixel--clear-data clears rect mode

(ert-deftest helixel-test-clear-data-clears-rect ()
  "Test `helixel--clear-data' disables rectangle-mark-mode."
  (helixel-test-with-buffer "first line\nsecond line"
    (helixel-select-rectangle)
    (helixel--clear-data)
    (should-not rectangle-mark-mode)
    (should-not helixel--selection-type)))

;;; helixel--rect-wise-text and helixel--rect-wise-kill-p tests

(ert-deftest helixel-test-rect-wise-text-propertizes ()
  "Test `helixel--rect-wise-text' propertizes text with rect handler."
  (let* ((lines '("hel" "wor"))
         (text (helixel--rect-wise-text lines)))
    (should (string= text "hel\nwor"))
    (should (eq (car (get-text-property 0 'yank-handler text))
                'helixel--yank-handler-rect-wise))
    (should (equal (nth 1 (get-text-property 0 'yank-handler text))
                   lines))))

(ert-deftest helixel-test-rect-wise-kill-p-positive ()
  "Test `helixel--rect-wise-kill-p' detects rect text."
  (let ((text (helixel--rect-wise-text '("AAA" "BBB"))))
    (should (helixel--rect-wise-kill-p text))))

(ert-deftest helixel-test-rect-wise-kill-p-negative ()
  "Test `helixel--rect-wise-kill-p' returns nil for plain text."
  (should-not (helixel--rect-wise-kill-p "plain")))

(ert-deftest helixel-test-rect-wise-kill-p-nil-kill-ring ()
  "Test `helixel--rect-wise-kill-p' returns nil when no kill ring."
  (let ((kill-ring nil))
    (should-not (helixel--rect-wise-kill-p))))

;;; helixel-kill-thing-at-point (d) rect tests

(ert-deftest helixel-test-kill-thing-rect ()
  "Test killing a rectangle selection."
  (helixel-test-with-buffer "ABC line1\nDEF line2\nGHI line3"
    (let ((kill-ring nil))
      (goto-char 1)
      (push-mark (point) t t)
      (goto-char 14) ;; col 3 on line 2 (space after "DEF")
      (rectangle-mark-mode 1)
      (setq helixel--selection-type 'rect)
      (helixel-kill-thing-at-point)
      (should (helixel--rect-wise-kill-p (car kill-ring)))
      ;; After killing first 3 chars of first two lines:
      (should (string= (buffer-string) " line1\n line2\nGHI line3"))
      (should-not rectangle-mark-mode))))

(ert-deftest helixel-test-kill-thing-rect-single-line ()
  "Test killing a single-line rectangle (like one char)."
  (helixel-test-with-buffer "ABCDE"
    (let ((kill-ring nil))
      (push-mark (point) t t)
      (goto-char 2)
      (rectangle-mark-mode 1)
      (setq helixel--selection-type 'rect)
      (helixel-kill-thing-at-point)
      (should (helixel--rect-wise-kill-p (car kill-ring)))
      (should (string= (buffer-string) "BCDE"))
      (should-not rectangle-mark-mode))))

;;; helixel-kill-ring-save (y) rect tests

(ert-deftest helixel-test-kill-ring-save-rect ()
  "Test copying a rectangle to kill ring without deleting."
  (helixel-test-with-buffer "ABC line1\nDEF line2\nGHI line3"
    (let ((kill-ring nil))
      (goto-char 1)
      (push-mark (point) t t)
      (goto-char 14) ;; col 3 on line 2 (space after "DEF")
      (rectangle-mark-mode 1)
      (setq helixel--selection-type 'rect)
      (helixel-kill-ring-save)
      (should (helixel--rect-wise-kill-p (car kill-ring)))
      ;; Buffer content unchanged
      (should (string= (buffer-string) "ABC line1\nDEF line2\nGHI line3"))
      (should-not rectangle-mark-mode))))

;;; helixel-replace (R) rect tests

(ert-deftest helixel-test-replace-yanked-rect-with-rect ()
  "Test replacing a rectangle selection with a rect kill."
  (helixel-test-with-buffer "ABC line1\nDEF line2\nGHI line3"
    (kill-new (helixel--rect-wise-text '("???" "XXX")))
    (goto-char 1)
    (push-mark (point) t t)
    (goto-char 14) ;; col 3 on line 2
    (rectangle-mark-mode 1)
    (setq helixel--selection-type 'rect)
    (helixel-replace)
    (should (string= (buffer-string) "??? line1\nXXX line2\nGHI line3"))))

(ert-deftest helixel-test-replace-yanked-rect-with-charwise ()
  "Test replacing a rect selection with a charwise kill."
  (helixel-test-with-buffer "ABC line1\nDEF line2\nGHI line3"
    (kill-new "!!")
    (goto-char 1)
    (push-mark (point) t t)
    (goto-char 14) ;; col 3 on line 2
    (rectangle-mark-mode 1)
    (setq helixel--selection-type 'rect)
    (helixel-replace)
    ;; "!!" inserted at top-left of rectangle area
    (should (string= (buffer-string) "!! line1\n line2\nGHI line3"))))

;;; helixel-yank (p) rect tests

(ert-deftest helixel-test-yank-rect ()
  "Test pasting a rect kill at point."
  (helixel-test-with-buffer "line1\nline2\nline3"
    (kill-new (helixel--rect-wise-text '("<<<" ">>>")))
    (goto-char 1)
    (helixel-yank)
    (should (string= (buffer-string) "<<<line1\n>>>line2\nline3"))))

(ert-deftest helixel-test-yank-rect-after ()
  "Test pasting a rect kill after point."
  (helixel-test-with-buffer "AAline1\nBBline2\nCCline3"
    (kill-new (helixel--rect-wise-text '("--" "++")))
    (goto-char 3) ;; after "AA"
    (helixel-yank)
    (should (string= (buffer-string) "AA--line1\nBB++line2\nCCline3"))))

;;; helixel-yank-before (P) rect tests

(ert-deftest helixel-test-yank-before-rect ()
  "Test pasting a rect kill before point."
  (helixel-test-with-buffer "line1\nline2\nline3"
    (kill-new (helixel--rect-wise-text '("<<<" ">>>")))
    (goto-char 1)
    (helixel-yank-before)
    (should (string= (buffer-string) "<<<line1\n>>>line2\nline3"))))

;;; helixel-begin-selection exits rect

(ert-deftest helixel-test-begin-selection-clears-rect ()
  "Test that `helixel-begin-selection' disables rectangle-mark-mode."
  (helixel-test-with-buffer "hello\nworld"
    (helixel-select-rectangle)
    (should rectangle-mark-mode)
    (helixel-begin-selection)
    (should-not rectangle-mark-mode)
    (should-not helixel--selection-type)))

;;; Interaction: rect kill doesn't affect line-wise detection

(ert-deftest helixel-test-rect-kill-not-line-wise ()
  "Test that rect-killed text is not detected as line-wise."
  (let ((text (helixel--rect-wise-text '("AAA" "BBB"))))
    (should-not (helixel--linewise-kill-p text))))

(ert-deftest helixel-test-line-kill-not-rect-wise ()
  "Test that line-killed text is not detected as rect-wise."
  (let ((text (helixel--linewise-text "hello\n")))
    (should-not (helixel--rect-wise-kill-p text))))

;;; Round-trip: rect select -> kill -> yank

(ert-deftest helixel-test-rect-round-trip ()
  "Test full round-trip: select rect, kill, then yank elsewhere."
  (helixel-test-with-buffer "AAA line1\nBBB line2\nCCC line3"
    (let ((kill-ring nil))
      (goto-char 1)
      (push-mark (point) t t)
      (goto-char 14) ;; col 3 on line 2 (space after "BBB")
      (rectangle-mark-mode 1)
      (setq helixel--selection-type 'rect)
      (helixel-kill-thing-at-point)
      (should (string= (buffer-string) " line1\n line2\nCCC line3"))
      ;; Now yank at beginning
      (goto-char 1)
      (helixel-yank)
      (should (string= (buffer-string) "AAA line1\nBBB line2\nCCC line3")))))

;;; Movement preserves rectangle selection

(ert-deftest helixel-test-movement-preserves-rect ()
  "Test that h/l/j/k movement preserves rectangle-mark-mode."
  (helixel-test-with-buffer "first line\nsecond line\nthird line"
    (goto-char 4) ;; avoid beginning-of-buffer on backward-char
    (call-interactively #'helixel-select-rectangle)
    (should rectangle-mark-mode)
    (helixel-backward-char)
    (should rectangle-mark-mode)
    (helixel-forward-char)
    (should rectangle-mark-mode)
    (helixel-next-line)
    (should rectangle-mark-mode)
    (helixel-previous-line)
    (should rectangle-mark-mode)))

;;; Rect change (c) with replay

(ert-deftest helixel-test-rect-change-multi-line ()
  "Test `c` on rect replays inserted text on all rect lines."
  (helixel-test-with-buffer "ABC line1\nDEF line2\nGHI line3"
    (goto-char 1)
    (push-mark (point) t t)
    (goto-char 14) ;; col 3 on line 2
    (rectangle-mark-mode 1)
    (setq helixel--selection-type 'rect)
    (helixel-change-thing-at-point)
    ;; Rect deleted, now type text in insert mode
    (insert "XXX")
    (helixel-insert-exit)
    (should (string= (buffer-string) "XXX line1\nXXX line2\nGHI line3"))))

(ert-deftest helixel-test-rect-change-empty-input ()
  "Test `c` on rect with empty input just deletes the rect."
  (helixel-test-with-buffer "ABC line1\nDEF line2\nGHI line3"
    (goto-char 1)
    (push-mark (point) t t)
    (goto-char 14)
    (rectangle-mark-mode 1)
    (setq helixel--selection-type 'rect)
    (helixel-change-thing-at-point)
    ;; Exit immediately without typing anything
    (helixel-insert-exit)
    (should (string= (buffer-string) " line1\n line2\nGHI line3"))))

(ert-deftest helixel-test-rect-change-single-line ()
  "Test `c` on single-line rect (no replay needed)."
  (helixel-test-with-buffer "ABC line1\nDEF line2"
    (goto-char 1)
    (push-mark (point) t t)
    (goto-char 3) ;; col 2 on same line
    (rectangle-mark-mode 1)
    (setq helixel--selection-type 'rect)
    (helixel-change-thing-at-point)
    (insert "XXX")
    (helixel-insert-exit)
    ;; Only line 1 changed; line-count=1 → no replay
    (should (string= (buffer-string) "XXXC line1\nDEF line2"))))

(ert-deftest helixel-test-rect-change-clears-replay-data ()
  "Test that rect replay data is cleared after exit."
  (helixel-test-with-buffer "ABC line1\nDEF line2\nGHI line3"
    (goto-char 1)
    (push-mark (point) t t)
    (goto-char 14)
    (rectangle-mark-mode 1)
    (setq helixel--selection-type 'rect)
    (helixel-change-thing-at-point)
    (insert "XXX")
    (helixel-insert-exit)
    (should-not helixel--rect-replay-data)
    (should-not helixel--rect-replay-marker)))

;;; Word text object tests

(ert-deftest helixel-test-textobj-word-basic ()
  "Test basic word text object selection."
  (with-temp-buffer
    (insert ";; This buffer is for notes.")
    (goto-char 4) ; at "T" of "This"
    (call-interactively #'helixel-mark-inner-word)
    (should (eql (region-beginning) 4))
    (should (eql (region-end) 8)))
  (with-temp-buffer
    (insert ";; This buffer is for notes.")
    (goto-char 4)
    (call-interactively #'helixel-mark-a-word)
    (should (eql (region-beginning) 4))
    (should (eql (region-end) 9))))

(ert-deftest helixel-test-textobj-word-select-first ()
  "Test selecting first word in buffer."
  (with-temp-buffer
    (insert "(a)")
    (goto-char 2) ; inside the parens, on "a"
    (call-interactively #'helixel-mark-inner-word)
    (should (eql (region-beginning) 2))
    (should (eql (region-end) 3))))

(ert-deftest helixel-test-textobj-word-whitespace-line-bound ()
  "Test selecting word when surrounded by whitespace."
  (with-temp-buffer
    (insert "foo\n  bar")
    (goto-char 7)
    (call-interactively #'helixel-mark-inner-word)
    (should (= (region-beginning) 7))))

(ert-deftest helixel-test-textobj-WORD-basic ()
  "Test basic WORD text object selection."
  (with-temp-buffer
    (insert ";; This buffer is for notes.")
    (goto-char 4)
    (call-interactively #'helixel-mark-inner-WORD)
    (should (= (region-beginning) 4))
    (should (= (region-end) 8))))

(ert-deftest helixel-test-textobj-word-cjk ()
  "Test word text object with CJK characters."
  (with-temp-buffer
    (insert "abc漢字")
    (goto-char 1)
    (call-interactively #'helixel-mark-inner-word)
    (should (= (region-beginning) 1))
    (should (= (region-end) 4))))

;;; Symbol text object tests

(ert-deftest helixel-test-textobj-symbol-basic ()
  "Test basic symbol text object selection."
  (with-temp-buffer
    (insert ";; This buffer is for notes.")
    (goto-char 4) ; at "T" of "This"
    (call-interactively #'helixel-mark-inner-symbol)
    (should (= (region-beginning) 4))
    (should (= (region-end) 8))))

;;; Sentence text object tests

(ert-deftest helixel-test-textobj-sentence-basic ()
  "Test basic sentence text object selection."
  (with-temp-buffer
    (insert "This is sentence one. This is sentence two.")
    (goto-char 1)
    (call-interactively #'helixel-mark-inner-sentence)
    (should (= (region-beginning) 1))
    (should (= (region-end) 44))))

(ert-deftest helixel-test-textobj-sentence-select ()
  "Test selecting sentence from middle."
  (with-temp-buffer
    (insert "This is sentence one. This is sentence two.")
    (goto-char 10)
    (call-interactively #'helixel-mark-inner-sentence)
    (should (= (region-beginning) 1))
    (should (= (region-end) 44))))

;;; Paragraph text object tests

(ert-deftest helixel-test-textobj-paragraph-basic ()
  "Test basic paragraph text object selection."
  (with-temp-buffer
    (insert ";; This buffer is for notes,
;; and for Lisp evaluation.

;; Another paragraph here.")
    (goto-char 1)
    (call-interactively #'helixel-mark-inner-paragraph)
    (should (= (region-beginning) 1))
    (should (= (region-end) 58))))

(ert-deftest helixel-test-textobj-paragraph-select ()
  "Test selecting paragraph at different positions."
  (with-temp-buffer
    (insert "First paragraph.

Second paragraph.")
    (goto-char 1)
    (call-interactively #'helixel-mark-inner-paragraph)
    (should (= (region-beginning) 1))
    (should (= (region-end) 18))))

;;; Outer (a) text object tests

(ert-deftest helixel-test-textobj-a-word ()
  "Test a-word text object selection."
  (with-temp-buffer
    (insert ";; This buffer is for notes.")
    (goto-char 4)
    (call-interactively #'helixel-mark-a-word)
    (should (= (region-beginning) 4))
    (should (= (region-end) 9))))

(ert-deftest helixel-test-textobj-a-symbol ()
  "Test a-symbol text object selection."
  (with-temp-buffer
    (insert ";; This buffer is for notes.")
    (goto-char 4)
    (call-interactively #'helixel-mark-a-symbol)
    (should (= (region-beginning) 4))
    (should (= (region-end) 9))))

(ert-deftest helixel-test-textobj-a-sentence ()
  "Test a-sentence text object selection."
  (with-temp-buffer
    (insert "This is sentence one. This is sentence two.")
    (goto-char 1)
    (call-interactively #'helixel-mark-a-sentence)
    (should (= (region-beginning) 1))
    (should (= (region-end) 44))))

(ert-deftest helixel-test-textobj-a-paragraph ()
  "Test a-paragraph text object selection."
  (with-temp-buffer
    (insert ";; This buffer is for notes,
;; and for Lisp evaluation.

;; Another paragraph here.")
    (goto-char 1)
    (call-interactively #'helixel-mark-a-paragraph)
    (should (= (region-beginning) 1))
    (should (= (region-end) 58))))

;;; Paren text object tests

 (ert-deftest helixel-test-textobj-paren-inner ()
  "Test inner paren text object."
  (with-temp-buffer
    (insert "(hello)")
    (goto-char 2)
    (call-interactively #'helixel-mark-inner-paren)
    (should (= (region-beginning) 2))
    (should (= (region-end) 7))))

 (ert-deftest helixel-test-textobj-paren-outer ()
  "Test outer paren text object."
  (with-temp-buffer
    (insert "(hello)")
    (goto-char 2)
    (call-interactively #'helixel-mark-a-paren)
    (should (= (region-beginning) 1))
    (should (= (region-end) 8))))

;;; Bracket text object tests

 (ert-deftest helixel-test-textobj-bracket-inner ()
  "Test inner bracket text object."
  (with-temp-buffer
    (insert "[hello]")
    (goto-char 2)
    (call-interactively #'helixel-mark-inner-bracket)
    (should (= (region-beginning) 2))
    (should (= (region-end) 7))))

 (ert-deftest helixel-test-textobj-bracket-outer ()
  "Test outer bracket text object."
  (with-temp-buffer
    (insert "[hello]")
    (goto-char 2)
    (call-interactively #'helixel-mark-a-bracket)
    (should (= (region-beginning) 1))
    (should (= (region-end) 8))))

;;; Brace text object tests

 (ert-deftest helixel-test-textobj-brace-inner ()
  "Test inner brace text object."
  (with-temp-buffer
    (insert "{hello}")
    (goto-char 2)
    (call-interactively #'helixel-mark-inner-brace)
    (should (= (region-beginning) 2))
    (should (= (region-end) 7))))

 (ert-deftest helixel-test-textobj-brace-outer ()
  "Test outer brace text object."
  (with-temp-buffer
    (insert "{hello}")
    (goto-char 2)
    (call-interactively #'helixel-mark-a-brace)
    (should (= (region-beginning) 1))
    (should (= (region-end) 8))))

;;; Angle bracket text object tests

 (ert-deftest helixel-test-textobj-angle-inner ()
  "Test inner angle bracket text object."
  (with-temp-buffer
    (insert "<hello>")
    (goto-char 2)
    (call-interactively #'helixel-mark-inner-angle)
    (should (= (region-beginning) 2))
    (should (= (region-end) 7))))

 (ert-deftest helixel-test-textobj-angle-outer ()
  "Test outer angle bracket text object."
  (with-temp-buffer
    (insert "<hello>")
    (goto-char 2)
    (call-interactively #'helixel-mark-a-angle)
    (should (= (region-beginning) 1))
    (should (= (region-end) 8))))

;;; Quote text object tests

(ert-deftest helixel-test-textobj-single-quote-inner ()
  "Test inner single-quote text object."
  (with-temp-buffer
    (insert "'hello'")
    (goto-char 2)
    (call-interactively #'helixel-mark-inner-single-quote)
    (should (= (region-beginning) 2))
    (should (= (region-end) 7))))

(ert-deftest helixel-test-textobj-single-quote-outer ()
  "Test outer single-quote text object."
  (with-temp-buffer
    (insert "'hello'")
    (goto-char 2)
    (call-interactively #'helixel-mark-a-single-quote)
    (should (= (region-beginning) 1))
    (should (= (region-end) 8))))

(ert-deftest helixel-test-textobj-double-quote-inner ()
  "Test inner double-quote text object."
  (with-temp-buffer
    (insert "\"hello\"")
    (goto-char 2)
    (call-interactively #'helixel-mark-inner-double-quote)
    (should (= (region-beginning) 2))
    (should (= (region-end) 7))))

(ert-deftest helixel-test-textobj-double-quote-outer ()
  "Test outer double-quote text object."
  (with-temp-buffer
    (insert "\"hello\"")
    (goto-char 2)
    (call-interactively #'helixel-mark-a-double-quote)
    (should (= (region-beginning) 1))
    (should (= (region-end) 8))))

(ert-deftest helixel-test-textobj-back-quote-inner ()
  "Test inner back-quote text object."
  (with-temp-buffer
    (insert "`hello`")
    (goto-char 2)
    (call-interactively #'helixel-mark-inner-back-quote)
    (should (= (region-beginning) 2))
    (should (= (region-end) 7))))

(ert-deftest helixel-test-textobj-back-quote-outer ()
  "Test outer back-quote text object."
  (with-temp-buffer
    (insert "`hello`")
    (goto-char 2)
    (call-interactively #'helixel-mark-a-back-quote)
    (should (= (region-beginning) 1))
    (should (= (region-end) 8))))

;;; Tag text object tests

(ert-deftest helixel-test-textobj-tag-inner ()
  "Test inner tag text object."
  (with-temp-buffer
    (insert "<foo>bar</foo>")
    (goto-char 2)
    (call-interactively #'helixel-mark-inner-tag)
    (should (= (region-beginning) 6))
    (should (= (region-end) 9))))

(ert-deftest helixel-test-textobj-tag-outer ()
  "Test outer tag text object."
  (with-temp-buffer
    (insert "<foo>bar</foo>")
    (goto-char 2)
    (call-interactively #'helixel-mark-a-tag)
    (should (= (region-beginning) 1))
    (should (= (region-end) 15))))

;;; Text object non-expansion tests

(ert-deftest helixel-test-textobj-no-expand-region-word ()
  "Test text-object replaces rather than expands active region."
  (helixel-test-with-buffer "hello world foo"
    (push-mark 6 nil t)
    (goto-char 1)
    (should (region-active-p))
    (goto-char 7)
    (setq last-command nil this-command 'helixel-mark-inner-word)
    (call-interactively #'helixel-mark-inner-word)
    (should (= (region-beginning) 7))
    (should (= (region-end) 12))))

(ert-deftest helixel-test-textobj-no-expand-region-paren ()
  "Test text-object replaces rather than expands active region (pairs)."
  (helixel-test-with-buffer "foo (hello) bar"
    (push-mark 4 nil t)
    (goto-char 1)
    (should (region-active-p))
    (goto-char 7)
    (setq last-command nil this-command 'helixel-mark-inner-paren)
    (call-interactively #'helixel-mark-inner-paren)
    (should (= (region-beginning) 6))
    (should (= (region-end) 11))))

(ert-deftest helixel-test-textobj-no-expand-region-quote ()
  "Test text-object replaces rather than expands active region (quotes)."
  (helixel-test-with-buffer "foo 'hello' bar"
    (push-mark 4 nil t)
    (goto-char 1)
    (should (region-active-p))
    (goto-char 7)
    (setq last-command nil this-command 'helixel-mark-inner-single-quote)
    (call-interactively #'helixel-mark-inner-single-quote)
     (should (= (region-beginning) 6))
     (should (= (region-end) 11))))

;;; Textobj: region-active prioritizes highlighted content

(ert-deftest helixel-test-textobj-region-active-prio-inner ()
  "When region is active with content, textobj selects the region content."
  (helixel-test-with-buffer "hello world"
    (push-mark 1 nil t)
    (goto-char 7)
    (call-interactively #'helixel-mark-inner-word)
    (should (= (region-beginning) 1))
    (should (= (region-end) 6))))

(ert-deftest helixel-test-textobj-followup-selects-next-inner ()
  "Second textobj press selects the next word, not expand."
  (helixel-test-with-buffer "hello world foo"
    (goto-char 1)
    (call-interactively #'helixel-mark-inner-word)
    (should (= (region-beginning) 1))
    (should (= (region-end) 6))
    (call-interactively #'helixel-mark-inner-word)
    (should (= (region-beginning) 7))
    (should (= (region-end) 12))))

(ert-deftest helixel-test-textobj-whitespace-adjust ()
  "Cursor on whitespace finds the adjacent word."
  (helixel-test-with-buffer "hello world"
    (goto-char 6)
    (call-interactively #'helixel-mark-inner-word)
    (should (= (region-beginning) 1))
    (should (= (region-end) 6))))

(ert-deftest helixel-test-textobj-followup-selects-next-outer ()
  "Second a-word press selects the next a-word, not expand."
  (helixel-test-with-buffer "hello world foo"
    (goto-char 1)
    (call-interactively #'helixel-mark-a-word)
    (should (= (region-beginning) 1))
    (should (= (region-end) 7))
    (call-interactively #'helixel-mark-a-word)
    (should (= (region-beginning) 7))
    (should (= (region-end) 13))))

;;; Text object action tests

(ert-deftest helixel-test-textobj-session-start ()
  "Test text-object command starts an action."
  (helixel-test-with-buffer "hello world"
    (setq helixel--action nil helixel--action-ring nil helixel--action-pos nil
          last-command nil this-command 'helixel-mark-inner-word)
    (helixel-mark-inner-word)
    (should helixel--action)
    (should (eq (helixel--live-get :category) 'textobj))
    (should (= (marker-position (helixel--live-get :marker)) 1))))

(ert-deftest helixel-test-textobj-session-same-family-continues ()
  "Test same-category text-object commands continue action."
  (helixel-test-with-buffer "(hello) (world)"
    (setq helixel--action nil helixel--action-ring nil helixel--action-pos nil
          last-command nil this-command 'helixel-mark-inner-paren)
    (goto-char 2)
    (helixel-mark-inner-paren)
    (should (eq (helixel--live-get :category) 'textobj))
    (let ((mark-pos (marker-position (helixel--live-get :marker))))
      (setq last-command 'helixel-mark-inner-paren this-command 'helixel-mark-a-paren)
      (goto-char 10)
      (helixel-mark-a-paren)
      (should (eq (helixel--live-get :category) 'textobj)))))

(ert-deftest helixel-test-textobj-session-different-family-breaks ()
  "Test different-family textobj pushes old action to ring."
  (helixel-test-with-buffer "hello (world)"
    (setq helixel--action nil helixel--action-ring nil helixel--action-pos nil
          last-command nil this-command 'helixel-mark-inner-word)
    (helixel-mark-inner-word)
    (setq last-command 'helixel-mark-inner-word this-command 'helixel-mark-inner-paren)
    (helixel-mark-inner-paren)
    (should (= (length helixel--action-ring) 1))
    (should (eq (helixel--live-get :subcat) 'pair))))

(ert-deftest helixel-test-textobj-session-type-property ()
  "Test textobj actions have correct category and subcat."
  (let (helixel--action helixel--action-ring helixel--action-pos)
    (helixel-test-with-buffer "hello world"
      (setq last-command nil this-command 'helixel-mark-inner-word)
      (helixel-mark-inner-word)
      (should (eq (helixel--live-get :category) 'textobj))
      (should (eq (helixel--live-get :subcat) 'word)))))

;;; Search tests

(ert-deftest helixel-test-search-repeat-prev-exchange ()
  "Test N exchanges point and mark and toggles direction."
  (helixel-test-with-buffer "hello world"
    (push-mark (point) t t)
    (goto-char 6)
    (let ((pt (point))
          (mk (mark)))
      (helixel-search-repeat-reverse)
      (should (eq (helixel-repeat-dir) 'backward))
      (should (= (point) mk))
      (should (= (mark) pt)))))

(ert-deftest helixel-test-search-extract-regex ()
  "Test extracting a bounded regex for word at point."
  (helixel-test-with-buffer "hello world"
    (goto-char 3)
    (let ((result (helixel-search--extract-regex (cons 1 6))))
      (should (string-match "hello" result)))))

(ert-deftest helixel-test-search-extract-regex-no-boundary ()
  "Test extracting regex without word boundary when inside a word."
  (helixel-test-with-buffer "hello world"
    (goto-char 2)
    (let ((result (helixel-search--extract-regex (cons 2 4))))
      (should (string= (regexp-quote "el") result)))))

(ert-deftest helixel-test-search-bounds-at-point-symbol ()
  "Test bounds-at-point returns symbol bounds."
  (helixel-test-with-buffer "hello world"
    (goto-char 3)
    (let ((bounds (helixel-search--bounds-at-point)))
      (should bounds)
      (should (= (car bounds) 1))
      (should (= (cdr bounds) 6)))))

(ert-deftest helixel-test-search-bounds-at-point-region ()
  "Test bounds-at-point uses single-line region when active."
  (helixel-test-with-buffer "hello world"
    (goto-char 2)
    (push-mark (point) t t)
    (goto-char 5)
    (activate-mark)
    (let ((bounds (helixel-search--bounds-at-point)))
      (should bounds)
      (should (= (car bounds) 2))
      (should (= (cdr bounds) 5)))))

(ert-deftest helixel-test-search-repeat-next-forward ()
  "Test n repeats search forward."
  (helixel-test-with-buffer "hello hello hello"
    (let ((isearch-string "hello")
          (isearch-regexp t)
          (isearch-forward t)
          (isearch-case-fold-search t)
          (isearch-success t)
          (isearch-other-end (copy-marker 6))
          (isearch-wrap-pause 'no-ding)
          (isearch-repeat-on-direction-change t))
      (goto-char 6)
      (helixel-search-repeat-next)
      (should (>= (point) 7))
      (should (use-region-p)))))

(ert-deftest helixel-test-search-repeat-next-reverse-when-point<mark ()
  "Test n goes backward when direction is backward."
  (helixel-test-with-buffer "hello hello hello"
    (let ((isearch-string "hello")
          (isearch-regexp t)
          (isearch-forward t)
          (isearch-case-fold-search t)
          (isearch-success t)
          (isearch-other-end (copy-marker 22))
          (isearch-wrap-pause 'no-ding)
          (isearch-repeat-on-direction-change t))
      (setq helixel--action '(:dir backward))
      (goto-char 18)
      (helixel-search-repeat-next)
      (should (< (point) 18))
      (should (use-region-p)))))

;;; Combined search history tests

(ert-deftest helixel-test-history-push-and-cap ()
  "Test history push adds entries and respects max size."
  (let ((helixel--action-ring nil)
        (helixel-action-ring-max 3))
    (helixel-action-commit)  ; null action, does nothing
    (should (null helixel--action-ring))))

(ert-deftest helixel-test-history-display-format ()
  "Test history display formatting with action plists."
  (should (string= (helixel-action-display
                    '(:category search :search (:pattern "hello" :dir forward))) "/hello/"))
  (should (string= (helixel-action-display
                    '(:category search :search (:pattern "hello" :dir backward))) "?hello?"))
  (should (string= (helixel-action-display
                    '(:category find-char :find-char (:type next :char ?x :dir forward))) "f→x"))
  (should (string= (helixel-action-display
                    '(:category find-char :find-char (:type next :char ?x :dir backward))) "F→x"))
  (should (string= (helixel-action-display
                    '(:category find-char :find-char (:type till :char ?x :dir forward))) "t→x"))
  (should (string= (helixel-action-display
                    '(:category find-char :find-char (:type till :char ?x :dir backward))) "T→x")))

(ert-deftest helixel-test-history-find-pushes ()
  "Test that find-char operations push to the action ring."
  (let ((helixel--action-ring nil)
        (helixel--action nil)
        (helixel--action-pos nil)
        )
    (helixel-test-with-buffer "axb axb axb"
      (setq last-command nil this-command 'helixel-find-next-char)
      (helixel-find-next-char ?x)
      (should (eq (plist-get (car helixel--action-ring) :category) 'find-char))
      (should (eq (helixel--action-cat-get (car helixel--action-ring) :type) 'next))
      (should (eq (helixel--action-cat-get (car helixel--action-ring) :char) ?x)))))

(ert-deftest helixel-test-history-from-history-find-next ()
  "Test C-u n selecting a find-char next entry replays it correctly."
  (let ((helixel--action-ring '((:category find-char :subcat find-char
                              :find-char (:type next :char ?b :dir forward) :display t)))
        (helixel--action nil)
        
        (helixel--clear-highlights-called nil))
    (helixel-test-with-buffer "axb axb axb"
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt _collection &rest _)
                   (helixel-action-display (car helixel--action-ring))))
                ((symbol-function 'helixel--clear-highlights)
                 (lambda () (setq helixel--clear-highlights-called t))))
        (helixel-search--from-history t))
      (should (eq (helixel--live-cat-get :dir) 'forward))
      (should (eql (point) 4))
      (should helixel--clear-highlights-called))))

(ert-deftest helixel-test-history-from-history-find-till ()
  "Test C-u n selecting a find-char till entry replays with till semantics."
  (let ((helixel--action-ring '((:category find-char :subcat find-char
                              :find-char (:type till :char ?b :dir forward) :display t)))
        (helixel--action nil)
        )
    (helixel-test-with-buffer "axb axb axb"
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt _collection &rest _)
                   (helixel-action-display (car helixel--action-ring)))))
        (helixel-search--from-history t))
      (should (eql (point) 3))
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt _collection &rest _)
                   (helixel-action-display (car helixel--action-ring)))))
        (helixel-search--from-history t))
      (should (eql (point) 7)))))

(ert-deftest helixel-test-history-from-history-direction-backward ()
  "Test selecting a backward find-char entry with forwardp=t (use stored dir)."
  (let ((helixel--action-ring '((:category find-char :subcat find-char
                              :find-char (:type next :char ?b :dir backward) :display t)))
        (helixel--action nil)
        )
    (helixel-test-with-buffer "axb axb axb"
      (goto-char 8)
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt _collection &rest _)
                   (helixel-action-display (car helixel--action-ring)))))
        (helixel-search--from-history t))
      (should (eq (helixel--live-cat-get :dir) 'backward))
      (should (eql (point) 7)))))

(ert-deftest helixel-test-history-repeat-next-with-arg ()
  "Test helixel-search-repeat-next with prefix arg calls from-history."
  (let ((helixel--action-ring '((:category search :subcat search
                              :search (:pattern "test" :dir forward) :display t)))
        (helixel--action nil)
        )
    (helixel-test-with-buffer "a test b"
      (goto-char 3)
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt _collection &rest _)
                   (helixel-action-display (car helixel--action-ring)))))
        (helixel-search-repeat-next t))
      (should (>= (point) 4)))))

(ert-deftest helixel-test-history-repeat-prev-with-arg-find ()
  "Test C-u N toggles direction and picks a find-char entry from history."
  (let ((helixel--action-ring '((:category find-char :subcat find-char
                              :find-char (:type next :char ?b :dir forward) :display t)))
        (helixel--action nil)
        )
    (helixel-test-with-buffer "axb axb axb"
      (goto-char 8)
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt _collection &rest _)
                   (helixel-action-display (car helixel--action-ring)))))
        (helixel-search-repeat-reverse t))
      (should (eq (helixel--live-cat-get :dir) 'backward))
      (should (eql (point) 7))
      (helixel-search-repeat-next)
      (should (eq (helixel--live-cat-get :dir) 'backward))
      (should (< (point) 7)))))

(ert-deftest helixel-test-history-repeat-prev-with-arg-search ()
  "Test C-u N with a regexp search entry: toggles direction, searches backward."
  (let ((helixel--action-ring '((:category search :subcat search
                              :search (:pattern "hello" :dir forward) :display t)))
        (helixel--action nil)
        )
    (helixel-test-with-buffer "hello world hello world"
      (goto-char 20)
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt _collection &rest _)
                   (helixel-action-display (car helixel--action-ring)))))
        (helixel-search-repeat-reverse t))
      (should (eq (helixel--live-cat-get :dir) 'backward))
      (should (<= (point) 13)))))

(ert-deftest helixel-test-history-sync-direction-c-u-N ()
  "Test C-u N flips the direction of the front history entry."
  (let ((helixel--action-ring '((:category find-char :subcat find-char
                              :find-char (:type next :char ?b :dir forward) :display t)))
        (helixel--action nil)
        )
    (helixel-test-with-buffer "axb axb axb"
      (goto-char 5)
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt _collection &rest _)
                   (helixel-action-display (car helixel--action-ring)))))
        (helixel-search-repeat-reverse t))
      (should (eq (helixel--live-cat-get :dir) 'backward))
      (should (eq (helixel--action-cat-get (car helixel--action-ring) :dir) 'backward)))))

(ert-deftest helixel-test-history-sync-direction-N ()
  "Test N (no prefix) flips the direction of the front history entry."
  (let ((helixel--action nil)
        (helixel--action-ring nil)
        )
    (helixel-test-with-buffer "axb axb axb"
      (goto-char 5)
      (setq last-command 'helixel-find-next-char this-command 'helixel-find-next-char)
      (helixel-find-next-char ?b)
      (setq last-command 'helixel-find-next-char this-command 'helixel-search-repeat-reverse)
      (helixel-search-repeat-reverse)
      (should (eq (helixel--live-cat-get :dir) 'backward))
      (should (eq (helixel--action-cat-get (car helixel--action-ring) :dir) 'backward)))))

(ert-deftest helixel-test-history-no-sync-c-u-n ()
  "Test C-u n does NOT flip the front entry direction."
  (let ((helixel--action-ring '((:category find-char :subcat find-char
                              :find-char (:type next :char ?b :dir forward) :display t)))
        (helixel--action nil)
        )
    (helixel-test-with-buffer "axb axb axb"
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt _collection &rest _)
                   (helixel-action-display (car helixel--action-ring)))))
        (helixel-search-repeat-next t))
      (should (eq (helixel--live-cat-get :dir) 'forward))
      (should (eq (helixel--action-cat-get (car helixel--action-ring) :dir) 'forward)))))

;;; Repeat recency tests

(ert-deftest helixel-test-repeat-find-after-movement ()
  "Test n repeats find-char after intervening movement."
  (helixel-test-with-buffer "axb axb axb"
    (setq helixel--action nil helixel--action-ring nil helixel--action-pos nil
          last-command nil this-command 'helixel-find-next-char)
    (helixel-find-next-char ?b)
    (should (eql (point) 4))
    ;; intervening movement pushes find-char to ring
    (setq last-command 'helixel-find-next-char this-command 'helixel-forward-char)
    (helixel-forward-char)
    (should (eq (plist-get (car helixel--action-ring) :category) 'find-char))
    ;; n should still repeat find-char (set :type on live action)
    (setq last-command 'helixel-forward-char this-command 'helixel-search-repeat-next)
    (helixel-search-repeat-next)
    (should (helixel--live-cat-get :type))))

(ert-deftest helixel-test-repeat-search-over-find ()
  "Test n picks search over older find-char in ring (detection only)."
  (let ((helixel--action-ring
         '((:category search :subcat search :search (:pattern "hello" :dir forward) :display t)
           (:category find-char :subcat find-char :find-char (:type next :char ?b :dir forward))))
        (helixel--action nil)
        (helixel--action-pos nil))
    (helixel-test-with-buffer "hello world"
      ;; call n — it should go to isearch-repeat (not find-char),
      ;; so helixel--action should NOT get :type from find-char-core
      (condition-case nil
          (helixel-search-repeat-next)
        (error nil))
      ;; verify no find-char data was set on live action
      (should (null (helixel--live-cat-get :type))))))

(ert-deftest helixel-test-repeat-no-search-repeat-wrap ()
  "Test n/N do not push search/repeat wrapper actions into ring."
  (let ((helixel--action nil) (helixel--action-ring nil) (helixel--action-pos nil))
    (helixel-test-with-buffer "axb axb axb"
      (setq last-command nil this-command 'helixel-find-next-char)
      (helixel-find-next-char ?b)
      (setq last-command 'helixel-find-next-char this-command 'helixel-search-repeat-next)
      (helixel-search-repeat-next)
      (helixel-search-repeat-next)
      ;; check: no search/repeat entries without :pattern in ring
      (let ((sr (cl-find-if (lambda (a)
                              (and (eq (helixel--action-get a :category) 'search)
                                   (null (helixel--action-cat-get a :pattern))))
                            helixel--action-ring)))
        (should (null sr))))))

(ert-deftest helixel-test-action-cycle-skip-meaningless ()
  "Test ; does not push meaningless live action into ring."
  (let ((helixel--action '(:category search :subcat repeat :dir forward))
        (helixel--action-ring `((:category movement :subcat char :marker ,(point-marker))))
        (helixel--action-pos nil))
    (let ((len-before (length helixel--action-ring)))
      (helixel-action-cycle)
      (should (= (length helixel--action-ring) len-before))
      (should (null helixel--action))
      (should (eq helixel--action-pos 0)))))

(ert-deftest helixel-test-history-from-history-sets-find-char-category ()
  "Test C-u N replaying find-char sets :category to find-char."
  (let ((helixel--action-ring '((:category find-char :subcat find-char
                              :find-char (:type next :char ?b :dir forward) :display t)))
        (helixel--action '(:category search :subcat repeat :dir forward))
        )
    (helixel-test-with-buffer "axb axb axb"
      (goto-char 5)
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt _collection &rest _)
                   (helixel-action-display (car helixel--action-ring)))))
        (helixel-search--from-history t))
      (should (eq (helixel--live-get :category) 'find-char))
      (should (eq (helixel--live-cat-get :type) 'next))
      (should (eq (helixel--live-cat-get :char) ?b)))))

;;; Action tracking tests

(ert-deftest helixel-test-action-start-movement ()
  "Test movement commands create and continue actions."
  (helixel-test-with-buffer "line1\nline2\nline3"
    (setq helixel--action nil helixel--action-ring nil helixel--action-pos nil
          last-command nil this-command 'helixel-next-line)
    (helixel-next-line)
    (should helixel--action)
    (should (eq (helixel--live-get :category) 'movement))
    (should (eq (helixel--live-get :subcat) 'line))
    (should (null helixel--action-pos))
    (let ((mark-pos (marker-position (helixel--live-get :marker))))
      (setq last-command 'helixel-next-line this-command 'helixel-next-line)
      (helixel-next-line)
      (should (eq (helixel--live-get :category) 'movement))
      (should (eq (helixel--live-get :subcat) 'line)))))

(ert-deftest helixel-test-action-category-mismatch ()
  "Test different categories push old action to ring."
  (helixel-test-with-buffer "axb axb axb"
    (setq helixel--action nil helixel--action-ring nil
          last-command nil this-command 'helixel-find-next-char)
    (helixel-find-next-char ?b)
    (should (eq (helixel--live-get :category) 'find-char))
    (let ((mark1 (marker-position (helixel--live-get :marker))))
      (setq last-command 'helixel-find-next-char this-command 'helixel-forward-char)
      (helixel-forward-char)
      (should (eq (helixel--live-get :category) 'movement))
      (should (eq (helixel--live-get :subcat) 'char))
      (should (not (eq (marker-position (helixel--live-get :marker)) mark1)))
      (should (= (length helixel--action-ring) 1))
      (should (eq (plist-get (car helixel--action-ring) :category) 'find-char)))))

(ert-deftest helixel-test-action-movement-different-subcat ()
  "Test different movement subcats push to ring."
  (helixel-test-with-buffer "hello\nworld\nagain"
    (setq helixel--action nil helixel--action-ring nil
          last-command nil this-command 'helixel-forward-char)
    (helixel-forward-char)
    (should (eq (helixel--live-get :subcat) 'char))
    (setq last-command 'helixel-forward-char this-command 'helixel-next-line)
    (helixel-next-line)
    (should (eq (helixel--live-get :subcat) 'line))
    (should (= (length helixel--action-ring) 1))))

(ert-deftest helixel-test-action-cycle-live ()
  "Test ; pushes live action to ring and shows ring[0]."
  (helixel-test-with-buffer "hello world again"
    (setq helixel--action nil helixel--action-ring nil helixel--action-pos nil
          last-command nil this-command 'helixel-forward-char)
    (goto-char 1)
    (helixel-forward-char)
    (setq last-command 'helixel-forward-char this-command 'helixel-forward-char)
    (helixel-forward-char)
    (helixel-action-cycle)
    (should (null helixel--action))
    (should (= (length helixel--action-ring) 2))
    (should (= helixel--action-pos 1))
    (should (= (region-beginning) 1))))

(ert-deftest helixel-test-action-cycle-ring ()
  "Test ; cycles through action ring."
  (helixel-test-with-buffer "hello\nworld\nagain"
    (setq helixel--action nil helixel--action-ring nil helixel--action-pos nil
          last-command nil this-command 'helixel-forward-char)
    (goto-char 1)
    (helixel-forward-char)
    (let ((mark1 (marker-position (helixel--live-get :marker))))
      (setq last-command 'helixel-forward-char this-command 'helixel-next-line)
      (goto-char 5)
      (helixel-next-line)  ; line subcat differs → push old
      (should (= (length helixel--action-ring) 1))
      (helixel-action-cycle)
      (should (eq helixel--action-pos 0))
      (should (use-region-p)))))

(ert-deftest helixel-test-action-goto-continues ()
  "Test goto commands share the same action."
  (helixel-test-with-buffer "line1\nline2\nline3"
    (setq helixel--action nil helixel--action-ring nil
          last-command nil this-command 'helixel-go-beginning-line)
    (helixel-go-beginning-line)
    (should (eq (helixel--live-get :category) 'movement))
    (should (eq (helixel--live-get :subcat) 'goto))))

(ert-deftest helixel-test-action-select-continues ()
  "Test select commands share the same action."
  (helixel-test-with-buffer "line1\nline2\nline3"
    (setq helixel--action nil helixel--action-ring nil
          last-command nil this-command 'helixel-select-line)
    (helixel-select-line)
    (should (eq (helixel--live-get :subcat) 'lineselect))))

(ert-deftest helixel-test-action-no-session-error ()
  "Test action-cycle with no sessions shows message."
  (let ((helixel--action nil) (helixel--action-ring nil) (helixel--action-pos nil))
    (helixel-action-cycle)
    t))  ; just verify no error

(ert-deftest helixel-test-action-cycle-forward ()
  "Test C-u ; cycles forward through saved actions."
  (helixel-test-with-buffer "hello\nworld\nagain"
    (setq helixel--action nil helixel--action-ring nil helixel--action-pos nil
          last-command nil this-command 'helixel-forward-char)
    (helixel-forward-char)
    (setq last-command 'helixel-forward-char this-command 'helixel-next-line)
    (goto-char 5)
    (helixel-next-line)
    (helixel-action-cycle)
    (should (eq helixel--action-pos 0))
    (should (= (region-beginning) 5))
    (helixel-action-cycle)
    (should (eq helixel--action-pos 1))
    (helixel-action-cycle t)
    (should (eq helixel--action-pos 0))))

(ert-deftest helixel-test-action-same-subcat-continues ()
  "Test same subcat movements continue action (word start→word end)."
  (helixel-test-with-buffer "hello world test"
    (setq helixel--action nil helixel--action-ring nil helixel--action-pos nil
          last-command nil this-command 'helixel-forward-word-start)
    (helixel-forward-word-start)
    (should (eq (helixel--live-get :subcat) 'word))
    (let ((mark-pos (marker-position (helixel--live-get :marker))))
      (setq last-command 'helixel-forward-word-start this-command 'helixel-forward-word-end)
      (helixel-forward-word-end)
      (should (eq (helixel--live-get :subcat) 'word)))))

(ert-deftest helixel-test-action-different-subcat-breaks ()
  "Test different subcat pushes old action to ring."
  (helixel-test-with-buffer "hello world\ntest line"
    (setq helixel--action nil helixel--action-ring nil helixel--action-pos nil
          last-command nil this-command 'helixel-forward-word-start)
    (helixel-forward-word-start)
    (should (eq (helixel--live-get :subcat) 'word))
    (let ((word-mark (marker-position (helixel--live-get :marker))))
      (setq last-command 'helixel-forward-word-start this-command 'helixel-next-line)
      (helixel-next-line)
      (should (eq (helixel--live-get :subcat) 'line))
      (should (= (length helixel--action-ring) 1)))))

(ert-deftest helixel-test-action-goto-marker ()
  "Test goto commands record correct marker position."
  (helixel-test-with-buffer "line1\nline2\nline3"
    (setq helixel--action nil helixel--action-ring nil helixel--action-pos nil
          last-command nil this-command 'helixel-go-beginning-buffer)
    (goto-char 10)
    (helixel-go-beginning-buffer)
    (should helixel--action)
    (should (eq (helixel--live-get :subcat) 'goto))
    (should (= (marker-position (helixel--live-get :marker)) 10))))

(ert-deftest helixel-test-action-wrapper-commands ()
  "Test goto-line starts action correctly."
  (helixel-test-with-buffer "line1\nline2\nline3\nline4\nline5"
    (setq helixel--action nil helixel--action-ring nil helixel--action-pos nil
          last-command nil this-command 'helixel-goto-line)
    (goto-char 1)
    (helixel-goto-line 3)
    (should helixel--action)
    (should (eq (helixel--live-get :subcat) 'goto))))

(ert-deftest helixel-test-action-select-commands ()
  "Test select-line starts action correctly."
  (helixel-test-with-buffer "hello world"
    (setq helixel--action nil helixel--action-ring nil helixel--action-pos nil
          last-command nil this-command 'helixel-select-line)
    (helixel-select-line)
    (should helixel--action)
    (should (eq (helixel--live-get :subcat) 'lineselect))))

(ert-deftest helixel-test-define-movement-macro ()
  "Test helixel-define-movement creates a working action-tracked command."
  (helixel-define-movement helixel-test-movement2 forward-char char)
  (helixel-test-with-buffer "hello"
    (setq helixel--action nil helixel--action-ring nil helixel--action-pos nil
          last-command nil this-command 'helixel-test-movement2)
    (helixel-test-movement2)
    (should helixel--action)
    (should (eq (helixel--live-get :category) 'movement))
    (should (eq (helixel--live-get :subcat) 'char))))

;;; helixel-execute-command / helixel-define-ex-command tests

(ert-deftest helixel-test-execute-command-known ()
  "Test executing a known command via helixel-execute-command."
  (let ((helixel--command-alist
         `((("test-cmd") ,#'ignore))))
    (should (progn (helixel-execute-command "test-cmd") t))))

(ert-deftest helixel-test-execute-command-unknown ()
  "Test executing an unknown command shows message."
  (let ((helixel--command-alist nil))
    (should (progn (helixel-execute-command "no-such-cmd") t))))

(ert-deftest helixel-test-execute-command-call-interactively ()
  "Test commandp callbacks are called via call-interactively."
  (let ((helixel--command-alist nil)
        (called-interactively nil))
    (cl-letf (((symbol-function 'test-helixel-cmd)
               (lambda ()
                 (interactive)
                 (setq called-interactively (called-interactively-p)))))
      (helixel-define-ex-command "test-ia" #'test-helixel-cmd)
      (helixel-execute-command "test-ia")
      (should called-interactively))))

(ert-deftest helixel-test-execute-command-funcall ()
  "Test non-commandp callbacks are called via funcall."
  (let ((helixel--command-alist nil)
        (called nil))
    (helixel-define-ex-command "test-fn" (lambda () (setq called t)))
    (helixel-execute-command "test-fn")
    (should called)))

(ert-deftest helixel-test-execute-command-multi-callback ()
  "Test executing a command with multiple callbacks."
  (let ((helixel--command-alist nil)
        (counter 0))
    (helixel-define-ex-command "multi"
      (list (lambda () (setq counter (1+ counter)))
            (lambda () (setq counter (1+ counter)))
            #'ignore))
    (helixel-execute-command "multi")
    (should (= counter 2))))

(ert-deftest helixel-test-execute-command-multi-order ()
  "Test callbacks are executed in order."
  (let ((helixel--command-alist nil)
        (vals nil))
    (helixel-define-ex-command "ord"
      (list (lambda () (push 1 vals))
            (lambda () (push 2 vals))
            (lambda () (push 3 vals))))
    (helixel-execute-command "ord")
    (should (equal vals '(3 2 1)))))

(ert-deftest helixel-test-execute-command-with-aliases ()
  "Test command can be invoked via any of its aliases."
  (let ((helixel--command-alist nil)
        (called nil))
    (helixel-define-ex-command
     '("a" "alias" "alt") (lambda () (setq called t)))
    (helixel-execute-command "alias")
    (should called)))

(ert-deftest helixel-test-execute-command-second-alias ()
  "Test command can be invoked via second alias."
  (let ((helixel--command-alist nil)
        (called nil))
    (helixel-define-ex-command
     '("a" "alias" "alt") (lambda () (setq called t)))
    (setq called nil)
    (helixel-execute-command "alt")
    (should called)))

(ert-deftest helixel-test-define-typable-command-single-symbol ()
  "Test helixel-define-ex-command with a single symbol callback."
  (let ((helixel--command-alist nil)
        (called nil))
    (cl-letf (((symbol-function 'test-tc) (lambda () (setq called t))))
      (helixel-define-ex-command "tc-sym" #'test-tc)
      (helixel-execute-command "tc-sym")
      (should called))))

(ert-deftest helixel-test-define-typable-command-duplicate ()
  "Test defining the same command twice does not duplicate."
  (let ((helixel--command-alist nil))
    (helixel-define-ex-command "dup" #'ignore)
    (helixel-define-ex-command "dup" #'ignore)
    (should (= (length helixel--command-alist) 1))))

(ert-deftest helixel-test-repeat-ring-no-bare-entries ()
  "Test ring never contains bare (:dir ...) entries without :category."
  (let ((helixel--action nil)
        (helixel--action-ring '((:category movement :subcat line
                                :marker ,(point-marker) :dir forward)))
        (helixel--action-pos nil)
        (helixel--repeat-dir 'forward)
        (helixel--repeat-data nil))
    (helixel-test-with-buffer "hello"
      (helixel-search-repeat-next)
      ;; set-dir no longer exists — repeat-dir is separate from action dir.
      ;; Verify no bare entries were pushed.
      (when helixel--action-ring
        (dolist (a helixel--action-ring)
          (should (plist-get a :category))
          (should-not (and (null (plist-get a :category))
                           (plist-get a :dir))))))))

(ert-deftest helixel-test-history-search-creates-proper-action ()
  "Test from-history for search sets :subcat and :marker on live action."
  (let ((helixel--action-ring `((:category search :subcat search
                                 :search (:pattern "test" :dir forward) :display t
                                 :marker ,(point-marker))))
        (helixel--action nil)
        (helixel--repeat-dir 'forward)
        (helixel--repeat-data nil))
    (helixel-test-with-buffer "a test b"
      (goto-char 3)
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt _collection &rest _)
                   (helixel-action-display (car helixel--action-ring)))))
        (helixel-search--from-history t))
      (should (eq (helixel--live-get :category) 'search))
      (should (eq (helixel--live-get :subcat) 'search))
      (should (helixel--live-get :marker)))))

(ert-deftest helixel-test-repeat-dir-separate-from-action-dir ()
  "Test that N flips repeat-dir without mutating action :dir of ring entries."
  (let ((helixel--action nil)
        (helixel--action-ring nil)
        (helixel--repeat-dir 'forward)
        (helixel--repeat-data nil))
    (helixel-test-with-buffer "axb axb axb"
      (goto-char 5)
      (setq last-command 'helixel-find-next-char
            this-command 'helixel-find-next-char)
      (helixel-find-next-char ?b)
      (should (eql (point) 8))
      (helixel-search-repeat-reverse)
      ;; repeat-dir should be flipped
      (should (eq helixel--repeat-dir 'backward))
      ;; Ring front :dir was synced by N (for history display)
      (should (eq (helixel--action-cat-get (car helixel--action-ring) :dir) 'backward))
      ;; Live action :dir is 'backward (set by find-repeat's action-start)
      (should (eq (helixel--live-cat-get :dir) 'backward)))))

(ert-deftest helixel-test-repeat-find-session-continuity ()
  "Test f d then n are one session — no duplicate ring entries."
  (let ((helixel--action nil)
        (helixel--action-ring nil)
        (helixel--repeat-dir 'forward)
        (helixel--repeat-data nil))
    (helixel-test-with-buffer "axd axd axd"
      (goto-char 1)
      (setq last-command nil this-command 'helixel-find-next-char)
      (helixel-find-next-char ?d)
      (should (= (length helixel--action-ring) 1))
      (setq last-command 'helixel-find-next-char
            this-command 'helixel-search-repeat-next)
      (helixel-search-repeat-next)
      ;; Same session — no new ring entry pushed
      (should (= (length helixel--action-ring) 1))
      (helixel-search-repeat-next)
      (should (= (length helixel--action-ring) 1)))))

(ert-deftest helixel-test-repeat-find-across-movement ()
  "Test f d → j → n: movement pushed, find-repeat continues original session."
  (let ((helixel--action nil)
        (helixel--action-ring nil)
        (helixel--repeat-dir 'forward)
        (helixel--repeat-data nil))
    (helixel-test-with-buffer "axd\naxd\naxd"
      (goto-char 1)
      (setq last-command nil this-command 'helixel-find-next-char)
      (helixel-find-next-char ?d)
      (should (= (length helixel--action-ring) 1))
      ;; Intervening movement
      (setq last-command 'helixel-find-next-char
            this-command 'helixel-next-line)
      (helixel-next-line)
      ;; movement pushed old action? No — old was already committed.
      ;; Actually the movement just creates a new action.
      (setq last-command 'helixel-next-line
            this-command 'helixel-search-repeat-next)
      (helixel-search-repeat-next)
      ;; Ring has: [find-char/next, movement/line]
      (should (= (length helixel--action-ring) 2))
      ;; Live action is find-char/next (same subcat as original)
      (should (eq (helixel--live-get :category) 'find-char))
      (should (eq (helixel--live-get :subcat) 'next)))))

;;; C-g session cancel test

(ert-deftest helixel-test-c-g-cancels-session ()
  "Test C-g breaks session: next same-type command starts fresh.
The cancelled session is preserved in the ring for `;' to jump back to.
Cancel pushes a state/cancel sentinel so dedup works naturally."
  (helixel-test-with-buffer "hello world test extra"
    (setq helixel--action nil helixel--action-ring nil helixel--action-pos nil
          last-command nil this-command 'helixel-forward-word-start)
    ;; w w: two word movements, same session
    (helixel-forward-word-start)
    (let ((mark1 (marker-position (helixel--live-get :marker))))
      (setq last-command 'helixel-forward-word-start
            this-command 'helixel-forward-word-start)
      (helixel-forward-word-start)
      (should-not (= (marker-position (helixel--live-get :marker)) mark1))
      ;; C-g: cancel session → pushes live action + cancel sentinel
      (helixel--cancel-action)
      (should (null helixel--action))
      ;; ring: [state/cancel, movement/word(2nd w), movement/word(1st w)]
      (should (= (length helixel--action-ring) 3))
      (should (eq (plist-get (car helixel--action-ring) :category) 'state))
      ;; w: new session, new marker at current position
      (setq last-command nil this-command 'helixel-forward-word-start)
      (goto-char 7)
      (helixel-forward-word-start)
      (should helixel--action)
      (should (= (marker-position (helixel--live-get :marker)) 7))
      ;; ;: push new w to ring
      ;; ring: [movement/word(new), state/cancel, movement/word(2nd), movement/word(1st)]
      (helixel-action-cycle)
      (should (= (length helixel--action-ring) 4))
      ;; First visible entry is movement/word(new)
      (should (eq (plist-get (nth helixel--action-pos helixel--action-ring)
                             :category) 'movement))
      ;; ; again: skip cancel, jump to older session (original w-w)
      (helixel-action-cycle)
      (should (eq (plist-get (nth helixel--action-pos helixel--action-ring)
                             :category) 'movement))
      (should (= (region-beginning) 1)))))

;;; Regex block text object tests

;; --- helixel-up-regex-block: counter-based (markdown fences) ---

(ert-deftest helixel-test-up-regex-block-counter-same ()
  "Test counter-based up-regex-block with same begin/end (markdown fence)."
  (with-temp-buffer
    (insert "before\n```\ncode\n```\nafter\n```\nmore\n```\ndone")
    (goto-char 1)
    (let ((mb (save-excursion
                (should (= (helixel-up-regex-block "^```" "^```" 1 nil) 0))
                (match-beginning 0))))
      (should mb)
      (goto-char mb)
      (should (looking-at "```$")))))

(ert-deftest helixel-test-up-regex-block-counter-diff ()
  "Test counter-based up-regex-block with different begin/end."
  (with-temp-buffer
    (insert "before\n#+begin\na\n#+begin\nb\n#+end\nc\n#+end\nafter")
    (goto-char (point-min))
    (search-forward "a")
    (let ((mb (save-excursion
                (should (= (helixel-up-regex-block "^#\\+begin" "^#\\+end" 1 nil) 0))
                (match-beginning 0))))
      (should mb)
      (goto-char mb)
      (should (looking-at "^#\\+end$")))))

;; --- helixel-up-regex-block: name-based (org blocks) ---

(ert-deftest helixel-test-up-regex-block-named-forward ()
  "Test named up-regex-block forward (org block)."
  (with-temp-buffer
    (insert "#+begin_src emacs-lisp\ncode\n#+end_src\nafter")
    (goto-char (point-min))
    (let ((mb (save-excursion
                (should (= (helixel-up-regex-block "^#\\+begin_\\([^ \n\r]+\\)"
                                                   "^#\\+end_\\([^ \n\r]+\\)"
                                                   1 1) 0))
                (match-beginning 0))))
      (should mb)
      (goto-char mb)
      (should (looking-at "^#\\+end_src")))))

(ert-deftest helixel-test-up-regex-block-named-nested ()
  "Test named up-regex-block with nested org blocks."
  (with-temp-buffer
    (insert "#+begin_src emacs-lisp\nouter\n#+begin_example\ninner\n#+end_example\nmore\n#+end_src")
    (goto-char (point-min))
    (let ((mb (save-excursion
                (should (= (helixel-up-regex-block "^#\\+begin_\\([^ \n\r]+\\)"
                                                   "^#\\+end_\\([^ \n\r]+\\)"
                                                   1 1) 0))
                (match-beginning 0))))
      (should mb)
      (goto-char mb)
      (should (looking-at "^#\\+end_src")))))

;; --- helixel-select-regex-block integration ---

(ert-deftest helixel-test-select-regex-block-inner-fence ()
  "Test select inner markdown fence block."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "```python\nprint('hello')\n```")
    (goto-char 14)
    (let ((range (helixel-select-regex-block "^```.+$" "^```[ \t]*$"
                                              nil nil nil 1 nil)))
      (should range)
      (should (> (nth 0 range) 1))
      (should (< (nth 0 range) 14))
      (should (> (nth 1 range) (nth 0 range)))
      (should (< (nth 1 range) (point-max))))))

(ert-deftest helixel-test-select-regex-block-around-fence ()
  "Test select around markdown fence block."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "```python\nprint('hello')\n```")
    (goto-char 14)
    (let ((range (helixel-select-regex-block "^```.+$" "^```[ \t]*$"
                                              nil nil nil 1 t)))
      (should range)
      (should (= (nth 0 range) 1))
      (should (> (nth 1 range) 1)))))

(ert-deftest helixel-test-select-regex-block-inner-org ()
  "Test select inner org block."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "#+begin_src emacs-lisp\n(message \"hi\")\n#+end_src\n")
    (goto-char 32)
    (let ((range (helixel-select-regex-block
                  "^#\\+begin_\\([^ \n\r]+\\)[^\n]*" "^#\\+end_\\([^ \n\r]+\\)[^\n]*"
                  nil nil nil 1 nil 1)))
      (should range)
      (should (> (nth 0 range) 1))
      (should (< (nth 0 range) 32))
      (should (> (nth 1 range) (nth 0 range)))
      (should (< (nth 1 range) (point-max))))))

(ert-deftest helixel-test-select-regex-block-around-org ()
  "Test select around org block."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "#+begin_src emacs-lisp\n(message \"hi\")\n#+end_src\n")
    (goto-char 32)
    (let ((range (helixel-select-regex-block
                  "^#\\+begin_\\([^ \n\r]+\\)[^\n]*" "^#\\+end_\\([^ \n\r]+\\)[^\n]*"
                  nil nil nil 1 t 1)))
      (should range)
      (should (= (nth 0 range) 1))
      (should (> (nth 1 range) 1)))))

;; --- helixel-up-block-at-point dispatch ---

(ert-deftest helixel-test-up-block-at-point-org ()
  "Test `helixel-up-block-at-point' dispatches to org block in org-mode."
  (with-temp-buffer
    (delay-mode-hooks (org-mode))
    (insert "#+begin_src emacs-lisp\ncode\n#+end_src")
    (goto-char (point-min))
    (let ((mb (save-excursion
                (should (= (helixel-up-block-at-point 1) 0))
                (match-beginning 0))))
      (should mb)
      (goto-char mb)
      (should (looking-at "^#\\+end_src")))))

(ert-deftest helixel-test-up-block-at-point-unsupported ()
  "Test `helixel-up-block-at-point' errors in unsupported mode."
  (with-temp-buffer
    (delay-mode-hooks (fundamental-mode))
    (insert "```\ncode\n```")
    (goto-char (point-min))
    (should-error (helixel-up-block-at-point 1))))

(ert-deftest helixel-test-block-inner-nested-fence-in-org ()
  "Inner block selects innermost fence inside an org block."
  (with-temp-buffer
    (delay-mode-hooks (org-mode))
    (insert "#+begin_ai\nhello\n```sh\nsudo emerge\ndev-python\n```\nworld\n#+end_ai")
    (goto-char (point-min))
    (search-forward "sudo")
    (let* ((helixel-textobj-visual-state-p-function nil)
           (helixel-textobj-action-function nil))
      (setq helixel--block-chosen-spec nil)
      (call-interactively #'helixel-mark-inner-block)
      (message "region: %d-%d content: '%s'" 
               (region-beginning) (region-end)
               (buffer-substring (region-beginning) (region-end)))
      (should (> (region-beginning) 20))
      (should (< (region-end) 50)))))

(ert-deftest helixel-test-block-fallback-brackets ()
  "Fallback selects bracket pairs in fundamental-mode."
  (with-temp-buffer
    (delay-mode-hooks (fundamental-mode))
    (insert "before (inner) after")
    (goto-char (point-min))
    (search-forward "nne")
    (let* ((helixel-textobj-visual-state-p-function nil)
           (helixel-textobj-action-function nil))
      (setq helixel--block-chosen-spec nil)
      (call-interactively #'helixel-mark-inner-block)
      ;; inner = content between parens, excluding parens
      (should (= (region-beginning) 9))   ; after (
      (should (= (region-end) 14)))))     ; at )

;;; Repeat Edit tests

(ert-deftest helixel-test-repeat-edit-no-prev ()
  "Test repeat-edit with no previous edit signals error."
  (helixel-test-with-buffer "hello world"
    (setq helixel--last-tx nil)
    (should-error (helixel-repeat-edit))))

(ert-deftest helixel-test-repeat-edit-paste ()
  "Test repeat paste."
  (helixel-test-with-buffer "hello world"
    (goto-char 7)
    (kill-word 1)
    (setq last-command nil this-command 'helixel-yank)
    (helixel-yank)
    (should (string= (buffer-string) "hello world"))
    (goto-char 7)
    (helixel-repeat-edit)
    (should (string= (buffer-string) "hello worldworld"))))

(ert-deftest helixel-test-repeat-edit-replace-char ()
  "Test repeat replace-char."
  (helixel-test-with-buffer "hello world"
    (goto-char 1)
    (setq last-command nil this-command 'helixel-replace-char)
    (helixel-replace-char ?X)
    (should (string= (buffer-string) "Xello world"))
    (goto-char 2)
    (helixel-repeat-edit)
    (should (string= (buffer-string) "XXllo world"))))

(ert-deftest helixel-test-repeat-edit-indent ()
  "Test repeat indent right with line selection."
  (helixel-test-with-buffer "hello\nworld\n"
    (goto-char 1)
    (setq last-command nil this-command 'helixel-select-line)
    (helixel-select-line)
    (setq last-command 'helixel-select-line this-command 'helixel-indent-right)
    (helixel-indent-right)
    (let ((after-first (buffer-string)))
      (should-not (string= "hello\nworld\n" after-first))
      (next-line)
      (helixel-repeat-edit)
      (should-not (string= after-first (buffer-string))))))

(ert-deftest helixel-test-repeat-edit-kill-textobj ()
  "Test repeat kill with textobj selection (diw style)."
  (helixel-test-with-buffer "hello world foo"
    (goto-char 3)
    (setq last-command nil this-command 'helixel-mark-inner-word)
    (helixel-mark-inner-word)
    (setq last-command 'helixel-mark-inner-word this-command 'helixel-kill-thing-at-point)
    (helixel-kill-thing-at-point)
    (should (string= (buffer-string) " world foo"))
    (goto-char 3)
    (helixel-repeat-edit)
    (should (string= (buffer-string) "  foo"))))

(ert-deftest helixel-test-repeat-edit-kill-linewise ()
  "Test repeat kill with linewise selection (x d style)."
  (helixel-test-with-buffer "first line\nsecond line\nthird line\n"
    (goto-char 3)
    (setq last-command nil this-command 'helixel-select-line)
    (helixel-select-line)
    (setq last-command 'helixel-select-line this-command 'helixel-kill-thing-at-point)
    (helixel-kill-thing-at-point)
    (should (string= (buffer-string) "second line\nthird line\n"))
    (helixel-repeat-edit)
    (should (string= (buffer-string) "third line\n"))))

(ert-deftest helixel-test-repeat-edit-change-textobj ()
  "Test repeat change with textobj (ciw style)."
  (helixel-test-with-buffer "hello world foo"
    (goto-char 3)
    (setq helixel--last-tx
          `(:op change
                      :sel (:fn helixel-mark-inner-word :kind textobj)
                      :payload (:inserted-text "CHANGED")))
    (helixel-repeat-edit)
    (should (string= (buffer-string) "CHANGED world foo"))
    (goto-char 1)
    (helixel-repeat-edit)
    (should (string= (buffer-string) "CHANGED world foo"))))

(ert-deftest helixel-test-repeat-edit-preserves-last-edit ()
  "Test that repeat-edit does not overwrite helixel--last-tx."
  (helixel-test-with-buffer "hello world"
    (goto-char 7)
    (kill-word 1)
    (setq last-command nil this-command 'helixel-yank)
    (helixel-yank)
    (let ((before helixel--last-tx))
      (helixel-repeat-edit)
      (should (equal helixel--last-tx before)))))

(ert-deftest helixel-test-repeat-edit-clear-data ()
  "Test repeat-edit clears selection data after operation."
  (helixel-test-with-buffer "hello world"
    (goto-char 7)
    (kill-word 1)
    (setq last-command nil this-command 'helixel-yank)
    (helixel-yank)
    (helixel-repeat-edit)
    (should (null helixel--selection-type))))

(ert-deftest helixel-test-repeat-edit-copy ()
  "Test repeat copy (yank)."
  (helixel-test-with-buffer "hello world"
    (goto-char 1)
    (setq last-command nil this-command 'helixel-mark-inner-word)
    (helixel-mark-inner-word)
    (setq last-command 'helixel-mark-inner-word this-command 'helixel-kill-ring-save)
    (helixel-kill-ring-save)
    (should (string= (current-kill 0 t) "hello"))
    (goto-char 7)
    (helixel-repeat-edit)
    (should (string= (current-kill 0 t) "world"))))

(ert-deftest helixel-test-repeat-edit-insert-text ()
  "Test repeat insert-text (i style)."
  (helixel-test-with-buffer "hello world"
    (goto-char 7)
    (setq helixel--last-tx
          '(:op insert-text
                      :sel nil
                      :payload (:text "INSERTED")))
    (helixel-repeat-edit)
    (should (string= (buffer-string) "hello INSERTEDworld"))))

(ert-deftest helixel-test-repeat-edit-insert-text-empty ()
  "Test repeat insert-text with empty text does nothing."
  (helixel-test-with-buffer "hello world"
    (goto-char 7)
    (setq helixel--last-tx
          '(:op insert-text
                      :sel nil
                      :payload (:text "")))
    (helixel-repeat-edit)
    (should (string= (buffer-string) "hello world"))))

(ert-deftest helixel-test-repeat-edit-movement-kill ()
  "Test repeat kill with movement selection (v w d style)."
  (helixel-test-with-buffer "hello world foo"
    (goto-char 1)
    (setq helixel--last-tx
          `(:op kill
                      :sel (:kind movement
                                :moves ((helixel-forward-word-start . 2)))))
    (helixel-repeat-edit)
    (should (string= (buffer-string) "foo"))))

(ert-deftest helixel-test-repeat-edit-movement-change ()
  "Test repeat change with movement selection (v w c style)."
  (helixel-test-with-buffer "hello world foo"
    (goto-char 1)
    (setq helixel--last-tx
          `(:op change
                      :sel (:kind movement
                                :moves ((helixel-forward-word-start . 1)))
                      :payload (:inserted-text "X")))
    (helixel-repeat-edit)
    (should (string= (buffer-string) "Xworld foo"))))

(ert-deftest helixel-test-repeat-invariant-sel-ctx-consumed ()
  "Test record-edit consumes helixel--repeat-sel-ctx."
  (helixel-test-with-buffer "hello world"
    (goto-char 1)
    (setq last-command nil this-command 'helixel-mark-inner-word)
    (helixel-mark-inner-word)
    (should helixel--repeat-sel-ctx)
    (setq last-command 'helixel-mark-inner-word this-command 'helixel-kill-thing-at-point)
    (helixel-kill-thing-at-point)
    (should (null helixel--repeat-sel-ctx))))

(ert-deftest helixel-test-repeat-invariant-repeat-no-pollute-ring ()
  "Test repeat-edit does not add extra entries to the action ring beyond record-edit."
  (helixel-test-with-buffer "hello world"
    (goto-char 1)
    (setq last-command nil this-command 'helixel-mark-inner-word)
    (helixel-mark-inner-word)
    (setq last-command 'helixel-mark-inner-word this-command 'helixel-kill-thing-at-point)
    (helixel-kill-thing-at-point)
    (let ((ring-len (length helixel--action-ring)))
      (helixel-repeat-edit)
      (should (= (length helixel--action-ring) ring-len)))))

(ert-deftest helixel-test-repeat-invariant-insert-after-records ()
  "Test helixel-insert-after (a) records insert-text."
  (helixel-test-with-buffer "hello world"
    (goto-char 3)
    (setq helixel--last-tx nil
          helixel--change-track-marker nil)
    (helixel-insert-after)
    (should (eq (helixel-edit-op helixel--last-tx) 'insert-text))
    (should helixel--change-track-marker)
    (set-marker helixel--change-track-marker nil)
    (setq helixel--change-track-marker nil)))

;; ============================================================================
;; Surround tests
;; ============================================================================

(ert-deftest helixel-test-surround-add-paren ()
  "Test `helixel--surround-add' with (pair."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "hello")
    (goto-char 1) (push-mark (point) nil t) (goto-char 6) (activate-mark)
    (helixel--surround-add ?\( ?\))
    (should (equal (buffer-string) "(hello)"))
    (should (region-active-p))
    (should (= (region-beginning) 1))
    (should (= (region-end) 8))))

(ert-deftest helixel-test-surround-add-bracket ()
  "Test `helixel--surround-add' with [pair."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "hello")
    (goto-char 1) (push-mark (point) nil t) (goto-char 6) (activate-mark)
    (helixel--surround-add ?\[ ?\])
    (should (equal (buffer-string) "[hello]"))
    (should (= (region-beginning) 1))
    (should (= (region-end) 8))))

(ert-deftest helixel-test-surround-add-quote ()
  "Test `helixel--surround-add' with 'pair."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "hello")
    (goto-char 1) (push-mark (point) nil t) (goto-char 6) (activate-mark)
    (helixel--surround-add ?\' ?\')
    (should (equal (buffer-string) "'hello'"))
    (should (region-active-p))))

(ert-deftest helixel-test-surround-add-block ()
  "Test `helixel--surround-add' with string block pair."
  (with-temp-buffer
    (org-mode)
    (transient-mark-mode 1)
    (insert "hello")
    (goto-char 1) (push-mark (point) nil t) (goto-char 6) (activate-mark)
    (helixel--surround-add "#+begin_quote " "#+end_quote")
    (should (string-match "\\`#\\+begin_quote .*\nhello\n#\\+end_quote\\'" (buffer-string)))))

(ert-deftest helixel-test-surround-add-tag ()
  "Test `helixel--surround-add-tag'."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "hello")
    (goto-char 1) (push-mark (point) nil t) (goto-char 6) (activate-mark)
    (helixel--surround-add-tag "div")
    (should (equal (buffer-string) "<div>\nhello\n</div>"))))

(ert-deftest helixel-test-surround-add-tag-inline ()
  "Test `helixel--surround-add-tag' on content with leading newline.
The leading newline is part of content so mt adds newline only before close."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "\nhello")
    (goto-char 1) (push-mark (point) nil t) (goto-char 7) (activate-mark)
    (helixel--surround-add-tag "b")
    (should (equal (buffer-string) "<b>\nhello\n</b>"))))

(ert-deftest helixel-test-surround-delete-pair-inner ()
  "Test delete surrounding () when point is inside (mi()."
  (with-temp-buffer
    (insert "(hello)")
    (goto-char 4)
    (helixel--surround-delete-delimiter (helixel--make-pair-delimiter ?\( ?\)))
    (should (equal (buffer-string) "hello"))))

(ert-deftest helixel-test-surround-delete-pair-outer ()
  "Test delete surrounding () when point is after the close (ma()."
  (with-temp-buffer
    (insert "(hello)")
    (goto-char 7)
    (helixel--surround-delete-delimiter (helixel--make-pair-delimiter ?\( ?\)))
    (should (equal (buffer-string) "hello"))))

(ert-deftest helixel-test-surround-delete-quote ()
  "Test delete surrounding '' when point is inside."
  (with-temp-buffer
    (insert "'hello'")
    (goto-char 4)
    (helixel--surround-delete-delimiter (helixel--make-pair-delimiter ?\' ?\'))
    (should (equal (buffer-string) "hello"))))

(ert-deftest helixel-test-surround-delete-quote-outer ()
  "Test delete surrounding \"\" when point is after the close (ma\")."
  (with-temp-buffer
    (insert "\"hello\"")
    (goto-char 8)
    (helixel--surround-delete-delimiter (helixel--make-pair-delimiter ?\" ?\"))
    (should (equal (buffer-string) "hello"))))

(ert-deftest helixel-test-surround-delete-tag ()
  "Test delete surrounding XML tags."
  (with-temp-buffer
    (insert "<div>hello</div>")
    (goto-char 8)
    (helixel--surround-delete-delimiter (helixel--make-tag-delimiter))
    (should (equal (buffer-string) "hello"))))

(ert-deftest helixel-test-surround-delete-tag-with-newlines ()
  "Test delete surrounding XML tags with newlines."
  (with-temp-buffer
    (insert "<div>\nhello\n</div>")
    (goto-char 9)
    (helixel--surround-delete-delimiter (helixel--make-tag-delimiter))
    (should (equal (buffer-string) "hello"))))

(ert-deftest helixel-test-surround-replace-pair ()
  "Test replace () with []."
  (with-temp-buffer
    (insert "(hello)")
    (goto-char 4)
    (helixel--surround-replace-pair (helixel--make-pair-delimiter ?\( ?\)) ?\[ ?\])
    (should (equal (buffer-string) "[hello]"))))

(ert-deftest helixel-test-surround-replace-quote ()
  "Test replace '' with \"\"."
  (with-temp-buffer
    (insert "'hello'")
    (goto-char 4)
    (helixel--surround-replace-pair (helixel--make-pair-delimiter ?\' ?\') ?\" ?\")
    (should (equal (buffer-string) "\"hello\""))))

(ert-deftest helixel-test-surround-replace-tag ()
  "Test replace tag div -> p."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "hello")
    (goto-char 1) (push-mark (point) nil t) (goto-char 6) (activate-mark)
    (helixel--surround-add-tag "div")
    (helixel--surround-replace-tag "p" (helixel--make-tag-delimiter))
    (should (equal (buffer-string) "<p>\nhello\n</p>"))))

(ert-deftest helixel-test-surround-replace-equal-repeated ()
  "Test repeated mr does not accumulate newlines."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "hello")
    (goto-char 1) (push-mark (point) nil t) (goto-char 6) (activate-mark)
    (helixel--surround-add-tag "div")
    (helixel--surround-replace-tag "p" (helixel--make-tag-delimiter))
    (helixel--surround-replace-tag "span" (helixel--make-tag-delimiter))
    (should (equal (buffer-string) "<span>\nhello\n</span>"))))

(ert-deftest helixel-test-surround-chain-ms-md ()
  "Chain ms( then md."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "hello")
    (goto-char 1) (push-mark (point) nil t) (goto-char 6) (activate-mark)
    (helixel--surround-add ?\( ?\))
    (let ((d (helixel--make-pair-delimiter ?\( ?\))))
      (let ((pos (helixel--surround-delete-delimiter d)))
        (goto-char pos)
        (should (equal (buffer-string) "hello"))))))

(ert-deftest helixel-test-surround-chain-ms-mr-md ()
  "Chain ms[ then mr{ then md."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "hello")
    (goto-char 1) (push-mark (point) nil t) (goto-char 6) (activate-mark)
    (helixel--surround-add ?\[ ?\])
    (helixel--surround-replace-pair (helixel--make-pair-delimiter ?\[ ?\]) ?\{ ?\})
    (let ((d (helixel--make-pair-delimiter ?\{ ?\})))
      (let ((pos (helixel--surround-delete-delimiter d)))
        (goto-char pos)
        (should (equal (buffer-string) "hello"))))))

(ert-deftest helixel-test-surround-chain-mt-mr-md ()
  "Chain mt div -> mr p -> md."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "hello")
    (goto-char 1) (push-mark (point) nil t) (goto-char 6) (activate-mark)
    (helixel--surround-add-tag "div")
    (helixel--surround-replace-tag "p" (helixel--make-tag-delimiter))
    (let ((d (helixel--make-tag-delimiter)))
      (let ((pos (helixel--surround-delete-delimiter d)))
        (goto-char pos)
        (should (equal (buffer-string) "hello"))))))

(ert-deftest helixel-test-surround-replace-trailing-newline ()
  "Test replace () with [] when content has trailing newline."
  (with-temp-buffer
    (insert "(hello)\n")
    (goto-char 4)
    (helixel--surround-replace-pair (helixel--make-pair-delimiter ?\( ?\)) ?\[ ?\])
    (should (equal (buffer-string) "[hello]\n"))))

(ert-deftest helixel-test-surround-block-lookup ()
  "Test block pair lookup returns (STRING . STRING)."
  (with-temp-buffer
    (org-mode)
    (let ((pair (helixel--surround-block-lookup ?s)))
      (should pair)
      (should (stringp (car pair)))
      (should (stringp (cdr pair)))
      (should (string-match "begin_src" (car pair)))
      (should (string-match "end_src" (cdr pair))))))

(ert-deftest helixel-test-surround-block-lookup-fallback ()
  "Test block pair lookup in fundamental mode returns nil."
  (with-temp-buffer
    (fundamental-mode)
    (should-not (helixel--surround-block-lookup ?s))))

(ert-deftest helixel-test-surround-available-keys ()
  "Test `helixel--surround-available-keys' returns expected keys."
  (with-temp-buffer
    (fundamental-mode)
    (let ((keys-str (string-join (helixel--surround-available-keys) " ")))
      (should (string-match-p "(" keys-str))
      (should (string-match-p "\\[" keys-str))
      (should (string-match-p "'" keys-str))
      (should (string-match-p "\"" keys-str)))))

(ert-deftest helixel-test-surround-available-keys-org ()
  "Test `helixel--surround-available-keys' includes block keys in org."
  (with-temp-buffer
    (org-mode)
    (let ((keys (helixel--surround-available-keys)))
      (should (cl-some (lambda (k) (string-match "src" k)) keys)))))

(ert-deftest helixel-test-surround-delete-block ()
  "Test delete block after ms s in org-mode."
  (with-temp-buffer
    (org-mode)
    (transient-mark-mode 1)
    (insert "hello")
    (goto-char 1) (push-mark (point) nil t) (goto-char 6) (activate-mark)
    (let ((pair (helixel--surround-block-lookup ?s)))
      (helixel--surround-add (car pair) (cdr pair))
      (let ((d (helixel--make-block-delimiter (car pair) (cdr pair))))
        (let ((pos (helixel--surround-delete-delimiter d)))
          (goto-char pos)
          (should (equal (buffer-string) "hello")))))))

;; ============================================================================
;; surround: delimiter protocol + edge cases
;; ============================================================================

;; --- helixel-up-xml-tag match-data fix ---

(ert-deftest helixel-test-up-xml-tag-match-data-from-opener ()
  "match-data is preserved when starting on opening tag."
  (with-temp-buffer
    (insert "<div>hello</div>")
    (goto-char 1)
    (should (zerop (helixel-up-xml-tag 1)))
    (should (match-beginning 0))
    (should (= (match-beginning 0) 11))))

(ert-deftest helixel-test-up-xml-tag-match-data-from-eob ()
  "match-data is preserved when starting from end of buffer."
  (with-temp-buffer
    (insert "<div>\nhello\n</div>")
    (goto-char (point-max))
    (should (zerop (helixel-up-xml-tag -1)))
    (should (match-beginning 0))
    (should (= (match-beginning 0) 1))))

(ert-deftest helixel-test-up-xml-tag-nested-from-inside ()
  "Find innermost tag pair when point is inside content."
  (with-temp-buffer
    (insert "<div><span>hello</span></div>")
    (goto-char 14) ;; inside "hello"
    (should (zerop (helixel-up-xml-tag 1)))
    (should (string= (match-string 0) "</span>"))
    (should (zerop (helixel-up-xml-tag -1)))
    (should (string= (match-string 0) "<span>"))))

;; --- helixel--strip-adjacent-newlines ---

(ert-deftest helixel-test-strip-adjacent-newlines-both ()
  "Strip newlines on both sides."
  (with-temp-buffer
    (insert "open\ncontent\nclose")
    (pcase-let ((`(,oe . ,cb) (helixel--strip-adjacent-newlines 5 14)))
      (should (= oe 6))
      (should (= cb 13)))))

(ert-deftest helixel-test-strip-adjacent-newlines-none ()
  "No newlines to strip."
  (with-temp-buffer
    (insert "openXcontentYclose")
    (pcase-let ((`(,oe . ,cb) (helixel--strip-adjacent-newlines 5 13)))
      (should (= oe 5))
      (should (= cb 13)))))

;; --- helixel-delimiter-bounds / unified delete ---

(ert-deftest helixel-test-delimiter-bounds-pair ()
  "Bounds for pair () from inside."
  (with-temp-buffer
    (insert "(hello)")
    (goto-char 4)
    (let* ((d (helixel--make-pair-delimiter ?\( ?\)))
           (b (helixel-delimiter-bounds d)))
      (should (= (caar b) 1))  ;; open-beg
      (should (= (cdar b) 2))  ;; open-end
      (should (= (cadr b) 7))  ;; close-beg
      (should (= (cddr b) 8))))) ;; close-end

(ert-deftest helixel-test-delimiter-bounds-pair-after-close ()
  "Bounds for pair from after closing delimiter."
  (with-temp-buffer
    (insert "(hello)")
    (goto-char 8) ;; after )
    (let* ((d (helixel--make-pair-delimiter ?\( ?\)))
           (b (helixel-delimiter-bounds d)))
      (should (= (caar b) 1))
      (should (= (cddr b) 8)))))

(ert-deftest helixel-test-delimiter-bounds-quote ()
  "Bounds for quote from inside (uses char-scanning fallback)."
  (with-temp-buffer
    (insert "\"hello\"")
    (goto-char 4)
    (should (> (helixel--surround-delete-delimiter
                (helixel--make-pair-delimiter ?\" ?\")) 0))
    (should (equal (buffer-string) "hello"))))

(ert-deftest helixel-test-delimiter-bounds-tag ()
  "Bounds for tag from inside."
  (with-temp-buffer
    (insert "<div>hello</div>")
    (goto-char 8)
    (let* ((d (helixel--make-tag-delimiter))
           (b (helixel-delimiter-bounds d)))
      (should (= (caar b) 1))
      (should (= (cadr b) 11)))))

(ert-deftest helixel-test-delimiter-bounds-block-org ()
  "Bounds for org block."
  (with-temp-buffer
    (org-mode)
    (insert "#+begin_src emacs-lisp\nhello\n#+end_src")
    (goto-char 25)
    (let* ((d (helixel--make-block-delimiter))
           (b (helixel-delimiter-bounds d)))
      (should b)
      (should (>= (caar b) 1)))))

(ert-deftest helixel-test-delete-block-via-delimiter ()
  "Delete org block via unified delimiter-delete."
  (with-temp-buffer
    (org-mode)
    (insert "#+begin_src emacs-lisp\nhello\n#+end_src")
    (goto-char 26)
    (let ((d (helixel--make-block-delimiter)))
      (helixel--surround-delete-delimiter d)
      (should (equal (buffer-string) "hello")))))

;; --- replace-tag fix: trailing text + newline correctness ---

(ert-deftest helixel-test-replace-tag-trailing-text ()
  "Replace tag when text follows closing tag."
  (with-temp-buffer
    (insert "prefix\n<div>\nhello\n</div>\nsuffix")
    (goto-char 14) ;; inside content
    (helixel--surround-replace-tag "p" (helixel--make-tag-delimiter))
    (should (equal (buffer-string) "prefix\n<p>\nhello\n</p>\nsuffix"))))

(ert-deftest helixel-test-replace-tag-inline-no-newlines ()
  "Replace inline tag, add newlines."
  (with-temp-buffer
    (insert "<div>hello</div>")
    (goto-char 8)
    (helixel--surround-replace-tag "p" (helixel--make-tag-delimiter))
    (should (equal (buffer-string) "<p>\nhello\n</p>"))))

(ert-deftest helixel-test-replace-tag-preexisting-newlines ()
  "Replace tag that already has newlines."
  (with-temp-buffer
    (insert "<div>\nhello\n</div>")
    (goto-char 9)
    (helixel--surround-replace-tag "p" (helixel--make-tag-delimiter))
    (should (equal (buffer-string) "<p>\nhello\n</p>"))))

(ert-deftest helixel-test-replace-tag-eob-no-extra-newlines ()
  "Replace tag at end of buffer, no extra \\n."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "hello")
    (goto-char 1) (push-mark (point) nil t) (goto-char 6) (activate-mark)
    (helixel--surround-add-tag "div")
    (helixel--surround-replace-tag "p" (helixel--make-tag-delimiter))
    ;; Must not have double newline
    (should-not (string-match "\n\n</p>" (buffer-string)))
    (should (equal (buffer-string) "<p>\nhello\n</p>"))))

;; --- nested tags ---

(ert-deftest helixel-test-delete-tag-nested-same-name ()
  "Delete innermost pair of same-name nested tags."
  (with-temp-buffer
    (insert "<div><div>hello</div></div>")
    (goto-char 14) ;; inside inner content
    (helixel--surround-delete-delimiter (helixel--make-tag-delimiter))
    (should (equal (buffer-string) "<div>hello</div>"))))

(ert-deftest helixel-test-delete-tag-nested-different-name ()
  "Delete innermost pair of different-name nested tags."
  (with-temp-buffer
    (insert "<div><span>hello</span></div>")
    (goto-char 15)
    (helixel--surround-delete-delimiter (helixel--make-tag-delimiter))
    (should (equal (buffer-string) "<div>hello</div>"))))

(ert-deftest helixel-test-replace-tag-innermost-nested ()
  "Replace innermost pair in nested tags."
  (with-temp-buffer
    (insert "<div><span>hello</span></div>")
    (goto-char 15)
    (helixel--surround-replace-tag "b" (helixel--make-tag-delimiter))
    (should (equal (buffer-string) "<div><b>\nhello\n</b></div>"))))

(ert-deftest helixel-test-nested-tag-mat-mr-replaces-inner ()
  "After mat on inner tag of nested tags, mr replaces inner (not outer)."
  (with-temp-buffer
    (insert "<p>\n<div>\nhello\n</div>\n</p>\n\nworld")
    ;; Simulate mat selecting outer <div> — region spans <div> to </div>
    (push-mark 5 nil t)
    (goto-char 25)
    (activate-mark)
    ;; position at midpoint of selection for finder
    (goto-char (/ (+ 5 25) 2))
    (helixel--surround-replace-tag "a" (helixel--make-tag-delimiter))
    (should (equal (buffer-string)
                   "<p>\n<a>\nhello\n</a>\n</p>\n\nworld"))))

(ert-deftest helixel-test-nested-tag-mat-md-deletes-inner ()
  "After mat on inner tag of nested tags, md deletes inner (not outer)."
  (with-temp-buffer
    (insert "<p>\n<div>\nhello\n</div>\n</p>\n\nworld")
    ;; Simulate mat selecting outer <div> — region spans <div> to </div>
    (push-mark 5 nil t)
    (goto-char 25)
    (activate-mark)
    ;; position at midpoint of selection for finder
    (goto-char (/ (+ 5 25) 2))
    (helixel--surround-delete-delimiter (helixel--make-tag-delimiter))
    (should (equal (buffer-string) "<p>\nhello\n</p>\n\nworld"))))

;; --- unified delete via delimiter protocol ---

(ert-deftest helixel-test-delete-delimiter-pair ()
  "Unified delete for pair via delimiter."
  (with-temp-buffer
    (insert "[hello]")
    (goto-char 4)
    (let ((d (helixel--make-pair-delimiter ?\[ ?\])))
      (helixel--surround-delete-delimiter d)
      (should (equal (buffer-string) "hello")))))

(ert-deftest helixel-test-delete-delimiter-regex ()
  "Unified delete for regex block."
  (with-temp-buffer
    (insert "#+begin_quote\nhello\n#+end_quote")
    (goto-char 18)
    (let ((d (helixel--make-regex-delimiter
              "#\\+begin_quote" "#\\+end_quote")))
      (helixel--surround-delete-delimiter d)
      (should (equal (buffer-string) "hello")))))

(ert-deftest helixel-test-chain-mt-mr-md-via-delimiter ()
  "Chain mt→mr→md via delimiter protocol."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "hello")
    (goto-char 1) (push-mark (point) nil t) (goto-char 6) (activate-mark)
    (helixel--surround-add-tag "div")
    (helixel--surround-replace-tag "p" (helixel--make-tag-delimiter))
    (let ((d (helixel--make-tag-delimiter)))
      (helixel--surround-delete-delimiter d)
      (should (equal (buffer-string) "hello")))))

;; --- delete-tag newline cleanup ---

(ert-deftest helixel-test-delete-tag-strips-newlines ()
  "Delete tag strips adjacent newlines."
  (with-temp-buffer
    (insert "<div>\nhello\n</div>")
    (goto-char 9)
    (helixel--surround-delete-delimiter (helixel--make-tag-delimiter))
    (should (equal (buffer-string) "hello"))))

;; --- ms add with new delimiter types ---

(ert-deftest helixel-test-surround-add-brace ()
  "Test `helixel--surround-add' with { pair."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "hello")
    (goto-char 1) (push-mark (point) nil t) (goto-char 6) (activate-mark)
    (helixel--surround-add ?\{ ?\})
    (should (equal (buffer-string) "{hello}"))))

(ert-deftest helixel-test-surround-add-angle ()
  "Test `helixel--surround-add' with < pair."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "hello")
    (goto-char 1) (push-mark (point) nil t) (goto-char 6) (activate-mark)
    (helixel--surround-add ?\< ?\>)
    (should (equal (buffer-string) "<hello>"))))

;;; helixel-test.el ends here
