#!/bin/bash
# Build the SWEET XNU kernel on any macOS host with Xcode 15.x.
# Mirrors .github/workflows/xnu.yml so the same build can run on Cirrus CI,
# Codemagic, a rented Mac or a friend's MacBook.
#
#   MACHINE_CONFIG=GUACAMOLE bash .github/ci-build.sh
#
# Output: out/kernel.<config>.<machine>  (e.g. kernel.development.guacamole)
set -euo pipefail

MACHINE_CONFIG=${MACHINE_CONFIG:-GUACAMOLE}
KERNEL_CONFIG=${KERNEL_CONFIG:-DEVELOPMENT}
MACOS_VERSION=${MACOS_VERSION:-13.5}
DXB_REPO=${DXB_REPO:-https://github.com/blacktop/darwin-xnu-build}
DXB_SHA=${DXB_SHA:-663906528d1cd5ea8fde7de6f16de73db9511549}

echo "== machine=$MACHINE_CONFIG config=$KERNEL_CONFIG xnu=$MACOS_VERSION =="
sw_vers

echo "== Xcode =="
XC=$(ls -d /Applications/Xcode*.app 2>/dev/null | sort -V | head -1 || true)
[ -n "${XC:-}" ] || { echo "no /Applications/Xcode*.app"; exit 1; }
export DEVELOPER_DIR="$XC/Contents/Developer"
sudo xcode-select -s "$XC" 2>/dev/null || true
xcodebuild -version
xcrun --find iig

echo "== dxb =="
rm -rf dxb
git init -q dxb
git -C dxb remote add origin "$DXB_REPO"
git -C dxb fetch -q --depth 1 origin "$DXB_SHA"
git -C dxb checkout -q FETCH_HEAD
cp xnu/patches/*.patch xnu/patches/*.sh dxb/patches/ 2>/dev/null || cp xnu/patches/*.patch dxb/patches/
# libfirehose_kernel is arm64e-only; the SWEET kernel is plain arm64
sed -i '' 's/ARCHS="x86_64 arm64e" VALID_ARCHS="x86_64 arm64e"/ARCHS="x86_64 arm64e arm64" VALID_ARCHS="x86_64 arm64e arm64"/' dxb/build.sh
grep -c 'VALID_ARCHS="x86_64 arm64e arm64"' dxb/build.sh
ls dxb/patches | wc -l

echo "== deps =="
if command -v brew >/dev/null; then
	brew install jq gum bash cmake ninja >/dev/null 2>&1 || brew install jq gum bash cmake ninja
fi
# build.sh only checks that xcodes exists; Xcode itself is preinstalled
if [ ! -x /usr/local/bin/xcodes ]; then
	printf '#!/bin/sh\nexit 0\n' | sudo tee /usr/local/bin/xcodes >/dev/null
	sudo chmod +x /usr/local/bin/xcodes
fi

echo "== build =="
export MACHINE_CONFIG KERNEL_CONFIG MACOS_VERSION
(cd dxb && bash build.sh)

echo "== collect =="
mkdir -p out
cp -R dxb/fakeroot/System/Library/Kernels/. out/ 2>/dev/null || true
ls -la out
shasum -a 256 out/kernel.* 2>/dev/null || true
echo "done: $(ls out/kernel.* 2>/dev/null | head -1)"
