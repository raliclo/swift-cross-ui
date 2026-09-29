// A HiDPI virtual display for as long as this process lives: `vdisplay <seconds>`.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
@interface CGVirtualDisplayDescriptor : NSObject
@property (retain) dispatch_queue_t queue;
@property (retain) NSString *name;
@property unsigned int maxPixelsHigh;
@property unsigned int maxPixelsWide;
@property CGSize sizeInMillimeters;
@property unsigned int productID;
@property unsigned int vendorID;
@property unsigned int serialNum;
@property (copy) void (^terminationHandler)(id, id);
@end
@interface CGVirtualDisplayMode : NSObject
- (instancetype)initWithWidth:(unsigned int)width height:(unsigned int)height refreshRate:(double)refreshRate;
@end
@interface CGVirtualDisplaySettings : NSObject
@property (retain) NSArray *modes;
@property unsigned int hiDPI;
@end
@interface CGVirtualDisplay : NSObject
- (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)settings;
@property (readonly) CGDirectDisplayID displayID;
@end
int main(int argc, char **argv) {
    @autoreleasepool {
        double seconds = argc > 1 ? atof(argv[1]) : 60;
        CGVirtualDisplayDescriptor *d = [CGVirtualDisplayDescriptor new];
        d.queue = dispatch_get_main_queue();
        d.name = @"P42 HiDPI";
        d.maxPixelsWide = 1920; d.maxPixelsHigh = 1080;
        d.sizeInMillimeters = CGSizeMake(300, 170);
        d.productID = 0x4242; d.vendorID = 0x4242; d.serialNum = 42;
        d.terminationHandler = ^(id a, id b) {};
        CGVirtualDisplay *display = [[CGVirtualDisplay alloc] initWithDescriptor:d];
        CGVirtualDisplaySettings *s = [CGVirtualDisplaySettings new];
        s.hiDPI = 1;
        s.modes = @[[[CGVirtualDisplayMode alloc] initWithWidth:960 height:540 refreshRate:60]];
        BOOL ok = [display applySettings:s];
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.5]];
        CGDirectDisplayID id_ = display.displayID;
        CGRect b = CGDisplayBounds(id_);
        CGDisplayModeRef m = CGDisplayCopyDisplayMode(id_);
        printf("applied=%d id=%u bounds=%.0f,%.0f %.0fx%.0f px=%zux%zu\n", ok, id_, b.origin.x, b.origin.y,
               b.size.width, b.size.height, m ? CGDisplayModeGetPixelWidth(m) : 0, m ? CGDisplayModeGetPixelHeight(m) : 0);
        fflush(stdout);
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
        (void)display;
    }
    return 0;
}
