APP := build/Meetie.app

.PHONY: app run debug release clean

app: release

release:
	swift build -c release
	CONFIG=release scripts/bundle.sh

run: debug
	open $(APP)

# Debug build: includes Test Dog and the --test-dog/--no-calendar flags.
debug:
	swift build -c debug
	CONFIG=debug scripts/bundle.sh

clean:
	rm -rf .build build
