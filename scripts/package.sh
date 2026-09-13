#!/bin/bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "$script_dir/.." && pwd)"
build_dir="$project_dir/.build/apple/Products/Release"
app_work_dir="$(mktemp -d /tmp/eternal-lights-app.XXXXXX)"
app_dir="$app_work_dir/Eternal Lights.app"
cli_path="$app_work_dir/eternal-lights"
contents_dir="$app_dir/Contents"
resources_dir="$contents_dir/Resources"
icon_work_dir="$(mktemp -d /tmp/eternal-lights-icon.XXXXXX)"
archive_work_path="$project_dir/.build/EternalLights-macOS-universal.zip"
archive_path="$project_dir/dist/EternalLights-macOS-universal.zip"

trap '/bin/rm -rf "$app_work_dir" "$icon_work_dir"' EXIT

cd "$project_dir"
swift build -c release --product EternalLights --arch arm64 --arch x86_64
swift build -c release --product eternal-lights --arch arm64 --arch x86_64

/bin/mkdir -p "$contents_dir/MacOS" "$resources_dir" "$project_dir/dist"
/usr/bin/install -m 755 "$build_dir/EternalLights" "$contents_dir/MacOS/EternalLights"
/usr/bin/install -m 755 "$build_dir/eternal-lights" "$cli_path"
/usr/bin/strip -x "$contents_dir/MacOS/EternalLights" "$cli_path"
/usr/bin/install -m 644 "$project_dir/Support/Info.plist" "$contents_dir/Info.plist"
/usr/bin/plutil -lint "$contents_dir/Info.plist"

/bin/mkdir "$icon_work_dir/AppIcon.iconset"
/usr/bin/sips -s format png "$project_dir/Support/AppIcon.svg" --out "$icon_work_dir/AppIcon-1024.png" >/dev/null
for size in 16 32 128 256 512; do
    /usr/bin/sips -z "$size" "$size" "$icon_work_dir/AppIcon-1024.png" --out "$icon_work_dir/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
    double_size=$((size * 2))
    /usr/bin/sips -z "$double_size" "$double_size" "$icon_work_dir/AppIcon-1024.png" --out "$icon_work_dir/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
/usr/bin/iconutil -c icns "$icon_work_dir/AppIcon.iconset" -o "$resources_dir/AppIcon.icns"

signing_identity="${ETERNAL_LIGHTS_SIGNING_IDENTITY:--}"
if [[ "$signing_identity" == "-" ]]; then
    /usr/bin/codesign --force --sign - "$cli_path"
    /usr/bin/codesign --force --sign - "$app_dir"
else
    /usr/bin/codesign --force --options runtime --timestamp --sign "$signing_identity" "$cli_path"
    /usr/bin/codesign --force --options runtime --timestamp --sign "$signing_identity" "$app_dir"
fi
/usr/bin/codesign --verify --strict "$cli_path"
/usr/bin/codesign --verify --deep --strict "$app_dir"

/bin/rm -f "$archive_work_path"
(cd "$app_work_dir" && /usr/bin/zip -q -r -X "$archive_work_path" "Eternal Lights.app" eternal-lights)

if [[ -n "${ETERNAL_LIGHTS_NOTARY_PROFILE:-}" ]]; then
    if [[ "$signing_identity" == "-" ]]; then
        echo "A Developer ID signing identity is required for notarization." >&2
        exit 1
    fi
    /usr/bin/xcrun notarytool submit "$archive_work_path" --keychain-profile "$ETERNAL_LIGHTS_NOTARY_PROFILE" --wait
    /usr/bin/xcrun stapler staple "$app_dir"
    /bin/rm -f "$archive_work_path"
    (cd "$app_work_dir" && /usr/bin/zip -q -r -X "$archive_work_path" "Eternal Lights.app" eternal-lights)
fi

/bin/mv -f "$archive_work_path" "$archive_path"
/usr/bin/shasum -a 256 "$archive_path"
echo "Packaged $archive_path"
