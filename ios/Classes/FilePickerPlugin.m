#import "FilePickerPlugin.h"
#import "FileUtils.h"
#import <Photos/Photos.h>
#import <MobileCoreServices/MobileCoreServices.h>

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
    videoPicker.videoQuality = UIImagePickerControllerQualityTypeHigh;
    
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

    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *basePath = ([paths count] > 0) ? paths[0] : nil;
    NSData *binaryImageData = UIImagePNGRepresentation([UIImage imageWithCGImage:image]);
    NSString *thumbnailFile = [basePath stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
    [binaryImageData writeToFile:thumbnailFile atomically:YES];

    AVURLAsset *sourceAsset = [AVURLAsset URLAssetWithURL:videoURL options:nil];
    CMTime duration = sourceAsset.duration;
    long seconds = duration.value / duration.timescale;
    
    _result(@{@"path": [videoURL path], @"thumbnail": thumbnailFile, @"duration": @(seconds * 1000)});
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

@end
