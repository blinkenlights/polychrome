APP := .build/Ear.app

.PHONY: app run test clean

# A real bundle: the microphone permission that reading BlackHole needs is
# granted per app, and only a bundle with a usage description can ask for it.
app:
	swift build -c release
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	cp .build/release/Ear $(APP)/Contents/MacOS/Ear
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	codesign --force --sign - $(APP)

run: app
	open $(APP)

test:
	swift test

clean:
	rm -rf .build
