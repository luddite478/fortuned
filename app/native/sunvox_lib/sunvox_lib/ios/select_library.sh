#!/bin/bash
#
# Automatically select the correct SunVox library based on the SDK
# This script should be run as a build phase in Xcode or before building
#

# Determine which SDK we're building for
if [ "${PLATFORM_NAME}" == "iphonesimulator" ] || [ "$1" == "simulator" ]; then
    # Building for simulator - use simulator library
    echo "Selecting SunVox library for iOS Simulator..."
    cp -f sunvox.a libsunvox.a
    echo "✓ Using simulator library (x86_64 + arm64 simulator)"
elif [ "${PLATFORM_NAME}" == "iphoneos" ] || [ "$1" == "device" ] || [ "$1" == "physical" ]; then
    # Building for device - use device library
    echo "Selecting SunVox library for iOS Device..."
    cp -f sunvox_arm64_device.a libsunvox.a
    echo "✓ Using device library (arm64 device)"
else
    # Default to simulator if not specified
    echo "Warning: Unknown platform '$1', defaulting to simulator library"
    cp -f sunvox.a libsunvox.a
fi

