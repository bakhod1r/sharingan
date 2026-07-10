# Blink — liquid-glass Pomodoro + eye-health menu bar app
#
#   make            # build (debug)
#   make run        # build & run from source
#   make release    # optimized build
#   make test       # run the test suite
#   make app        # assemble dist/Blink.app
#   make dmg        # build dist/Blink.dmg (drag-install)
#   make install    # install the `tired` CLI onto PATH
#   make open       # open the assembled app
#   make clean      # remove build artifacts

# SwiftPM product (module names are unchanged); the shipped bundle is branded.
PRODUCT  := Blink
APP      := Sharingan
SCRIPTS  := Scripts

.DEFAULT_GOAL := build
.PHONY: build run release test app dmg install open clean

build:
	swift build

run:
	swift run $(PRODUCT)

release:
	swift build -c release

test:
	swift test

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
