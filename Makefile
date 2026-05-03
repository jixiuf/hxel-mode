EMACS ?= emacs

FILES = helixel-action.el helixel-common.el helixel-search.el helixel-textobj.el helixel.el
ELS := helixel-action.elc helixel-common.elc helixel-search.elc helixel-textobj.elc helixel.elc

DEPS = package-lint

INIT_PACKAGES="(progn \
  (require 'package) \
  (push '(\"melpa\" . \"https://melpa.org/packages/\") package-archives) \
  (package-initialize) \
  (dolist (pkg '(${DEPS})) \
    (unless (package-installed-p pkg) \
      (unless (assoc pkg package-archive-contents) \
	(package-refresh-contents)) \
      (package-install pkg))) \
  (unless package-archive-contents (package-refresh-contents)) \
  )"

EMACS_BATCH=${EMACS} -Q -batch -L . --eval ${INIT_PACKAGES}

all: clean-elc compile lint test

compile: $(ELC)

%.elc: %.el
	$(EMACS) --batch -Q  -L . --eval "(setq byte-compile-error-on-warn t)" \
		--eval "(package-initialize)" \
		-f batch-byte-compile $<

clean-elc:
	rm -f *.elc

clean: clean-elc

TEST_SELECTOR ?= t
test:
	@echo "---- Run unit tests"
	@${EMACS_BATCH} \
		$(addprefix -l ,$(FILES)) \
		-l helixel-test.el \
		--eval "(ert-run-tests-batch-and-exit '${TEST_SELECTOR})" \
		&& echo "OK"

checkdoc:
	@for file in $(FILES); do \
		echo "Checking $$file..."; \
		$(EMACS) -Q -L . --batch \
		--eval "(require 'checkdoc)" \
		--eval "(setq checkdoc-sentence-ends-double-space t \
		            checkdoc-proper-noun-list nil \
		            checkdoc-verb-check-experimental-flag nil)" \
		--eval "(let ((ok t)) \
		          (ignore-errors (kill-buffer \"*Warnings*\")) \
		          (let ((inhibit-message t)) \
		            (checkdoc-file \"$$file\")) \
		          (when (get-buffer \"*Warnings*\") \
		            (setq ok nil) \
		            (with-current-buffer \"*Warnings*\" \
		              (message \"%s\" (buffer-string)))) \
		          (unless ok (kill-emacs 1)))" || exit 1; \
	done



package-lint:
	$(EMACS_BATCH) --eval "(package-initialize)" \
		--eval "(require 'package-lint)" \
		--eval "(setq package-lint-main-file \"helixel.el\")" \
		-f package-lint-batch-and-exit \
		${FILES}


COLWIDTH ?= 80

column-check:
	@echo "---- Check column width <= $(COLWIDTH)"
	@for file in $(FILES); do \
		awk -v w=$(COLWIDTH) \
		'length>w{print FILENAME":"NR": line exceeds "w" columns ("length" chars)"; err=1} END{exit err}' \
		"$$file" || exit 1; \
	done && echo "OK"


lint: compile checkdoc package-lint column-check

.PHONY:	all compile clean-elc test lint checkdoc
