#import "FilePickerPlugin.h"
#import "FileUtils.h"
#import "ImageUtils.h"

@interface FilePickerPlugin() <UIImagePickerControllerDelegate, MPMediaPickerControllerDelegate>
@property (nonatomic) FlutterResult result;
@property (nonatomic) UIViewController *viewController;
@property (nonatomic) UIImagePickerController *galleryPickerController;
@property (nonatomic) UIDocumentPickerViewController *documentPickerController;
@property (nonatomic) UIDocumentInteractionController *interactionController;
@property (nonatomic) MPMediaPickerController *audioPickerController;
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

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
    if (_result) {
        result([FlutterError errorWithCode:@"multiple_request"
                                    message:@"Cancelled by a second request"
                                    details:nil]);
        _result = nil;
        return;
    }
    
    _result = result;
    BOOL isMultiplePick = [call.arguments boolValue];
    if(isMultiplePick || [call.method isEqualToString:@"ANY"] || [call.method containsString:@"__CUSTOM"]) {
        self.fileType = [FileUtils resolveType:call.method];
        if(self.fileType == nil) {
            _result([FlutterError errorWithCode:@"Unsupported file extension"
                                        message:@"Make sure that you are only using the extension without the dot, (ie., jpg instead of .jpg). This could also have happened because you are using an unsupported file extension.  If the problem persists, you may want to consider using FileType.ALL instead."
                                        details:nil]);
            _result = nil;
        } else if(self.fileType != nil) {
            [self resolvePickDocumentWithMultipleSelection:isMultiplePick];
        }
    } else if([call.method isEqualToString:@"VIDEO"]) {
        [self resolvePickVideo];
    } else if([call.method isEqualToString:@"AUDIO"]) {
        [self resolvePickAudio];
    } else if([call.method isEqualToString:@"IMAGE"]) {
        [self resolvePickImage];
    } else {
        result(FlutterMethodNotImplemented);
        _result = nil;
    }
    
}

#pragma mark - Resolvers

- (void)resolvePickDocumentWithMultipleSelection:(BOOL)allowsMultipleSelection {
    
    @try{
        self.documentPickerController = [[UIDocumentPickerViewController alloc]
                             initWithDocumentTypes:@[self.fileType]
                             inMode:UIDocumentPickerModeImport];
    } @catch (NSException * e) {
       Log(@"Couldn't launch documents file picker. Probably due to iOS version being below 11.0 and not having the iCloud entitlement. If so, just make sure to enable it for your app in Xcode. Exception was: %@", e);
        _result = nil;
        return;
    }
    
    if (@available(iOS 11.0, *)) {
        self.documentPickerController.allowsMultipleSelection = allowsMultipleSelection;
    } else if(allowsMultipleSelection) {
       Log(@"Multiple file selection is only supported on iOS 11 and above. Single selection will be used.");
    }
    
    self.documentPickerController.delegate = self;
    self.documentPickerController.modalPresentationStyle = UIModalPresentationCurrentContext;
    self.galleryPickerController.allowsEditing = NO;
    
    [_viewController presentViewController:self.documentPickerController animated:YES completion:nil];
}

- (void) resolvePickImage {
    
    self.galleryPickerController = [[UIImagePickerController alloc] init];
    self.galleryPickerController.delegate = self;
    self.galleryPickerController.modalPresentationStyle = UIModalPresentationCurrentContext;
    self.galleryPickerController.mediaTypes = @[(NSString *)kUTTypeImage];
    self.galleryPickerController.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    
    [_viewController presentViewController:self.galleryPickerController animated:YES completion:nil];
}

- (void) resolvePickAudio {
    
    self.audioPickerController = [[MPMediaPickerController alloc] initWithMediaTypes:MPMediaTypeAnyAudio];
    self.audioPickerController.delegate = self;
    self.audioPickerController.showsCloudItems = NO;
    self.audioPickerController.allowsPickingMultipleItems = NO;
    self.audioPickerController.modalPresentationStyle = UIModalPresentationCurrentContext;
    
    [self.viewController presentViewController:self.audioPickerController animated:YES completion:nil];
}

- (void) resolvePickVideo {
    
    self.galleryPickerController = [[UIImagePickerController alloc] init];
    self.galleryPickerController.delegate = self;
    self.galleryPickerController.modalPresentationStyle = UIModalPresentationCurrentContext;
    self.galleryPickerController.mediaTypes = @[(NSString*)kUTTypeMovie, (NSString*)kUTTypeAVIMovie, (NSString*)kUTTypeVideo, (NSString*)kUTTypeMPEG4];
    self.galleryPickerController.videoQuality = UIImagePickerControllerQualityTypeHigh;
    
    [self.viewController presentViewController:self.galleryPickerController animated:YES completion:nil];
}

#pragma mark - Delegates

// DocumentPicker delegate - iOS 10 only
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentAtURL:(NSURL *)url{
    [self.documentPickerController dismissViewControllerAnimated:YES completion:nil];
    NSString * path = (NSString *)[url path];
    _result(path);
    _result = nil;
}

// DocumentPicker delegate
- (void)documentPicker:(UIDocumentPickerViewController *)controller
didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls{
    
    [self.documentPickerController dismissViewControllerAnimated:YES completion:nil];
    NSArray * result = [FileUtils resolvePath:urls];
    
    if([result count] > 1) {
        _result(result);
    } else {
       _result([result objectAtIndex:0]);
    }
    _result = nil;
    
}


// ImagePicker delegate
- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info {
    
    NSURL *pickedVideoUrl = [info objectForKey:UIImagePickerControllerMediaURL];
    NSURL *pickedImageUrl;
    
    if (@available(iOS 11.0, *)) {
       pickedImageUrl = [info objectForKey:UIImagePickerControllerImageURL];
    } else {
       UIImage *pickedImage  = [info objectForKey:UIImagePickerControllerEditedImage];
    
        if(pickedImage == nil) {
            pickedImage = [info objectForKey:UIImagePickerControllerOriginalImage];
        }
        pickedImageUrl = [ImageUtils saveTmpImage:pickedImage];
    }
    
    [picker dismissViewControllerAnimated:YES completion:NULL];

    if(pickedImageUrl == nil && pickedVideoUrl == nil) {
        _result([FlutterError errorWithCode:@"file_picker_error"
                                    message:@"Temporary file could not be created"
                                    details:nil]);
        _result = nil;
        return;
    }
    
    _result([pickedVideoUrl != nil ? pickedVideoUrl : pickedImageUrl path]);
    _result = nil;
}


// AudioPicker delegate
- (void)mediaPicker: (MPMediaPickerController *)mediaPicker didPickMediaItems:(MPMediaItemCollection *)mediaItemCollection
{
    Log(@"Debug Media Picker8");
    [mediaPicker dismissViewControllerAnimated:YES completion:NULL];
    MPMediaItem *mediaItem = [[mediaItemCollection items] objectAtIndex:0];
    //get the name of the file.
    NSString *songTitle = [mediaItem valueForProperty: MPMediaItemPropertyTitle];
    
    //convert MPMediaItem to AVURLAsset.
    AVURLAsset *sset = [AVURLAsset assetWithURL:[mediaItem valueForProperty:MPMediaItemPropertyAssetURL]];
    
    if(sset == nil) {
        Log(@"Couldn't retrieve the audio file path, either is not locally downloaded or the file is DRM protected.");
        _result(nil);
        _result = nil;
        return;
    }
    
    //get the extension of the file.
    NSString *fileType = [[[[sset.URL absoluteString] componentsSeparatedByString:@"?"] objectAtIndex:0] pathExtension];
    
    //init export, here you must set "presentName" argument to "AVAssetExportPresetPassthrough". If not, you will can't export mp3 correct.
    AVAssetExportSession *export = [[AVAssetExportSession alloc] initWithAsset:sset presetName:AVAssetExportPresetPassthrough];
    
    NSLog(@"export.supportedFileTypes : %@",export.supportedFileTypes);
    //export to mov format.
    export.outputFileType = @"com.apple.quicktime-movie";
    
    export.shouldOptimizeForNetworkUse = YES;
    
    NSString *extension = (__bridge NSString *)UTTypeCopyPreferredTagWithClass((__bridge CFStringRef)export.outputFileType, kUTTagClassFilenameExtension);
    
    NSLog(@"extension %@",extension);
    NSString *path = [NSHomeDirectory() stringByAppendingFormat:@"/Documents/%@.%@",songTitle,extension];
    
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    
    NSURL *outputURL = [NSURL fileURLWithPath:path];
    export.outputURL = outputURL;
    [export exportAsynchronouslyWithCompletionHandler:^{
        
        if (export.status == AVAssetExportSessionStatusCompleted)
        {
                        Log(@"Success");
            NSURL* saveDirectory = [outputURL URLByDeletingLastPathComponent];
            Log(@"saveDirectory: %@", [saveDirectory absoluteString]);
                        NSArray* dirs = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[ saveDirectory absoluteString]
                            error:NULL];
            Log(@"fileCount: %d", [dirs count]);
                        [dirs enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
                            NSString *filename = (NSString *)obj;
                            Log(@"file: %@", filename);
                        }];
            //then rename mov format to the original format.
            NSFileManager *manage = [NSFileManager defaultManager];
            NSString *mp3Path = [NSHomeDirectory() stringByAppendingFormat:@"/Documents/%@.%@",songTitle,fileType];
            
            NSError *error = nil;
            
            [[NSFileManager defaultManager] removeItemAtPath:mp3Path error:nil];
            [manage moveItemAtPath:path toPath:mp3Path error:&error];
            
            Log(@"error %@",error);
            
            _result(mp3Path);
            _result = nil;
            
        }
        else
        {
            NSLog(@"%@",export.error);
            _result(nil);
            _result = nil;
        }
        
    }];
//    NSURL *assetURL = mediaItem.assetURL;
//    NSFileManager *fileManager = [NSFileManager defaultManager];
//    NSURL *documentURL = [fileManager URLForDirectory:NSDocumentDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:true error:nil];
//    Log(@"assetURL: %@", [assetURL absoluteString]);
//    Log(@"documentURL: %@", [documentURL absoluteString]);
//
//    NSString * extension = @"mov";//[assetURL pathExtension];
//    Log(@"extension: %@", extension);
//
//    NSURL *tempURL = [ documentURL URLByAppendingPathComponent:@"temp" isDirectory:true ];
//    Log(@"tempURL: %@", [tempURL absoluteString]);
//
//    NSURL *fileURL = [ tempURL URLByAppendingPathComponent:@"export" ];
//    fileURL = [ fileURL URLByAppendingPathExtension:extension ];
//    Log(@"fileURL: %@", [fileURL absoluteString]);
//
//    AVAsset *asset = [AVAsset assetWithURL:fileURL];
//    //AVAssetExportSession *exportSession = [AVAssetExportSession exportSessionWithAsset:asset];
//    AVAssetExportSession *exportSession
//    = [AVAssetExportSession exportSessionWithAsset:asset presetName:AVAssetExportPresetPassthrough];
//    Log(@"exportSession.supportedFileTypes : %@",exportSession.supportedFileTypes);
//    exportSession.shouldOptimizeForNetworkUse = YES;
//    exportSession.outputFileType = @"com.apple.quicktime-movie";
////    exportSession.metadata = asset.commonMetadata;
//    NSURL *exportURL = [[[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:@"export"] URLByAppendingPathExtension:@"mov"];
//
//    exportSession.outputURL = exportURL;
////    exportSession.outputURL = fileURL;
//
//    Log(@"processing asset...: %@", exportSession);
//    [exportSession exportAsynchronouslyWithCompletionHandler:^{
//        if (exportSession.status == AVAssetExportSessionStatusCompleted)
//        {
//            Log(@"Success");
//            NSArray* dirs = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[tempURL absoluteString]
//                                                                                error:NULL];
//            NSMutableArray *mp3Files = [[NSMutableArray alloc] init];
//            [dirs enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
//                NSString *filename = (NSString *)obj;
//                NSString *extension = [[filename pathExtension] lowercaseString];
//                Log(@"file: %@", filename);
////                if ([extension isEqualToString:@"mp3"]) {
////                    [mp3Files addObject:[sourcePath stringByAppendingPathComponent:filename]];
////                }
//            }];
//            //then rename mov format to the original format.
////            NSFileManager *manage = [NSFileManager defaultManager];
////
////            NSString *mp3Path = [NSHomeDirectory() stringByAppendingFormat:@"/Documents/%@.%@",songTitle,fileType];
////
////            NSError *error = nil;
////
////            [manage moveItemAtPath:path toPath:mp3Path error:&error];
////
////            NSLog(@"error %@",error);
//
//        }
//        else
//        {
//            Log(@"%@",exportSession.error);
//        }
//    }];
//
}

#pragma mark - Actions canceled

- (void)mediaPickerDidCancel:(MPMediaPickerController *)controller {
    Log(@"FilePicker canceled");
    _result(nil);
    _result = nil;
    [controller dismissViewControllerAnimated:YES completion:NULL];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    Log(@"FilePicker canceled");
    _result(nil);
    _result = nil;
    [controller dismissViewControllerAnimated:YES completion:NULL];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    Log(@"FilePicker canceled");
    _result(nil);
    _result = nil;
    [picker dismissViewControllerAnimated:YES completion:NULL];
}

@end
