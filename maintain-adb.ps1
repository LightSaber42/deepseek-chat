# Maintain ADB Wireless Debugging Connection
Write-Host "Configuring device for stable ADB wireless debugging..."

# Keep device awake while plugged in
adb shell settings put global stay_on_while_plugged_in 3

# Disable device idle
adb shell dumpsys deviceidle disable

# Keep screen on
adb shell svc power stayon true

Write-Host "Device configured for stable wireless debugging."
Write-Host "Note: You may need to re-run this script if you reconnect your device."