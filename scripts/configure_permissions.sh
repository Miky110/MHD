#!/usr/bin/env bash
set -euo pipefail

ANDROID_MANIFEST="android/app/src/main/AndroidManifest.xml"
IOS_PLIST="ios/Runner/Info.plist"

if [[ -f "$ANDROID_MANIFEST" ]] &&
  ! grep -q 'android.permission.ACCESS_FINE_LOCATION' "$ANDROID_MANIFEST"; then
  sed -i.bak '/<manifest/a\
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />\
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />' "$ANDROID_MANIFEST"
  rm "$ANDROID_MANIFEST.bak"
fi

if [[ -x /usr/libexec/PlistBuddy ]] && [[ -f "$IOS_PLIST" ]]; then
  if ! /usr/libexec/PlistBuddy -c 'Print :NSLocationWhenInUseUsageDescription' "$IOS_PLIST" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c 'Add :NSLocationWhenInUseUsageDescription string MHD Mikylov používá vaši polohu k nalezení nejbližší zastávky a zobrazení správných odjezdů.' "$IOS_PLIST"
  fi

  if ! /usr/libexec/PlistBuddy -c 'Print :NSLocationAlwaysAndWhenInUseUsageDescription' "$IOS_PLIST" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c 'Add :NSLocationAlwaysAndWhenInUseUsageDescription string V režimu řidiče používá MHD Mikylov polohu během aktivní jízdy k automatickému rozpoznání příjezdu do zastávky a přehrání správného hlášení, i když aplikace není právě na obrazovce.' "$IOS_PLIST"
  fi
fi
