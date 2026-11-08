#!/bin/bash
# The iPhone app's own settings, laid over the project `flutter create` makes (the ios/ folder isn't kept
# in git): its name, music that keeps playing in the background and on the lock screen, plain http for
# the player's local server and old podcasts, and the cassette icon.
set -euo pipefail
cd "$(dirname "$0")/.."
P=ios/Runner/Info.plist
B=/usr/libexec/PlistBuddy

$B -c "Set :CFBundleDisplayName Mixtape" "$P" 2>/dev/null || $B -c "Add :CFBundleDisplayName string Mixtape" "$P"
$B -c "Set :CFBundleName Mixtape" "$P" 2>/dev/null || $B -c "Add :CFBundleName string Mixtape" "$P"
$B -c "Delete :UIBackgroundModes" "$P" 2>/dev/null || true
$B -c "Add :UIBackgroundModes array" -c "Add :UIBackgroundModes:0 string audio" "$P"
$B -c "Delete :NSAppTransportSecurity" "$P" 2>/dev/null || true
$B -c "Add :NSAppTransportSecurity dict" -c "Add :NSAppTransportSecurity:NSAllowsArbitraryLoads bool true" \
   -c "Add :NSAppTransportSecurity:NSAllowsLocalNetworking bool true" "$P"
$B -c "Delete :ITSAppUsesNonExemptEncryption" "$P" 2>/dev/null || true
$B -c "Add :ITSAppUsesNonExemptEncryption bool false" "$P"

cp ios-extras/AppIcon.appiconset/* ios/Runner/Assets.xcassets/AppIcon.appiconset/
echo "iOS project set up: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$P"), background audio, icons"
