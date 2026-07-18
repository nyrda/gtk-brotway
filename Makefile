# Brotway docs (mdbook). Run from this dir.
.PHONY: lint build serve keymasq-overlay verify-keymasq-overlay

lint:   ## markdownlint the docs sources (config: .markdownlint.jsonc)
	markdownlint 'docs/src/**/*.md'

build:  ## build the book into docs/book
	mdbook build docs

serve:  ## serve the docs at http://0.0.0.0:3000
	mdbook serve docs -n 0.0.0.0 -p 3000

keymasq-overlay:  ## build the Arch/Keymasq private runtime overlay
	./packaging/keymasq/build-overlay.sh

verify-keymasq-overlay:  ## verify an existing Arch/Keymasq overlay
	./packaging/keymasq/verify-overlay.sh
