.PHONY: build run test app install clean

build:
	swift build

# Los tests necesitan el toolchain de Xcode (las CLT no traen Testing/XCTest).
test:
	DEVELOPER_DIR=/Applications/Xcode.app swift test

run: build
	./.build/debug/MyTasks

app:
	bash scripts/make_app.sh

install: app
	rm -rf /Applications/MyTasks.app
	cp -R dist/MyTasks.app /Applications/

clean:
	rm -rf .build dist
