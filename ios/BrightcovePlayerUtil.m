#import <React/RCTBridgeModule.h>
#import "BrightcovePlayerUtil.h"
#import "BrightcovePlayerOfflineVideoManager.h"

static NSString *const kErrorCode = @"error";
static NSString *const kErrorMessageDelete = @"undefined videoToken";
static NSString *const kEventOfflineNotification = @"OfflineNotification";
static NSString *const kUserDefaultKeyOfflinePrefix = @"bcovoffline@";
static NSString *const kUserDefaultKeyOfflineAccountId = @"accountId";
static NSString *const kUserDefaultKeyOfflineVideoId = @"videoId";
static NSString *const kOfflineStatusAccountId = @"accountId";
static NSString *const kOfflineStatusVideoId = @"videoId";
static NSString *const kOfflineStatusVideoToken = @"videoToken";
static NSString *const kOfflineStatusDownloadProgress = @"downloadProgress";
static NSString *const kPlaylistAccountId = @"accountId";
static NSString *const kPlaylistVideoId = @"videoId";
static NSString *const kPlaylistReferenceId = @"referenceId";
static NSString *const kPlaylistName = @"name";
static NSString *const kPlaylistDescription = @"description";
static NSString *const kPlaylistDuration = @"duration";

@implementation BrightcovePlayerUtil {
    bool hasListeners;
}

RCT_EXPORT_MODULE();

- (NSArray<NSString *> *)supportedEvents {
    return @[kEventOfflineNotification];
}

- (void)startObserving {
    hasListeners = YES;
}

- (void)stopObserving {
    hasListeners = NO;
}

RCT_EXPORT_METHOD(requestDownloadVideoWithReferenceId:(NSString *)referenceId accountId:(NSString *)accountId policyKey:(NSString *)policyKey bitRate:(nonnull NSNumber *)bitRate resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
    [BrightcovePlayerOfflineVideoManager sharedManager].delegate = self;
    BCOVPlaybackService* playbackService = [[BCOVPlaybackService alloc] initWithAccountId:accountId policyKey:policyKey];
    [playbackService findVideoWithReferenceID:referenceId parameters:nil completionHandler:^(BCOVVideo *video, NSDictionary *jsonResponse, NSError *error) {
        if (error) {
            reject(kErrorCode, error.localizedDescription, error);
            return;
        }
        [[BrightcovePlayerOfflineVideoManager sharedManager] requestVideoDownload:video mediaSelections:nil parameters:[self generateDownloadParameterWithBitRate:bitRate] completion:^(BCOVOfflineVideoToken offlineVideoToken, NSError *error) {
            if (error) {
                reject(kErrorCode, error.localizedDescription, error);
                return;
            }
            [NSUserDefaults.standardUserDefaults setObject:@{kUserDefaultKeyOfflineAccountId: accountId,
                                                             kUserDefaultKeyOfflineVideoId: video.properties[kBCOVVideoPropertyKeyId]}
                                                    forKey:[kUserDefaultKeyOfflinePrefix stringByAppendingString:offlineVideoToken]];
            [NSUserDefaults.standardUserDefaults synchronize];
            [self sendOfflineNotification];
            resolve(offlineVideoToken);
        }];
    }];
}

RCT_EXPORT_METHOD(requestDownloadVideoWithVideoId:(NSString *)videoId accountId:(NSString *)accountId policyKey:(NSString *)policyKey bitRate:(nonnull NSNumber *)bitRate resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
    BCOVPlaybackService* playbackService = [[BCOVPlaybackService alloc] initWithAccountId:accountId policyKey:policyKey];
    [playbackService findVideoWithVideoID:videoId parameters:nil completionHandler:^(BCOVVideo *video, NSDictionary *jsonResponse, NSError *error) {
        if (error) {
            reject(kErrorCode, error.localizedDescription, error);
            return;
        }
        [BrightcovePlayerOfflineVideoManager sharedManager].delegate = self;
        [[BrightcovePlayerOfflineVideoManager sharedManager] preloadFairPlayLicense:video parameters:[self generateDownloadParameterWithBitRate:bitRate] completion:^(BCOVOfflineVideoToken offlineVideoToken, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [[BrightcovePlayerOfflineVideoManager sharedManager] requestVideoDownload:video mediaSelections:nil parameters:[self generateDownloadParameterWithBitRate:bitRate] completion:^(BCOVOfflineVideoToken offlineVideoToken, NSError *error) {
                    if (error) {
                        reject(kErrorCode, error.localizedDescription, error);
                        return;
                    }
                    [NSUserDefaults.standardUserDefaults setObject:@{kUserDefaultKeyOfflineAccountId: accountId,
                                                                     kUserDefaultKeyOfflineVideoId: video.properties[kBCOVVideoPropertyKeyId]}
                                                            forKey:[kUserDefaultKeyOfflinePrefix stringByAppendingString:offlineVideoToken]];
                    [NSUserDefaults.standardUserDefaults synchronize];
                    [self sendOfflineNotification];
                    resolve(offlineVideoToken);
                }];
            });
        }];
    }];
}

RCT_EXPORT_METHOD(getOfflineVideoStatuses:(NSString *)accountId policyKey:(NSString *)policyKey resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
    resolve([self collectOfflineVideoStatuses]);
}

RCT_EXPORT_METHOD(deleteOfflineVideo:(NSString *)accountId policyKey:(NSString *)policyKey videoToken:(NSString *)videoToken resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
    if (!videoToken) {
        reject(kErrorCode, kErrorMessageDelete, nil);
        return;
    }
    [BrightcovePlayerOfflineVideoManager sharedManager].delegate = self;
    [[BrightcovePlayerOfflineVideoManager sharedManager] cancelVideoDownload:videoToken];
    [[BrightcovePlayerOfflineVideoManager sharedManager] deleteOfflineVideo:videoToken];
    [NSUserDefaults.standardUserDefaults removeObjectForKey:[kUserDefaultKeyOfflinePrefix stringByAppendingString:videoToken]];
    [NSUserDefaults.standardUserDefaults synchronize];
    [self sendOfflineNotification];
    resolve(nil);
}

RCT_EXPORT_METHOD(getPlaylistWithPlaylistId:(NSString *)playlistId accountId:(NSString *)accountId policyKey:(NSString *)policyKey resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
    BCOVPlaybackService* playbackService = [[BCOVPlaybackService alloc] initWithAccountId:accountId policyKey:policyKey];
    [playbackService findPlaylistWithPlaylistID:playlistId parameters:nil completionHandler:^(BCOVPlaylist *playlist, NSDictionary *jsonResponse, NSError *error) {
        if (error) {
            reject(kErrorCode, error.localizedDescription, error);
            return;
        }
        resolve([self collectPlaylist:playlist]);
    }];
}

RCT_EXPORT_METHOD(getPlaylistWithReferenceId:(NSString *)referenceId accountId:(NSString *)accountId policyKey:(NSString *)policyKey resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
    BCOVPlaybackService* playbackService = [[BCOVPlaybackService alloc] initWithAccountId:accountId policyKey:policyKey];
    [playbackService findPlaylistWithReferenceID:referenceId parameters:nil completionHandler:^(BCOVPlaylist *playlist, NSDictionary *jsonResponse, NSError *error) {
        if (error) {
            reject(kErrorCode, error.localizedDescription, error);
            return;
        }
        resolve([self collectPlaylist:playlist]);
    }];
}

- (NSArray *)collectOfflineVideoStatuses {
    NSArray* statuses = [[BrightcovePlayerOfflineVideoManager sharedManager] offlineVideoStatus];
    NSMutableArray *results = [[NSMutableArray alloc] init];
    for (BCOVOfflineVideoStatus *status in statuses) {
        NSDictionary *dictionary = [NSUserDefaults.standardUserDefaults dictionaryForKey:[kUserDefaultKeyOfflinePrefix stringByAppendingString:status.offlineVideoToken]];
        if (!dictionary) continue;
        [results addObject:
         @{
           kOfflineStatusAccountId: [dictionary objectForKey:kUserDefaultKeyOfflineAccountId],
           kOfflineStatusVideoId: [dictionary objectForKey:kUserDefaultKeyOfflineVideoId],
           kOfflineStatusDownloadProgress: @(status.downloadPercent / 100.0),
           kOfflineStatusVideoToken: status.offlineVideoToken
           }];
    }
    return results;
}

- (NSArray *)collectPlaylist:(BCOVPlaylist *)playlist {
    NSMutableArray *videos = [[NSMutableArray alloc] init];
    for (BCOVVideo *video in playlist.videos) {
        NSString *name = video.properties[kBCOVVideoPropertyKeyName] ?: @"";
        NSString *description = video.properties[kBCOVVideoPropertyKeyDescription] ?: @"";
        NSString *referenceId = video.properties[kBCOVVideoPropertyKeyReferenceId] ?: @"";
        [videos addObject:
         @{
           kPlaylistAccountId: video.properties[kBCOVVideoPropertyKeyAccountId],
           kPlaylistVideoId: video.properties[kBCOVVideoPropertyKeyId],
           kPlaylistReferenceId: referenceId,
           kPlaylistName: name,
           kPlaylistDescription: description,
           kPlaylistDuration: video.properties[kBCOVVideoPropertyKeyDuration]
           }];
    }
    return videos;
}

- (NSDictionary *)generateDownloadParameterWithBitRate:(NSNumber*)bitRate {
    return
    @{
      // Purchase license (check if this key is still valid in the latest SDK)
      kBCOVFairPlayLicensePurchaseKey: @(YES),

      // Specify variant using the bitrate
      kBCOVOfflineVideoManagerRequestedBitrateKey: bitRate
      };
}

#pragma mark - BCOVOfflineVideoManagerDelegate Methods

- (void)offlineVideoToken:(BCOVOfflineVideoToken)offlineVideoToken
             downloadTask:(AVAssetDownloadTask *)downloadTask
            didProgressTo:(NSTimeInterval)progressPercent NS_AVAILABLE_IOS(10_0) {
    [self sendOfflineNotification];
}

- (void)offlineVideoToken:(BCOVOfflineVideoToken)offlineVideoToken
    aggregateDownloadTask:(AVAggregateAssetDownloadTask *)aggregateDownloadTask
            didProgressTo:(NSTimeInterval)progressPercent
        forMediaSelection:(AVMediaSelection *)mediaSelection NS_AVAILABLE_IOS(11_0) {
    [self sendOfflineNotification];
}

- (void)offlineVideoToken:(BCOVOfflineVideoToken)offlineVideoToken didFinishDownloadWithError:(NSError *)error {
    [self sendOfflineNotification];
}

- (void)sendOfflineNotification {
    if (hasListeners) {
        [self sendEventWithName:kEventOfflineNotification body:[self collectOfflineVideoStatuses]];
    }
}

@end

