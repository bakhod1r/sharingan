# MoveEyes — sichqonchaga qaraydigan Sharingan ko'zlar
#
#   make run      # build & ishga tushirish
#   make release  # optimallashtirilgan build

.DEFAULT_GOAL := run
.PHONY: run release build

build:
	swift build

run: build
	.build/debug/MoveEyes

release:
	swift build -c release
	.build/release/MoveEyes
