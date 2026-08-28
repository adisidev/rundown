APP      = rundown
BUNDLE   = build/$(APP).app
BIN      = $(shell swift build -c release --show-bin-path 2>/dev/null)/$(APP)
FILE    ?= examples/talk.md

.PHONY: build app run install test clean

build:
	swift build -c release

app: build
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources
	cp $(BIN) $(BUNDLE)/Contents/MacOS/$(APP)
	cp Info.plist $(BUNDLE)/Contents/Info.plist
	codesign --force --deep --sign - $(BUNDLE)
	@echo "built $(BUNDLE)"

run: app
	pkill -f "$(APP).app/Contents/MacOS/$(APP)" || true
	open $(BUNDLE) --args "$(abspath $(FILE))"

install: app
	rm -rf /Applications/$(APP).app
	cp -R $(BUNDLE) /Applications/
	@echo "installed /Applications/$(APP).app — run: open -a rundown talk.md"

test:
	swift test

clean:
	rm -rf .build build
