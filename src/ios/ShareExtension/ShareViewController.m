//
//  ShareViewController.m
//  OpenWith - Share Extension
//

//
// The MIT License (MIT)
//
// Copyright (c) 2017 Jean-Christophe Hoelt
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//

#import <UIKit/UIKit.h>
#import <Social/Social.h>
#import <Photos/Photos.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import "ShareViewController.h"

@interface ShareViewController : UIViewController {
    int _verbosityLevel;
    NSUserDefaults *_userDefaults;
    NSString *_backURL;
}
@property (nonatomic) int verbosityLevel;
@property (nonatomic,retain) NSUserDefaults *userDefaults;
@property (nonatomic,retain) NSString *backURL;
@end

/*
* Constants
*/
#define VERBOSITY_DEBUG  0
#define VERBOSITY_INFO  10
#define VERBOSITY_WARN  20
#define VERBOSITY_ERROR 30

@implementation ShareViewController

@synthesize verbosityLevel = _verbosityLevel;
@synthesize userDefaults = _userDefaults;
@synthesize backURL = _backURL;

- (void) log:(int)level message:(NSString*)message {
    if (level >= self.verbosityLevel) {
        NSLog(@"[ShareViewController.m]%@", message);
    }
}

- (void) debug:(NSString*)message { [self log:VERBOSITY_DEBUG message:message]; }
- (void) info:(NSString*)message { [self log:VERBOSITY_INFO message:message]; }
- (void) warn:(NSString*)message { [self log:VERBOSITY_WARN message:message]; }
- (void) error:(NSString*)message { [self log:VERBOSITY_ERROR message:message]; }

-(void) viewDidLoad {
    [super viewDidLoad];
    printf("did load");
    [self debug:@"[viewDidLoad]"];
    [self submit];
}

- (void) setup {
    self.userDefaults = [[NSUserDefaults alloc] initWithSuiteName:SHAREEXT_GROUP_IDENTIFIER];
    self.verbosityLevel = [self.userDefaults integerForKey:@"verbosityLevel"];
    [self debug:@"[setup]"];
}

- (BOOL) isContentValid {
    return YES;
}

- (void) openURL:(nonnull NSURL *)url {
    SEL selector = NSSelectorFromString(@"openURL:options:completionHandler:");
    UIResponder* responder = self;
    while ((responder = [responder nextResponder]) != nil) {
        NSLog(@"responder = %@", responder);
        if([responder respondsToSelector:selector] == true) {
            NSMethodSignature *methodSignature = [responder methodSignatureForSelector:selector];
            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:methodSignature];
            // Arguments
            UISceneOpenExternalURLOptions * options = [[UISceneOpenExternalURLOptions alloc] init];
            options.universalLinksOnly = false;
            void (^completion)(BOOL success) = ^void(BOOL success) {
                NSLog(@"Completions block: %i", success);
            };
            [invocation setTarget: responder];
            [invocation setSelector: selector];
            [invocation setArgument: &url atIndex: 2];
            [invocation setArgument: &options atIndex:3];
            [invocation setArgument: &completion atIndex: 4];
            [invocation invoke];
            break;
        }
    }
}

- (void) submit {
    [self setup];
    [self debug:@"[submit]"];
    
    NSExtensionItem *extensionItem = (NSExtensionItem*)self.extensionContext.inputItems[0];
    
    for (NSItemProvider* itemProvider in extensionItem.attachments) {
        [self debug:[NSString stringWithFormat:@"Item provider registered types: %@", itemProvider.registeredTypeIdentifiers]];
        
        if ([itemProvider hasItemConformingToTypeIdentifier:@"com.apple.live-photo"]) {
            [self debug:@"Live Photo detected"];
            [self handleLivePhoto:itemProvider];
            return;
        }
        else if ([itemProvider hasItemConformingToTypeIdentifier:SHAREEXT_UNIFORM_TYPE_IDENTIFIER]) {
            [self debug:@"Regular image detected"];
            [self handleRegularImage:itemProvider];
            return;
        }
        else if ([itemProvider hasItemConformingToTypeIdentifier:@"public.vcard"]) {
            [self debug:@"VCard detected"];
            [self handleVCard:itemProvider];
            return;
        }
    }
    
    [self debug:@"No supported item type found"];
    [self.extensionContext completeRequestReturningItems:@[] completionHandler:nil];
}

- (void) handleRegularImage:(NSItemProvider*)itemProvider {
    [self debug:@"[handleRegularImage]"];
    
    [itemProvider loadItemForTypeIdentifier:SHAREEXT_UNIFORM_TYPE_IDENTIFIER
                                   options:nil
                           completionHandler:^(id<NSSecureCoding> item, NSError *error) {
        if (error) {
            [self error:[NSString stringWithFormat:@"Error: %@", error.localizedDescription]];
            [self.extensionContext completeRequestReturningItems:@[] completionHandler:nil];
            return;
        }
        
        if (item == nil) {
            [self error:@"Item is nil"];
            [self.extensionContext completeRequestReturningItems:@[] completionHandler:nil];
            return;
        }
        
        NSData *data = [[NSData alloc] init];
        NSObject *obj = (NSObject *)item;
        
        if ([obj isKindOfClass:[NSURL class]]) {
            NSURL *url = (NSURL *)item;
            data = [NSData dataWithContentsOfURL:url];
            [self debug:[NSString stringWithFormat:@"Loaded data from URL: %lu bytes", (unsigned long)data.length]];
        }
        else if ([obj isKindOfClass:[UIImage class]]) {
            UIImage *image = (UIImage *)item;
            data = UIImagePNGRepresentation(image);
            [self debug:[NSString stringWithFormat:@"Loaded PNG data: %lu bytes", (unsigned long)data.length]];
        }
        else {
            [self error:[NSString stringWithFormat:@"Unknown item type: %@", [obj class]]];
            [self.extensionContext completeRequestReturningItems:@[] completionHandler:nil];
            return;
        }
        
        if (data == nil || data.length == 0) {
            [self error:@"Data is empty"];
            [self.extensionContext completeRequestReturningItems:@[] completionHandler:nil];
            return;
        }
        
        NSString *suggestedName = @"image";
        if ([itemProvider respondsToSelector:NSSelectorFromString(@"suggestedName")]) {
            NSString *name = [itemProvider valueForKey:@"suggestedName"];
            if (name && [name length] > 0) {
                suggestedName = name;
            }
        }
        
        NSString *uti = SHAREEXT_UNIFORM_TYPE_IDENTIFIER;
        NSArray<NSString *> *utis = itemProvider.registeredTypeIdentifiers;
        
        if (utis && [utis count] > 0) {
            uti = utis[0];
        }
        
        [self saveSharedDataWithBytes:data
                                name:suggestedName
                                 uti:uti
                                utis:utis];
    }];
}

- (void) handleLivePhoto:(NSItemProvider*)itemProvider {
    [self debug:@"[handleLivePhoto]"];
    
  // Live Photos cannot be loaded directly as JPEG/HEIC
  // We need to load PHLivePhoto and then extract the data
    
    if (@available(iOS 9.1, *)) {
        [itemProvider loadItemForTypeIdentifier:@"com.apple.live-photo"
                                       options:nil
                               completionHandler:^(id<NSSecureCoding> item, NSError *error) {
            
            if (error) {
                [self error:[NSString stringWithFormat:@"Error loading live photo: %@", error.localizedDescription]];
                
                // Fallback: Try to load the still image
                [self debug:@"Trying fallback to load still image"];
                [self loadLivePhotoStillImage:itemProvider];
                return;
            }
            
            if (item == nil) {
                [self error:@"Live photo item is nil"];
                [self loadLivePhotoStillImage:itemProvider];
                return;
            }
            
            [self debug:[NSString stringWithFormat:@"Successfully loaded live photo item"]];
            
            // Try to extract image data from the item
            [self extractLivePhotoData:item];
        }];
    } else {
        [self loadLivePhotoStillImage:itemProvider];
    }
}

- (void) loadLivePhotoStillImage:(NSItemProvider*)itemProvider {
    [self debug:@"[loadLivePhotoStillImage]"];
    
    // Fallback: Load the thumbnail of the live photo
    // Live Photos have multiple attachments - we look for the UIImage
    // Try to load UIImage directly
    if ([itemProvider canLoadObjectOfClass:[UIImage class]]) {
        [self debug:@"Loading UIImage from live photo"];
        [itemProvider loadObjectOfClass:[UIImage class]
                       completionHandler:^(__kindof id<NSItemProviderReading> object, NSError *error) {
            if (error) {
                [self error:[NSString stringWithFormat:@"Error loading UIImage: %@", error.localizedDescription]];
                
                // Second fallback: Try NSURL
                [self loadLivePhotoFromURL:itemProvider];
                return;
            }
            
            if ([object isKindOfClass:[UIImage class]]) {
                UIImage *image = (UIImage *)object;
                [self debug:[NSString stringWithFormat:@"Got UIImage, size: %@", NSStringFromCGSize(image.size)]];
                [self processLivePhotoImage:image withName:@"livephoto.jpg"];
            }
        }];
    } else {
        [self loadLivePhotoFromURL:itemProvider];
    }
}

- (void) loadLivePhotoFromURL:(NSItemProvider*)itemProvider {
    [self debug:@"[loadLivePhotoFromURL]"];
    
    if ([itemProvider canLoadObjectOfClass:[NSURL class]]) {
        [self debug:@"Loading NSURL from live photo"];
        [itemProvider loadObjectOfClass:[NSURL class]
                           completionHandler:^(__kindof id<NSItemProviderReading> object, NSError *error) {
            if (error) {
                [self error:[NSString stringWithFormat:@"Error loading NSURL: %@", error.localizedDescription]];
                [self.extensionContext completeRequestReturningItems:@[] completionHandler:nil];
                return;
            }
            
            if ([object isKindOfClass:[NSURL class]]) {
                NSURL *url = (NSURL *)object;
                NSData *data = [NSData dataWithContentsOfURL:url];
                [self debug:[NSString stringWithFormat:@"Got data from URL: %lu bytes", (unsigned long)data.length]];
                [self processLivePhotoDataWithBytes:data andName:@"livephoto.jpg"];
            }
        }];
    } else {
        [self error:@"Cannot load live photo - no suitable type available"];
        [self.extensionContext completeRequestReturningItems:@[] completionHandler:nil];
    }
}

- (void) extractLivePhotoData:(id<NSSecureCoding>)livePhotoItem {
    [self debug:@"[extractLivePhotoData]"];
    
    // Cast to NSObject to access methods
    NSObject *obj = (NSObject *)livePhotoItem;
    
    // Try to extract the image from the live photo
    if ([obj respondsToSelector:@selector(image)]) {
        NSData *imageData = [obj performSelector:@selector(image)];
        if ([imageData isKindOfClass:[UIImage class]]) {
            UIImage *image = (UIImage *)imageData;
            [self processLivePhotoImage:image withName:@"livephoto.jpg"];
            return;
        }
    }
    
    // If that doesn't work, fallback
    [self debug:@"Could not extract image from live photo, using fallback"];
    [self loadLivePhotoStillImage:nil];
}

- (void) processLivePhotoImage:(UIImage *)image withName:(NSString *)name {
    [self debug:@"[processLivePhotoImage]"];
    
    if (image == nil) {
        [self error:@"Image is nil"];
        [self.extensionContext completeRequestReturningItems:@[] completionHandler:nil];
        return;
    }
    
    NSData *data = UIImageJPEGRepresentation(image, 0.9);
    
    if (data == nil || data.length == 0) {
        [self error:@"Failed to convert live photo to JPEG"];
        [self.extensionContext completeRequestReturningItems:@[] completionHandler:nil];
        return;
    }
    
    [self debug:[NSString stringWithFormat:@"Converted live photo to JPEG: %lu bytes", (unsigned long)data.length]];
    
    NSString *suggestedName = name ? name : @"livephoto.jpg";
    NSString *uti = (NSString *)kUTTypeJPEG;
    NSArray *utis = @[uti];
    
    [self saveSharedDataWithBytes:data
                            name:suggestedName
                             uti:uti
                            utis:utis];
}

- (void) processLivePhotoDataWithBytes:(NSData *)data andName:(NSString *)name {
    [self debug:@"[processLivePhotoDataWithBytes]"];
    
    if (data == nil || data.length == 0) {
        [self error:@"Live photo data is empty"];
        [self.extensionContext completeRequestReturningItems:@[] completionHandler:nil];
        return;
    }
    
    NSString *suggestedName = name ? name : @"livephoto.jpg";
    NSString *uti = (NSString *)kUTTypeJPEG;
    NSArray *utis = @[uti];
    
    [self saveSharedDataWithBytes:data
                            name:suggestedName
                             uti:uti
                            utis:utis];
}

- (void) handleVCard:(NSItemProvider*)itemProvider {
    [self debug:@"[handleVCard]"];
    
    [itemProvider loadItemForTypeIdentifier:@"public.vcard"
                                   options:nil
                           completionHandler:^(id<NSSecureCoding> item, NSError *error) {
        if (error) {
            [self error:[NSString stringWithFormat:@"Error: %@", error.localizedDescription]];
            [self.extensionContext completeRequestReturningItems:@[] completionHandler:nil];
            return;
        }
        
        if (item == nil) {
            [self error:@"VCard item is nil"];
            [self.extensionContext completeRequestReturningItems:@[] completionHandler:nil];
            return;
        }
        
        NSData *data = [[NSData alloc] init];
        NSObject *obj = (NSObject *)item;
        
        if ([obj isKindOfClass:[NSData class]]) {
            data = (NSData *)item;
        }
        else if ([obj isKindOfClass:[NSURL class]]) {
            NSURL *url = (NSURL *)item;
            data = [NSData dataWithContentsOfURL:url];
        }
        
        if (data == nil || data.length == 0) {
            [self error:@"VCard data is empty"];
            [self.extensionContext completeRequestReturningItems:@[] completionHandler:nil];
            return;
        }
        
        NSString *suggestedName = @"contact";
        if ([itemProvider respondsToSelector:NSSelectorFromString(@"suggestedName")]) {
            NSString *name = [itemProvider valueForKey:@"suggestedName"];
            if (name && [name length] > 0) {
                suggestedName = name;
            }
        }
        
        NSString *uti = @"public.vcard";
        NSArray<NSString *> *utis = itemProvider.registeredTypeIdentifiers;
        
        if (utis && [utis count] > 0) {
            uti = utis[0];
        }
        
        [self saveSharedDataWithBytes:data
                            name:suggestedName
                             uti:uti
                            utis:utis];
    }];
}

// Method for storing large amounts of data in a file.
- (void) saveSharedDataWithBytes:(NSData *)data
                            name:(NSString *)name
                             uti:(NSString *)uti
                            utis:(NSArray *)utis {
    
    [self debug:[NSString stringWithFormat:@"[saveSharedDataWithBytes] Size: %lu bytes", (unsigned long)data.length]];
    
    // create temporary path within container
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *containerURL = [fileManager containerURLForSecurityApplicationGroupIdentifier:SHAREEXT_GROUP_IDENTIFIER];
    
    if (!containerURL) {
        [self error:@"Cannot access container"];
        [self.extensionContext completeRequestReturningItems:@[] completionHandler:nil];
        return;
    }
    
    // generate unique file name
    NSString *fileName = [NSString stringWithFormat:@"shared_%@_%ld",
                         [name stringByDeletingPathExtension],
                         (long)[[NSDate date] timeIntervalSince1970]];
    
    NSURL *fileURL = [containerURL URLByAppendingPathComponent:fileName];
    
    // save file
    NSError *writeError = nil;
    [data writeToURL:fileURL options:NSDataWritingAtomic error:&writeError];
    
    if (writeError) {
        [self error:[NSString stringWithFormat:@"Error writing file: %@", writeError.localizedDescription]];
        [self.extensionContext completeRequestReturningItems:@[] completionHandler:nil];
        return;
    }
    
    [self debug:[NSString stringWithFormat:@"File saved to: %@", fileURL.path]];
    
    // store file name and url into user defaults meta data
    NSString *backURL = self.backURL ? self.backURL : @"";
    NSArray *utiArray = utis ? utis : @[uti];
    
    NSDictionary *dict = @{
        @"backURL": backURL,
        @"filePath": fileName,  // only file name, no data
        @"uti": uti,
        @"utis": utiArray,
        @"name": name
    };
    
    [self.userDefaults setObject:dict forKey:@"image"];
    [self.userDefaults synchronize];
    
    [self debug:@"Saved metadata to user defaults"];
    
    NSString *urlString = [NSString stringWithFormat:@"%@://image", SHAREEXT_URL_SCHEME];
    [self openURL:[NSURL URLWithString:urlString]];
    [self.extensionContext completeRequestReturningItems:@[] completionHandler:nil];
}

- (NSArray*) configurationItems {
    return @[];
}

- (NSString*) backURLFromBundleID: (NSString*)bundleId {
    if (bundleId == nil) return nil;
    
    if ([bundleId isEqualToString:@"com.apple.AppStore"]) return @"itms-apps://";
    if ([bundleId isEqualToString:@"com.apple.MobileAddressBook"]) return @"contact://";
    if ([bundleId isEqualToString:@"com.apple.mobilemail"]) return @"message://";
    if ([bundleId isEqualToString:@"com.apple.Maps"]) return @"maps://";
    if ([bundleId isEqualToString:@"com.apple.news"]) return @"applenews://";
    if ([bundleId isEqualToString:@"com.apple.mobilenotes"]) return @"mobilenotes://";
    if ([bundleId isEqualToString:@"com.apple.mobileslideshow"]) return @"photos-redirect://";
    if ([bundleId isEqualToString:@"com.apple.reminders"]) return @"x-apple-reminder://";
    if ([bundleId isEqualToString:@"com.apple.videos"]) return @"videos://";
    if ([bundleId isEqualToString:@"com.apple.VoiceMemos"]) return @"voicememos://";
    
    return @"";
}

- (void) willMoveToParentViewController: (UIViewController*)parent {
    NSString *extensionBundleIdentifier = [[NSBundle mainBundle] bundleIdentifier];
    NSString *parentBundleIdentifier = [extensionBundleIdentifier stringByReplacingOccurrencesOfString:@".shareextension" withString:@""];
    self.backURL = [self backURLFromBundleID:parentBundleIdentifier];
}

@end