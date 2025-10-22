//
//  MotionDetector.mm
//  VidLabel
//
//  OpenCV implementation of track_motion2.py algorithm
//

#import "MotionDetector.h"

// Only include specific OpenCV headers we need (avoid conflicts with macOS)
#import <opencv2/core.hpp>
#import <opencv2/imgproc.hpp>
#import <opencv2/video.hpp>
#import <opencv2/video/background_segm.hpp>

// Use cv namespace prefix to avoid conflicts with macOS frameworks

@implementation MotionDetectionResult
@end

@interface MotionDetector() {
    cv::Ptr<cv::BackgroundSubtractorMOG2> fgbg;
    cv::Point2f lastPos;
    cv::Point2f velocity;
    int misses;
    cv::Rect lastBBox;
    BOOL hasLastPos;
}
@end

@implementation MotionDetector

- (instancetype)initWithHistory:(int)history varThreshold:(double)varThreshold {
    self = [super init];
    if (self) {
        // Create MOG2 background subtractor (same as Python)
        fgbg = cv::createBackgroundSubtractorMOG2(history, varThreshold, true);

        // Default configuration (matching track_motion2.py)
        _minArea = 400.0;
        _maxJumpDistance = 100.0;
        _maxMisses = 15;
        _smoothAlpha = 0.5;

        // Initialize state
        lastPos = cv::Point2f(0, 0);
        velocity = cv::Point2f(0, 0);
        misses = 0;
        lastBBox = cv::Rect(0, 0, 0, 0);
        hasLastPos = NO;
    }
    return self;
}

- (void)reset {
    hasLastPos = NO;
    misses = 0;
    velocity = cv::Point2f(0, 0);
    lastPos = cv::Point2f(0, 0);
    lastBBox = cv::Rect(0, 0, 0, 0);
}

- (MotionDetectionResult *)processFrame:(CGImageRef)frame {
    MotionDetectionResult *result = [[MotionDetectionResult alloc] init];
    result.isValid = NO;
    result.isDetected = NO;

    // Convert CGImage to cv::Mat
    cv::Mat cvFrame = [self matFromCGImage:frame];
    if (cvFrame.empty()) {
        return result;
    }

    // Convert to grayscale (line 34-35 in Python)
    cv::Mat gray;
    cv::cvtColor(cvFrame, gray, cv::COLOR_BGR2GRAY);

    // Gaussian blur (line 35)
    cv::GaussianBlur(gray, gray, cv::Size(5, 5), 0);

    // Background subtraction (line 36)
    cv::Mat fgmask;
    fgbg->apply(gray, fgmask);

    // Morphological operations (lines 38-40)
    cv::Mat kernel = cv::getStructuringElement(cv::MORPH_ELLIPSE, cv::Size(5, 5));
    cv::morphologyEx(fgmask, fgmask, cv::MORPH_OPEN, kernel);
    cv::morphologyEx(fgmask, fgmask, cv::MORPH_DILATE, kernel, cv::Point(-1, -1), 2);

    // Find contours (line 42)
    std::vector<std::vector<cv::Point>> contours;
    cv::findContours(fgmask, contours, cv::RETR_EXTERNAL, cv::CHAIN_APPROX_SIMPLE);

    // Find largest contour (lines 44-51)
    cv::Point2f candidate;
    cv::Rect bbox;
    BOOL hasCandidate = NO;

    if (!contours.empty()) {
        auto largest = std::max_element(contours.begin(), contours.end(),
            [](const std::vector<cv::Point>& a, const std::vector<cv::Point>& b) {
                return cv::contourArea(a) < cv::contourArea(b);
            });

        if (cv::contourArea(*largest) > self.minArea) {
            bbox = cv::boundingRect(*largest);
            candidate = cv::Point2f(bbox.x + bbox.width/2.0f, bbox.y + bbox.height/2.0f);
            hasCandidate = YES;
        }
    }

    // Motion consistency check (lines 53-83)
    BOOL useDetection = NO;

    if (hasCandidate) {
        if (!hasLastPos) {
            // First detection (lines 56-60)
            lastPos = candidate;
            lastBBox = bbox;
            misses = 0;
            useDetection = YES;
            hasLastPos = YES;
        } else {
            // Check motion consistency (lines 62-72)
            float dist = cv::norm(candidate - lastPos);
            if (dist < self.maxJumpDistance) {
                // Valid detection (lines 63-68)
                velocity.x = (1 - self.smoothAlpha) * velocity.x + self.smoothAlpha * (candidate.x - lastPos.x);
                velocity.y = (1 - self.smoothAlpha) * velocity.y + self.smoothAlpha * (candidate.y - lastPos.y);
                lastPos = candidate;
                lastBBox = bbox;
                misses = 0;
                useDetection = YES;
            } else {
                // Jump too large: predict (lines 70-72)
                lastPos.x += velocity.x;
                lastPos.y += velocity.y;
                misses++;
            }
        }
    } else if (hasLastPos) {
        // No detection: predict position (lines 73-76)
        lastPos.x += velocity.x;
        lastPos.y += velocity.y;
        misses++;
    }

    // Reset if too many misses (lines 78-83)
    if (misses > self.maxMisses) {
        [self reset];
        return result;
    }

    // Return result if we have a valid position (lines 86-102)
    if (hasLastPos) {
        result.isValid = YES;
        result.center = CGPointMake(lastPos.x, lastPos.y);
        result.boundingBox = CGRectMake(lastBBox.x, lastBBox.y, lastBBox.width, lastBBox.height);
        result.isDetected = useDetection;
    }

    return result;
}

// Helper: Convert CGImage to cv::Mat
- (cv::Mat)matFromCGImage:(CGImageRef)image {
    size_t width = CGImageGetWidth(image);
    size_t height = CGImageGetHeight(image);

    CGColorSpaceRef colorSpace = CGImageGetColorSpace(image);

    cv::Mat mat((int)height, (int)width, CV_8UC4);

    CGContextRef context = CGBitmapContextCreate(
        mat.data,
        width,
        height,
        8,
        mat.step[0],
        colorSpace,
        kCGImageAlphaNoneSkipLast | kCGBitmapByteOrderDefault
    );

    if (!context) {
        return cv::Mat();
    }

    CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
    CGContextRelease(context);

    cv::Mat bgr;
    cv::cvtColor(mat, bgr, cv::COLOR_RGBA2BGR);

    return bgr;
}

@end
