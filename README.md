# VidLabel

A macOS video annotation tool for object detection and tracking, with automatic motion-based detection and manual refinement capabilities.

## Overview

VidLabel is a video annotation application designed for creating training datasets for object detection models. 
It combines automatic motion detection with manual annotation and tracking features, supporting both frame-by-frame annotation and semi-automated workflows.

## Key Features

### 🎯 Three Annotation Modes

1. **Manual Annotation**
   - Draw bounding boxes frame-by-frame
   - Multiple objects per frame
   - Color-coded object tracking
   - Frame-by-frame navigation

2. **Auto-Detection Mode** (Motion-Based)
   - Automatic object detection using OpenCV MOG2 background subtraction
   - Motion consistency validation with velocity smoothing
   - Prediction fallback for temporary occlusions
   - Processes untouched video footage efficiently
   - Generates proposals for review and refinement

3. **Vision Tracking Mode**
   - Apple Vision framework integration (`VNTrackObjectRequest`)
   - Bidirectional tracking (forward and backward)
   - High accuracy for extending manual annotations

### 📊 Export Formats

- **COCO JSON**: Industry-standard format with all objects as class 1 - I needed something for 1 class dataset, feel free to update
- Includes image metadata, bounding boxes in pixel coordinates

### 🛠️ Advanced Refinement Tools

- **Delete Frame Range**: Remove unstable detections from proposals
- **Trim Before/After**: Clean up tracking results
- **Batch Adjustments**: Expand or shift all boxes for an object
- **Proposal System**: Review and accept/reject auto-detections before committing

---

## Installation

### Prerequisites

- macOS 15.0 or later
- Xcode 16.0 or later
- Homebrew (for OpenCV installation)

### Setup

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd vidlabel
   ```

2. **Install OpenCV**
   ```bash
   brew install opencv
   ```

3. **Open the Xcode project**
   ```bash
   open VidLabel/VidLabel.xcodeproj
   ```

4. **Configure Build Settings** (if not already configured)

   In Xcode:
   - Select VidLabel target → Build Settings
   - Set **Header Search Paths**: `/opt/homebrew/opt/opencv/include/opencv4`
   - Set **Library Search Paths**: `/opt/homebrew/opt/opencv/lib`
   - Set **Other Linker Flags**: `-lopencv_core -lopencv_imgproc -lopencv_video -lopencv_videoio`
   - Set **Bridging Header**: `$(SRCROOT)/VidLabel/VidLabel-Bridging-Header.h`

5. **Build and Run** (Cmd+B, then Cmd+R)

---

## Usage Guide

### Basic Workflow

#### 1. Load Video
- Click **"Load Video"** button
- Select your video file (MP4, MOV, etc.)
- Video opens with playback controls

#### 2. Manual Annotation
1. Click **"Add Object"** to create a new tracked object
2. Drag on the video to draw a bounding box
3. Use **← →** arrow keys to navigate frames
4. Draw boxes on each frame where the object appears
5. Use **Track Forward/Backward** to auto-track between keyframes

#### 3. Auto-Detection (Recommended for New Videos)
1. Click **"Auto-Detect"** button in toolbar
2. Set **Frame Range** (e.g., 0 to 300, or leave blank for full video)
3. Click **"Start Detection"**
4. Review proposals:
   - **Green dashed boxes** = Motion detected
   - **Blue dashed boxes** = Position predicted
5. Use **"Delete Range..."** to remove unstable intervals
6. Click **"Accept"** to convert proposal to tracked object
7. Click **"Reject"** to discard proposal

#### 4. Refine and Track
- Select an object from the sidebar
- Adjust boxes manually on any frame
- Use **Track Forward/Backward** to extend annotations
- Use **Trim After/Before** to clean up tracking errors
- Use **Expand Boxes** to adjust all boxes by a fixed margin

#### 5. Export
- Click **"Export COCO"** button
- Save as `annotations.json`
- All objects are exported with `category_id: 1`

---

## Modes Explained

### Mode 1: Manual Annotation
**Best for:** Precise annotations, small datasets, complex scenes

**Workflow:**
1. Add object
2. Draw box on current frame
3. Navigate to next frame
4. Repeat

**Pros:**
- Complete control
- High precision
- Works for any object type

**Cons:**
- Time-consuming
- Tedious for long videos

---

### Mode 2: Auto-Detection (Motion Consistency)
**Best for:** Videos with moving objects, untouched footage, initial proposals

**Algorithm Details:**

```python
# Background Subtraction
fgbg = cv2.createBackgroundSubtractorMOG2(history=500, varThreshold=25)
fgmask = fgbg.apply(gray)

# Morphological Cleanup
kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
fgmask = cv2.morphologyEx(fgmask, cv2.MORPH_OPEN, kernel)
fgmask = cv2.morphologyEx(fgmask, cv2.MORPH_DILATE, kernel, iterations=2)

# Find Largest Contour
contours, _ = cv2.findContours(fgmask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
largest = max(contours, key=cv2.contourArea)

# Motion Consistency Check
if distance < MAX_JUMP_DIST:  # 100 pixels
    velocity = (1 - SMOOTH_ALPHA) * velocity + SMOOTH_ALPHA * (candidate - last_pos)
    use_detection = True
else:
    # Predict position instead
    predicted_pos = last_pos + velocity
```

**Parameters:**
- **Min Area**: 100 pixels² (~10×10 objects)
- **Max Jump Distance**: 100 pixels between frames
- **Max Misses**: 15 frames before reset
- **Velocity Smoothing**: α = 0.5
- **MOG2 History**: 500 frames
- **MOG2 Variance**: 25

**Detection States:**
- **DETECTED** (Green): Actual motion detected via background subtraction
- **PREDICTED** (Blue): Position estimated using velocity when detection fails

**Workflow:**
1. Auto-detect generates proposals
2. Review detections by scrubbing timeline
3. Delete unstable frame ranges
4. Accept clean detections
5. Refine with manual adjustments or tracking

**Pros:**
- Fast initial annotation (processes ~5-10 fps)
- Works well for moving objects in static scenes
- Handles temporary occlusions via prediction
- Non-destructive (proposals don't affect originals)


**Tuning Tips:**
- Increase `minArea` to filter out small noise
- Increase `maxJumpDistance` for fast-moving objects
- Increase `maxMisses` to track through longer occlusions
- Adjust `varThreshold` (lower = more sensitive to motion)

---

### Mode 3: Vision Tracking
**Best for:** Extending manual annotations, stable tracking, precise frame-to-frame tracking

**Algorithm Details:**
Uses Apple's Vision framework:

```swift
let request = VNTrackObjectRequest(detectedObjectObservation: initialBox)
request.trackingLevel = .accurate

// Image Enhancement Pipeline
1. Contrast boost (1.5x)
2. Unsharp masking (radius=2.5, intensity=0.5)

// Process each frame
try seqHandler.perform([request], on: cgImage)
```

**Workflow:**
1. Draw initial box on current frame
2. Click **"Track Forward"** or **"Track Backward"**
3. Vision tracks object through subsequent frames
4. Review and adjust as needed
5. Use **"Trim After/Before"** to clean up errors

**Pros:**
- Very accurate frame-to-frame tracking
- Handles rotation, scale changes
- Bidirectional (forward and backward)
- Works with enhanced image preprocessing
- Apple's ML-based tracker

**Cons:**
- Requires manual initialization (one box per object)
- Can drift over long sequences
- Slower than auto-detection for initial proposals
- May fail on fast motion or full occlusions

---

## Typical Workflows

### Workflow A: Completely New Video (Fastest)
1. Load video
2. **Auto-Detect** (Mode 2) → Full video
3. Review proposals → Delete bad ranges → Accept
4. Export COCO

---

### Workflow B: Refinement Workflow
1. Load video
2. **Auto-Detect** (Mode 2) → Generate proposals
3. Accept proposal
4. Manual adjustments on key frames
5. **Vision Track** (Mode 3) → Extend/refine
6. Export COCO


---

### Workflow C: Manual Precision Workflow
1. Load video
2. Add object manually
3. Draw box on frame 0
4. **Vision Track Forward** to frame 50
5. Adjust box on frame 50
6. **Vision Track Forward** to frame 100
7. Repeat
8. Export COCO

---

## Export Format (COCO)

```json
{
  "info": {
    "description": "Video annotations from VidLabel",
    "version": "1.0",
    "year": 2025,
    "contributor": "VidLabel",
    "date_created": "2025-10-22T20:00:00Z"
  },
  "images": [
    {
      "id": 1,
      "width": 1920,
      "height": 1080,
      "file_name": "video_frame_000000.jpg",
      "frame_number": 0
    }
  ],
  "annotations": [
    {
      "id": 1,
      "image_id": 1,
      "category_id": 1,
      "bbox": [150.0, 200.0, 80.0, 120.0],
      "area": 9600.0,
      "iscrowd": 0
    }
  ],
  "categories": [
    {
      "id": 1,
      "name": "object",
      "supercategory": "object"
    }
  ]
}
```

**Bbox Format:** `[x, y, width, height]` in pixels (top-left origin)

---

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| **Space** | Play/Pause video |
| **←** | Previous frame |
| **→** | Next frame |
| **⌫** (Delete) | Delete annotation on current frame |

--

---

## Technical Architecture

### Core Components

**SwiftUI Views:**
- `ContentView.swift` - Main application layout
- `VideoPlayerView.swift` - AVPlayer wrapper
- `DrawingOverlayView.swift` - Annotation rendering
- `AutoDetectPanelView.swift` - Detection controls
- `ObjectRowView.swift` - Object list item

**ViewModels:**
- `VideoPlayerViewModel.swift` - Video playback state
- `AnnotationViewModel.swift` - Annotation management

**Tracking Engines:**
- `MotionDetectionManager.swift` - OpenCV bridge for auto-detection
- `MotionDetector.mm` - Objective-C++ OpenCV implementation
- `TrackingManager.swift` - Apple Vision framework wrapper

**Data Models:**
- `BoundingBox` - Normalized coordinates (0.0-1.0)
- `TrackedObject` - Object with frame→bbox mapping
- `DetectionProposal` - Auto-detection results pending review

**Export:**
- `COCOExporter.swift` - COCO JSON format export

### Dependencies
- **Apple Frameworks**: SwiftUI, AVFoundation, Vision, CoreImage
- **OpenCV 4.12.0**: Background subtraction, morphological operations

---

## Configuration Files

- `OpenCV.xcconfig` - Xcode build configuration for OpenCV
- `VidLabel-Bridging-Header.h` - Objective-C++ to Swift bridge


---

**Frameworks:**
- Apple Vision Framework
- OpenCV 4.12.0
- SwiftUI / AVFoundation

---

## License
 
MIT

---

## Version History

**v1.0.0** (October 2025)
- Initial release
- Manual annotation mode
- Auto-detection with Mode 2 (Motion Consistency)
- Vision tracking integration
- COCO export format
- Proposal refinement tools
