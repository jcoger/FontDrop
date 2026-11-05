# FontDrop release tasks. Setup: docs/release.md
#   make release                       Developer ID signed, notarized, stapled DMG in dist/
#   make release NOTARY_PROFILE=name   use another notarytool keychain profile name
#   make release-adhoc                 ad-hoc signed DMG for local testing (same as scripts/release.sh --adhoc)
#   make test                          Rust core tests, then the Mac app tests
export NOTARY_PROFILE ?= fontdrop-notary

.PHONY: release release-adhoc test
release:
	scripts/release.sh

release-adhoc:
	scripts/release.sh --adhoc

test:
	cd core && cargo test
	macos/build.sh --test
