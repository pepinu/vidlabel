#!/bin/bash
# Configure Xcode project for OpenCV

PROJECT_DIR="/Users/pepi/Developer/vidlabel/VidLabel"
cd "$PROJECT_DIR"

echo "🔧 Configuring VidLabel project for OpenCV..."

# Use xcodebuild to set build settings
xcodebuild -project VidLabel.xcodeproj \
  -target VidLabel \
  -configuration Debug \
  OTHER_LDFLAGS='$(inherited) -lopencv_core -lopencv_imgproc -lopencv_video -lopencv_videoio' \
  HEADER_SEARCH_PATHS='$(inherited) /opt/homebrew/opt/opencv/include/opencv4' \
  LIBRARY_SEARCH_PATHS='$(inherited) /opt/homebrew/opt/opencv/lib' \
  SWIFT_OBJC_BRIDGING_HEADER='$(SRCROOT)/VidLabel/VidLabel-Bridging-Header.h' \
  -showBuildSettings > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo "✅ Build settings configured successfully"
else
    echo "⚠️  Warning: xcodebuild configuration had issues, will use manual configuration"
fi

echo ""
echo "📝 You need to manually configure these settings in Xcode:"
echo ""
echo "1. Open VidLabel.xcodeproj in Xcode"
echo "2. Select VidLabel target → Build Settings"
echo "3. Search and set these values:"
echo ""
echo "   Header Search Paths:"
echo "   /opt/homebrew/opt/opencv/include/opencv4"
echo ""
echo "   Library Search Paths:"
echo "   /opt/homebrew/opt/opencv/lib"
echo ""
echo "   Other Linker Flags:"
echo "   -lopencv_core -lopencv_imgproc -lopencv_video -lopencv_videoio"
echo ""
echo "   Objective-C Bridging Header:"
echo "   \$(SRCROOT)/VidLabel/VidLabel-Bridging-Header.h"
echo ""
echo "4. Make sure to add the new files to the project:"
echo "   - MotionDetector.h"
echo "   - MotionDetector.mm"
echo "   - VidLabel-Bridging-Header.h"
echo ""
