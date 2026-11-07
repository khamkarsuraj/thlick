#!/usr/bin/env bash
#
# Archives the Mac App Store build, ready to upload to App Store Connect (issue #81).
#
# Builds the `thlick App Store` scheme as a universal Release archive. The build number is
# the commit count, as in the DMG release, so an upload from a newer commit is always
# higher than the last one, which App Store Connect requires. The version is
# MARKETING_VERSION from Config/Shared.xcconfig unless --version is given. The archive goes
# into Xcode's Archives folder, so it shows up in the Organizer, where Distribute App >
# App Store Connect validates and uploads it.
#
# Usage:
#   scripts/archive_appstore.sh [--version X.Y[.Z]]
#
#   --version X.Y[.Z]    the version shown on the App Store (default MARKETING_VERSION)
#
# Signing is automatic, with the account in Xcode > Settings > Accounts. The last line
# printed is the archive path.

set -euo pipefail

usage() { sed -n '3,18p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
fail() { echo "archive_appstore: $*" >&2; exit 1; }

version=
while [[ $# -gt 0 ]]; do
  case $1 in
    --version) version=$2; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown option: $1" >&2; usage ;;
  esac
done

cd "$(dirname "$0")/.."

version=${version:-$(sed -n 's/^MARKETING_VERSION = //p' Config/Shared.xcconfig)}
[[ $version =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] \
  || fail "version '$version' must be X.Y or X.Y.Z; the App Store takes no suffix such as -beta"
build=$(git rev-list --count HEAD)

if [[ -n $(git status --porcelain --untracked-files=no) ]]; then
  echo "archive_appstore: warning: uncommitted changes go into this archive, but build $build" \
    "is the commit count of HEAD" >&2
fi

archive="$HOME/Library/Developer/Xcode/Archives/$(date +%F)/thlick App Store $version ($build) $(date +%H.%M.%S).xcarchive"
log=build/archive_appstore.log
mkdir -p build

echo "Archiving Thlick $version ($build) for the App Store"
xcodebuild archive \
  -project thlick.xcodeproj \
  -scheme "thlick App Store" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$archive" \
  -allowProvisioningUpdates \
  MARKETING_VERSION="$version" \
  CURRENT_PROJECT_VERSION="$build" \
  | tee "$log" \
  | grep -E 'error:|warning:|\*\* (ARCHIVE|BUILD)' \
  || fail "the archive failed; the full log is in $log"

app="$archive/Products/Applications/thlick.app"
[[ -d $app ]] || fail "no app in $archive; the full log is in $log"
plist="$app/Contents/Info.plist"
echo "Version:      $(plutil -extract CFBundleShortVersionString raw -o - "$plist")"
echo "Build:        $(plutil -extract CFBundleVersion raw -o - "$plist")"
echo "Category:     $(plutil -extract LSApplicationCategoryType raw -o - "$plist")"
echo "Architectures: $(lipo -archs "$app/Contents/MacOS/thlick")"
echo
echo "Next: in Xcode, Window > Organizer > Archives, select this archive and choose"
echo "Distribute App > App Store Connect."
echo "$archive"
