# Sharingan — liquid-glass Pomodoro + eye-health menu bar app
#
#   make            # build (debug)
#   make run        # build & run from source
#   make release    # optimized build
#   make test       # run the test suite
#   make selftest   # run the SelfTest executable
#   make app        # assemble dist/Sharingan.app
#   make dmg        # build dist/Sharingan.dmg (drag-install)
#   make install    # install the `tired` CLI onto PATH
#   make open       # open the assembled app
#   make clean      # remove build artifacts

# SwiftPM product and shipped bundle are both branded Sharingan.
PRODUCT  := Sharingan
APP      := Sharingan
SCRIPTS  := Scripts

# The app target needs Xcode's toolchain: under the Command Line Tools the
# SwiftUI macro plugin is missing ("plugin for module 'SwiftUIMacros' not
# found"). Use Xcode when xcode-select points elsewhere; an explicit
# DEVELOPER_DIR from the environment still wins. Exported so the Scripts/
# that `app`/`dmg`/`install` call inherit it.
XCODE_DEV := /Applications/Xcode.app/Contents/Developer
ifeq ($(origin DEVELOPER_DIR),undefined)
  ifneq ($(wildcard $(XCODE_DEV)),)
    DEVELOPER_DIR := $(XCODE_DEV)
  endif
endif
export DEVELOPER_DIR

.DEFAULT_GOAL := build
.PHONY: build run release test selftest app dmg install open clean

build:
	swift build

run:
	swift run $(PRODUCT)

release:
	swift build -c release

test:
	swift test

selftest:
	swift build --product SelfTest
	"$$(swift build --show-bin-path)/SelfTest"

app:
	$(SCRIPTS)/make-app.sh

dmg:
	$(SCRIPTS)/make-dmg.sh

install:
	$(SCRIPTS)/install-cli.sh

open: app
	open dist/$(APP).app

clean:
	swift package clean
	rm -rf .build dist
