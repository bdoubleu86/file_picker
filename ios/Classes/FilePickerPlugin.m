#import "FilePickerPlugin.h"
#import "FileUtils.h"
#import <Photos/Photos.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import <GLKit/GLKit.h>

@interface FilePickerPlugin()
@property (nonatomic) FlutterResult result;
@property (nonatomic) UIViewController *viewController;
@property (nonatomic) UIDocumentPickerViewController *pickerController;
@property (nonatomic) UIDocumentInteractionController *interactionController;
@property (nonatomic) NSString * fileType;
@end

@implementation FilePickerPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
    
    FlutterMethodChannel* channel = [FlutterMethodChannel
                                     methodChannelWithName:@"file_picker"
                                     binaryMessenger:[registrar messenger]];
    
    UIViewController *viewController = [UIApplication sharedApplication].delegate.window.rootViewController;
    FilePickerPlugin* instance = [[FilePickerPlugin alloc] initWithViewController:viewController];
    
    [registrar addMethodCallDelegate:instance channel:channel];
}


- (instancetype)initWithViewController:(UIViewController *)viewController {
    self = [super init];
    if(self) {
        self.viewController = viewController;
    }
    
    return self;
}

- (void)initPicker {
    
    self.pickerController = [[UIDocumentPickerViewController alloc]
                             initWithDocumentTypes:@[self.fileType]
                             inMode:UIDocumentPickerModeImport];
    
    self.pickerController.modalPresentationStyle = UIModalPresentationCurrentContext;
    self.pickerController.delegate = self;
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
    if (_result) {
        _result([FlutterError errorWithCode:@"multiple_request"
                                    message:@"Cancelled by a second request"
                                    details:nil]);
        _result = nil;
    }
    
    _result = result;
    
    
    if([call.method isEqualToString:@"VIDEO"]) {
        [self resolvePickVideo];
    }
    else {
        self.fileType = [FileUtils resolveType:call.method];
        
        if(self.fileType == nil){
            result(FlutterMethodNotImplemented);
        } else {
            [self initPicker];
            [_viewController presentViewController:self.pickerController animated:YES completion:^{
                if (@available(iOS 11.0, *)) {
                    self.pickerController.allowsMultipleSelection = NO;
                }
            }];
            
        }
    }
    
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller
didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls{
    
    [self.pickerController dismissViewControllerAnimated:YES completion:nil];
    _result([FileUtils resolvePath:urls]);
}


// VideoPicker delegate
- (void) resolvePickVideo{
    UIImagePickerController *videoPicker = [[UIImagePickerController alloc] init];
    videoPicker.delegate = self;
    videoPicker.modalPresentationStyle = UIModalPresentationCurrentContext;
    videoPicker.mediaTypes = @[(NSString*)kUTTypeMovie, (NSString*)kUTTypeAVIMovie, (NSString*)kUTTypeVideo, (NSString*)kUTTypeMPEG4];
    videoPicker.videoQuality = UIImagePickerControllerQualityTypeMedium;
    
    [self.viewController presentViewController:videoPicker animated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info {
    NSURL *videoURL = [info objectForKey:UIImagePickerControllerMediaURL];

    AVURLAsset *asset = [[AVURLAsset alloc] initWithURL:videoURL options:nil];
    AVAssetImageGenerator *generator = [[AVAssetImageGenerator alloc] initWithAsset:asset];
    generator.appliesPreferredTrackTransform = YES;

    NSError *err = NULL;
    CMTime time = CMTimeMake(1, 2);
    CGImageRef image = [generator copyCGImageAtTime:time actualTime:NULL error:&err];

    AVAssetTrack *assetTrack = [[asset tracksWithMediaType:AVMediaTypeVideo]objectAtIndex:0];
    float width = assetTrack.naturalSize.width;
    float height = assetTrack.naturalSize.height;
    // Rotate the video by using a videoComposition and the preferredTransform
    CGAffineTransform _preferredTransform = [self fixTransform:assetTrack];
    NSInteger rotationDegrees = (NSInteger)round(radiansToDegrees(atan2(_preferredTransform.b, _preferredTransform.a)));
    if (rotationDegrees == 90 || rotationDegrees == 270) {
        width = assetTrack.naturalSize.height;
        height = assetTrack.naturalSize.width;
    }
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *basePath = ([paths count] > 0) ? paths[0] : nil;
    NSData *binaryImageData = UIImagePNGRepresentation([UIImage imageWithCGImage:image]);
    NSString *thumbnailFile = [basePath stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
    [binaryImageData writeToFile:thumbnailFile atomically:YES];

    CMTime duration = CMTimeMultiplyByRatio(asset.duration, 1000, 1);
    long seconds = duration.value / duration.timescale;
    _result(@{
              @"path": [videoURL path],
              @"thumbnail": thumbnailFile,
              @"duration": @(seconds),
              @"width": @(width),
              @"height": @(height)
              });
    [picker dismissViewControllerAnimated:YES completion:NULL];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    _result = nil;
    [controller dismissViewControllerAnimated:YES completion:NULL];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    _result = nil;
    [picker dismissViewControllerAnimated:YES completion:NULL];
}

static inline CGFloat radiansToDegrees(CGFloat radians) {
    // Input range [-pi, pi] or [-180, 180]
    CGFloat degrees = GLKMathRadiansToDegrees(radians);
    if (degrees < 0) {
        // Convert -90 to 270 and -180 to 180
        return degrees + 360;
    }
    // Output degrees in between [0, 360[
    return degrees;
};

- (CGAffineTransform)fixTransform:(AVAssetTrack*)videoTrack {
    CGAffineTransform transform = videoTrack.preferredTransform;
    // TODO(@recastrodiaz): why do we need to do this? Why is the preferredTransform incorrect?
    // At least 2 user videos show a black screen when in portrait mode if we directly use the
    // videoTrack.preferredTransform Setting tx to the height of the video instead of 0, properly
    // displays the video https://github.com/flutter/flutter/issues/17606#issuecomment-413473181
    if (transform.tx == 0 && transform.ty == 0) {
        NSInteger rotationDegrees = (NSInteger)round(radiansToDegrees(atan2(transform.b, transform.a)));
        NSLog(@"TX and TY are 0. Rotation: %ld. Natural width,height: %f, %f", rotationDegrees,
              videoTrack.naturalSize.width, videoTrack.naturalSize.height);
        if (rotationDegrees == 90) {
            NSLog(@"Setting transform tx");
            transform.tx = videoTrack.naturalSize.height;
            transform.ty = 0;
        } else if (rotationDegrees == 270) {
            NSLog(@"Setting transform ty");
            transform.tx = 0;
            transform.ty = videoTrack.naturalSize.width;
        }
    }
    return transform;
}

@end
