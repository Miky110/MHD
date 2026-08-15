#!/usr/bin/env bash
set -euo pipefail

ANDROID_MANIFEST="android/app/src/main/AndroidManifest.xml"
IOS_PLIST="ios/Runner/Info.plist"

if ! grep -q 'android.permission.ACCESS_FINE_LOCATION' "$ANDROID_MANIFEST"; then
  sed -i.bak '/<manifest/a\
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />\
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />' "$ANDROID_MANIFEST"
  rm "$ANDROID_MANIFEST.bak"
fi

if ! grep -q 'NSLocationWhenInUseUsageDescription' "$IOS_PLIST"; then
  /usr/libexec/PlistBuddy -c 'Add :NSLocationWhenInUseUsageDescription string MHD Mikylov používá polohu k nalezení nejbližší zastávky a automatickému hlášení.' "$IOS_PLIST"
fi
