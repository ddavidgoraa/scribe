.PHONY: core project build test run clean

core:            ## Build Rust core XCFramework + Swift bindings
	./scripts/build-core.sh

project:         ## Generate Xcode project
	cd app && xcodegen generate

build: core project
	xcodebuild -project app/Scribe.xcodeproj -scheme Scribe -configuration Debug \
	  -destination 'platform=macOS,arch=arm64' -derivedDataPath app/build build

test: core project
	cd core && cargo test
	xcodebuild -project app/Scribe.xcodeproj -scheme Scribe \
	  -destination 'platform=macOS,arch=arm64' -derivedDataPath app/build test

run: build
	open app/build/Build/Products/Debug/Scribe.app

clean:
	rm -rf core/target app/build app/Scribe.xcodeproj app/Packages/MdCore/MdCoreFFI.xcframework
