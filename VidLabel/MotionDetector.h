//
//  MotionDetector.h
//  VidLabel
//
//  Objective-C++ bridge for OpenCV motion detection
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

@interface MotionDetectionResult : NSObject
@property (nonatomic, assign) CGRect boundingBox;
@property (nonatomic, assign) CGPoint center;
@property (nonatomic, assign) BOOL isDetected; // YES = detected, NO = predicted
@property (nonatomic, assign) BOOL isValid;
@end

@interface MotionDetector : NSObject

// Configuration
@property (nonatomic, assign) double minArea;           // Default: 400
@property (nonatomic, assign) double maxJumpDistance;   // Default: 100
@property (nonatomic, assign) int maxMisses;            // Default: 15
@property (nonatomic, assign) double smoothAlpha;       // Default: 0.5

- (instancetype)initWithHistory:(int)history varThreshold:(double)varThreshold;
- (void)reset;
- (MotionDetectionResult *)processFrame:(CGImageRef)frame;

@end

NS_ASSUME_NONNULL_END
