.PHONY: check build-macos build-android install install-macos install-boox package

check:
	./scripts/check.sh

build-macos:
	./scripts/build-macos.sh

build-android:
	./scripts/build-android.sh

install:
	./scripts/install.sh

install-macos:
	./scripts/install-macos.sh

install-boox:
	./scripts/install-boox.sh

package:
	./scripts/package-release.sh
