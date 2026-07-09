# MoveEyes — sichqonchaga qaraydigan Sharingan ko'zlar
#
#   make run      # build & ishga tushirish
#   make release  # optimallashtirilgan build

.DEFAULT_GOAL := run
.PHONY: run release build wallpaper stop app dmg

build:
	swift build

run: build
	.build/debug/MoveEyes

release:
	swift build -c release
	.build/release/MoveEyes

# ish stoli orqa foni (jonli wallpaper) sifatida ishga tushirish
wallpaper:
	swift build -c release
	pkill -x MoveEyes || true
	nohup .build/release/MoveEyes --wallpaper >/dev/null 2>&1 &

stop:
	pkill -x MoveEyes || true

app:
	Scripts/make-app.sh

dmg:
	Scripts/make-dmg.sh
