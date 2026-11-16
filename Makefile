.PHONY: build run test app install clean

# Desde macOS 27 las CLT no traen los macros de SwiftUI (ni Testing/XCTest): todo
# se compila con el toolchain de Xcode. Se puede sobreescribir desde el entorno.
export DEVELOPER_DIR ?= /Applications/Xcode.app

build:
	swift build

test:
	swift test

run: build
	./.build/debug/MyTasks

app:
	bash scripts/make_app.sh

install: app
	rm -rf /Applications/MyTasks.app
	cp -R dist/MyTasks.app /Applications/

clean:
	rm -rf .build dist
