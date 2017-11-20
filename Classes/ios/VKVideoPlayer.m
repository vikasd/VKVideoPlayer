//
//  Created by Viki.
//  Copyright (c) 2014 Viki Inc. All rights reserved.
//

#import "VKVideoPlayer.h"
#import "VKVideoPlayerConfig.h"
#import "VKVideoPlayerCaption.h"
#import "VKVideoPlayerSettingsManager.h"
#import "VKVideoPlayerLayerView.h"
#import "VKVideoPlayerTrack.h"
#import "NSObject+VKFoundation.h"
#import "VKVideoPlayerExternalMonitor.h"

#define ARC4RANDOM_MAX 0x100000000

#define VKCaptionPadding 10
#define degreesToRadians(x) (M_PI * x / 180.0f)

#ifdef DEBUG
static const int ddLogLevel = LOG_LEVEL_WARN;
#else
static const int ddLogLevel = LOG_LEVEL_WARN;
#endif

NSString *kTracksKey		= @"tracks";
NSString *kPlayableKey		= @"playable";

static const NSString *ItemStatusContext;


typedef enum {
    VKVideoPlayerCaptionPositionTop = 1111,
    VKVideoPlayerCaptionPositionBottom
} VKVideoPlayerCaptionPosition;

@interface VKVideoPlayer() <AVAssetResourceLoaderDelegate>
@property (nonatomic, assign) BOOL scrubbing;
@property (nonatomic, assign) NSTimeInterval beforeSeek;
@property (nonatomic, assign) NSTimeInterval previousPlaybackTime;
@property (nonatomic, strong) NSTimer *animationTimer;
@property (nonatomic, assign) BOOL moveRight;
@property (nonatomic, assign) BOOL moveBottom;
@property (nonatomic, assign) BOOL moveLeft;
@property (nonatomic, assign) BOOL moveTop;

@property (nonatomic, assign) float playbackRate;
@property (nonatomic, assign) double previousIndicatedBandwidth;

@property (nonatomic, strong) id timeObserver;

@property (nonatomic, strong) id<VKVideoPlayerCaptionProtocol> captionTop;
@property (nonatomic, strong) id<VKVideoPlayerCaptionProtocol> captionBottom;
@property (nonatomic, strong) id captionTopTimer;
@property (nonatomic, strong) id captionBottomTimer;


@end


@implementation VKVideoPlayer

- (id)init {
    self = [super init];
    if (self) {
        self.view = [[VKVideoPlayerView alloc] init];
        [self initialize];
    }
    return self;
}

- (id)initWithVideoPlayerView:(VKVideoPlayerView*)videoPlayerView {
    self = [super init];
    if (self) {
        self.view = videoPlayerView;
        [self initialize];
    }
    return self;
}

- (void)dealloc {
    [self removeObservers];
    
    [self.externalMonitor deactivate];
    
    self.timeObserver = nil;
    self.avPlayer = nil;
    self.captionTop = nil;
    self.captionBottom = nil;
    self.captionTopTimer = nil;
    self.captionBottomTimer = nil;
    
    self.playerItem = nil;
    
    [self pauseContent];
}

#pragma mark - initialize
- (void)initialize {
    [self initializeProperties];
    [self initializePlayerView];
    [self addObservers];
}

- (void)initializeProperties {
    self.state = VKVideoPlayerStateUnknown;
    self.scrubbing = NO;
    self.beforeSeek = 0.0;
    self.playbackRate = 1.0;
    self.previousPlaybackTime = 0;
    //  self.supportedOrientations = [[UIApplication sharedApplication] supportedInterfaceOrientationsForWindow:[[UIApplication sharedApplication] keyWindow]];
    self.supportedOrientations = VKSharedUtility.isPad ? UIInterfaceOrientationMaskAll : UIInterfaceOrientationMaskAllButUpsideDown;
    
    self.forceRotate = NO;
    
    CGRect bounds = [[UIScreen mainScreen] bounds];
    
    self.portraitFrame = CGRectMake(0, 0, MIN(bounds.size.width, bounds.size.height), MAX(bounds.size.width, bounds.size.height));
    self.landscapeFrame = CGRectMake(0, 0, MAX(bounds.size.width, bounds.size.height), MIN(bounds.size.width, bounds.size.height));
}

- (void)initializePlayerView {
    self.view.delegate = self;
    [self.view setPlayButtonsSelected:NO];
    [self.view.scrubber setValue:0.0f animated:NO];
    self.view.controlHideCountdown = [self.view.playerControlsAutoHideTime integerValue];
    
    if (!self.forceRotate) {
        self.view.fullscreenButton.hidden = YES;
    }
}

- (void)loadCurrentVideoTrack {
    __weak __typeof__(self) weakSelf = self;
    RUN_ON_UI_THREAD(^{
        [weakSelf playVideoTrack:self.videoTrack];
    });
}

#pragma mark - Error Handling

- (NSString*)videoPlayerErrorCodeToString:(VKVideoPlayerErrorCode)code {
    switch (code) {
        case kVideoPlayerErrorVideoBlocked:
            return @"kVideoPlayerErrorVideoBlocked";
            break;
        case kVideoPlayerErrorFetchStreamError:
            return @"kVideoPlayerErrorFetchStreamError";
            break;
        case kVideoPlayerErrorStreamNotFound:
            return @"kVideoPlayerErrorStreamNotFound";
            break;
        case kVideoPlayerErrorAssetLoadError:
            return @"kVideoPlayerErrorAssetLoadError";
            break;
        case kVideoPlayerErrorDurationLoadError:
            return @"kVideoPlayerErrorDurationLoadError";
            break;
        case kVideoPlayerErrorAVPlayerFail:
            return @"kVideoPlayerErrorAVPlayerFail";
            break;
        case kVideoPlayerErrorAVPlayerItemFail:
            return @"kVideoPlayerErrorAVPlayerItemFail";
            break;
        case kVideoPlayerErrorUnknown:
        default:
            return @"kVideoPlayerErrorUnknown";
            break;
    }
}

- (void)handleErrorCode:(VKVideoPlayerErrorCode)errorCode track:(id<VKVideoPlayerTrackProtocol>)track {
    [self handleErrorCode:errorCode track:track customMessage:nil];
}

- (void)handleErrorCode:(VKVideoPlayerErrorCode)errorCode track:(id<VKVideoPlayerTrackProtocol>)track customMessage:(NSString*)customMessage {
    RUN_ON_UI_THREAD(^{
        if ([self.delegate respondsToSelector:@selector(handleErrorCode:track:customMessage:)]) {
            [self.delegate handleErrorCode:errorCode track:track customMessage:customMessage];
        }
    });
}

#pragma mark - KVO

- (void)setTimeObserver:(id)timeObserver {
    if (_timeObserver) {
        DDLogVerbose(@"TimeObserver: remove %@", _timeObserver);
        [self.avPlayer removeTimeObserver:_timeObserver];
    }
    _timeObserver = timeObserver;
    if (timeObserver) {
        DDLogVerbose(@"TimeObserver: setup %@", _timeObserver);
    }
}

- (void)setCaptionBottomTimer:(id)captionBottomTimer {
    if (_captionBottomTimer) [self.avPlayer removeTimeObserver:_captionBottomTimer];
    _captionBottomTimer = captionBottomTimer;
}

- (void)setCaptionTopTimer:(id)captionTopTimer {
    if (_captionTopTimer) [self.avPlayer removeTimeObserver:_captionTopTimer];
    _captionTopTimer = captionTopTimer;
}

- (void)addObservers {
    NSNotificationCenter *defaultCenter = [NSNotificationCenter defaultCenter];
    //  [defaultCenter addObserver:self selector:@selector(applicationWillResignActive) name:UIApplicationWillResignActiveNotification object:nil];
    //  [defaultCenter addObserver:self selector:@selector(applicationDidBecomeActive) name:UIApplicationDidBecomeActiveNotification object:nil];
    [defaultCenter addObserver:self selector:@selector(volumeChanged:) name:@"AVSystemController_SystemVolumeDidChangeNotification" object:nil];
    
    //    [defaultCenter addObserver:self selector:@selector(reachabilityChanged:) name:kReachabilityChangedNotification object:nil];
    [defaultCenter addObserver:self selector:@selector(playerItemReadyToPlay) name:kVKVideoPlayerItemReadyToPlay object:nil];
    [defaultCenter addObserver:self selector:@selector(orientationChanged:) name:UIDeviceOrientationDidChangeNotification object:[UIDevice currentDevice]];
    
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    [defaults addObserver:self forKeyPath:kVKSettingsSubtitlesEnabledKey options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:nil];
    [defaults addObserver:self forKeyPath:kVKSettingsTopSubtitlesEnabledKey options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:nil];
    [defaults addObserver:self forKeyPath:kVKSettingsSubtitleLanguageCodeKey options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:nil];
    [defaults addObserver:self forKeyPath:kVKVideoQualityKey options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:nil];
    
}

- (void)removeObservers {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    [defaults removeObserver:self forKeyPath:kVKSettingsSubtitlesEnabledKey];
    [defaults removeObserver:self forKeyPath:kVKSettingsTopSubtitlesEnabledKey];
    [defaults removeObserver:self forKeyPath:kVKSettingsSubtitleLanguageCodeKey];
    [defaults removeObserver:self forKeyPath:kVKVideoQualityKey];
    
}

- (void)reachabilityChanged:(NSNotification*)notification {
    Reachability* curReachability = notification.object;
    if (curReachability == VKSharedUtility.wifiReach) {
        DDLogVerbose(@"Reachability Changed: %@", [VKSharedUtility.wifiReach isReachableViaWiFi] ? @"Wifi Detected." : @"Cellular Detected.");
        [self reloadCurrentVideoTrack];
    } else {
    }
}


- (NSString*)observedBitrateBucket:(NSNumber*)observedKbps {
    NSString* observedKbpsString = @"";
    if ([observedKbps integerValue] <= 100) {
        observedKbpsString = @"0-100";
    } else if ([observedKbps integerValue] <= 200) {
        observedKbpsString = @"101-200";
    } else if ([observedKbps integerValue] <= 400) {
        observedKbpsString = @"201-400";
    } else if ([observedKbps integerValue] <= 600) {
        observedKbpsString = @"401-600";
    } else if ([observedKbps integerValue] <= 800) {
        observedKbpsString = @"601-800";
    } else if ([observedKbps integerValue] <= 1000) {
        observedKbpsString = @"801-1000";
    } else if ([observedKbps integerValue] > 1000) {
        observedKbpsString = @">1000";
    }
    return observedKbpsString;
}

- (void)periodicTimeObserver:(CMTime)time {
    
    NSTimeInterval timeInSeconds = CMTimeGetSeconds(time);
    NSTimeInterval lastTimeInSeconds = _previousPlaybackTime;
    
    if (timeInSeconds <= 0) {
        return;
    }
    
    if ([self isPlayingVideo]) {
        _previousPlaybackTime = timeInSeconds;
    }
    
    if ([self.player currentItemDuration] > 1) {
        NSDictionary *info = [NSDictionary dictionaryWithObject:[NSNumber numberWithFloat:timeInSeconds] forKey:@"scrubberValue"];
        [[NSNotificationCenter defaultCenter] postNotificationName:kVKVideoPlayerScrubberValueUpdatedNotification object:self userInfo:info];
        
        NSDictionary *durationInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                                      [NSNumber numberWithBool:self.track.hasPrevious], @"hasPreviousVideo",
                                      [NSNumber numberWithBool:self.track.hasNext], @"hasNextVideo",
                                      [NSNumber numberWithDouble:[self.player currentItemDuration]], @"duration",
                                      nil];
        [[NSNotificationCenter defaultCenter] postNotificationName:kVKVideoPlayerDurationDidLoadNotification object:self userInfo:durationInfo];
    }
    
    [self.view hideControlsIfNecessary];
    
    if ([self.delegate respondsToSelector:@selector(videoPlayer:didPlayFrame:time:lastTime:)]) {
        [self.delegate videoPlayer:self didPlayFrame:self.track time:timeInSeconds lastTime:lastTimeInSeconds];
    }
}

- (void)seekToTimeInSecond:(float)sec userAction:(BOOL)isUserAction completionHandler:(void (^)(BOOL finished))completionHandler {
    [self scrubbingBegin];
    [self scrubbingEndAtSecond:sec userAction:isUserAction completionHandler:completionHandler];
}

- (void)scrubbingEndAtSecond:(float)sec userAction:(BOOL)isUserAction completionHandler:(void (^)(BOOL finished))completionHandler {
    [self.player seekToTimeInSeconds:sec completionHandler:completionHandler];
}


#pragma mark - Playback position

- (void)seekToLastWatchedDuration {
    RUN_ON_UI_THREAD(^{
        
        [self.view setPlayButtonsEnabled:NO];
        
        CGFloat lastWatchedTime = [self.track.lastDurationWatchedInSeconds floatValue];
        if (lastWatchedTime > 5) lastWatchedTime -= 5;
        
        DDLogVerbose(@"Seeking to last watched duration: %f", lastWatchedTime);
        [self.view.scrubber setValue:([self.player currentItemDuration] > 0) ? lastWatchedTime / [self.player currentItemDuration] : 0.0f animated:NO];
        
        [self.player seekToTimeInSeconds:lastWatchedTime completionHandler:^(BOOL finished) {
            
            if (finished && self.autoPlay){
                [self playContent];
            }
            
            if ([self.delegate respondsToSelector:@selector(videoPlayer:didStartVideo:)]) {
                [self.delegate videoPlayer:self didStartVideo:self.track];
            }
            [self.view setPlayButtonsEnabled:YES];
        }];
    });
}

- (void)playerDidPlayToEnd:(NSNotification *)notification {
    DDLogVerbose(@"Player: Did play to the end");
    RUN_ON_UI_THREAD(^{
        
        self.track.isPlayedToEnd = YES;
        [self pauseContent:NO completionHandler:^{
            if ([self.delegate respondsToSelector:@selector(videoPlayer:didPlayToEnd:)]) {
                [self.delegate videoPlayer:self didPlayToEnd:self.track];
            }
        }];
        
    });
}

#pragma mark - AVPlayer wrappers

- (BOOL)isPlayingVideo {
    return (self.avPlayer && self.avPlayer.rate != 0.0);
}


#pragma mark - Airplay

- (VKVideoPlayerView*)activePlayerView {
    if (self.externalMonitor.isConnected) {
        return self.externalMonitor.externalView;
    } else {
        return self.view;
    }
}

- (BOOL)isPlayingOnExternalDevice {
    return self.externalMonitor.isConnected;
}

#pragma mark - Hundle Videos
- (void)loadVideoWithTrack:(id<VKVideoPlayerTrackProtocol>)track {
    self.track = track;
    self.state = VKVideoPlayerStateContentLoading;
    
    VoidBlock completionHandler = ^{
        [self playVideoTrack:self.track];
    };
    switch (self.state) {
        case VKVideoPlayerStateError:
        case VKVideoPlayerStateContentPaused:
        case VKVideoPlayerStateContentLoading:
            completionHandler();
            break;
        case VKVideoPlayerStateContentPlaying:
            [self pauseContent:NO completionHandler:completionHandler];
            break;
        default:
            break;
    };
}

- (void)loadVideoWithStreamURL:(NSURL*)streamURL {
    [self loadVideoWithTrack:[[VKVideoPlayerTrack alloc] initWithStreamURL:streamURL]];
}

- (void)setTrack:(id<VKVideoPlayerTrackProtocol>)track {
    
    _track = track;
    [self clearPlayer];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:kVKVideoPlayerUpdateVideoTrack object:track];
    [self updateTrackControls];
}


- (void)clearPlayer {
    self.playerItem = nil;
    self.avPlayer = nil;
    self.player = nil;
}

- (void)playVideoTrack:(id<VKVideoPlayerTrackProtocol>)track {
    if ([self.delegate respondsToSelector:@selector(shouldVideoPlayer:startVideo:)]) {
        if (![self.delegate shouldVideoPlayer:self startVideo:track]) {
            return;
        }
    }
    [self clearPlayer];
    
    NSURL *streamURL = [track streamURL];
    if (!streamURL) {
        return;
    }
    
    [self playOnAVPlayer:streamURL playerLayerView:[self activePlayerView].playerLayerView track:track];
}

- (void)playOnAVPlayer:(NSURL*)streamURL playerLayerView:(VKVideoPlayerLayerView*)playerLayerView track:(id<VKVideoPlayerTrackProtocol>)track {
    
    if (!track.isVideoLoadedBefore) {
        track.isVideoLoadedBefore = YES;
    }
    
    NSMutableDictionary *dictionary = [@{ AVURLAssetPreferPreciseDurationAndTimingKey : @YES } mutableCopy];
    
    NSDictionary *authorization = [track authorization];
    
    if (authorization && authorization.count > 0) {
        [dictionary setValue:authorization forKey:@"AVURLAssetHTTPHeaderFieldsKey"];
    }
    
    AVURLAsset* asset = [[AVURLAsset alloc] initWithURL:streamURL options:dictionary];
    [asset.resourceLoader setDelegate:self queue:dispatch_get_main_queue()];
    
    [asset loadValuesAsynchronouslyForKeys:@[kTracksKey, kPlayableKey] completionHandler:^{
        // Completion handler block.
        RUN_ON_UI_THREAD(^{
            if (self.state == VKVideoPlayerStateDismissed) return;
            if (![asset.URL.absoluteString isEqualToString:streamURL.absoluteString]) {
                DDLogVerbose(@"Ignore stream load success. Requested to load: %@ but the current stream should be %@.", asset.URL.absoluteString, streamURL.absoluteString);
                return;
            }
            NSError *error = nil;
            AVKeyValueStatus status = [asset statusOfValueForKey:kTracksKey error:&error];
            if (status == AVKeyValueStatusLoaded) {
                
                self.playerItem = [AVPlayerItem playerItemWithAsset:asset];
                
                if (!self.avPlayer) {
                    self.avPlayer = [[AVPlayer alloc] init];
                }
                
                [self.avPlayer replaceCurrentItemWithPlayerItem:self.playerItem];
                //                self.avPlayer = [self playerWithPlayerItem:self.playerItem];
                self.player = (id<VKPlayer>)self.avPlayer;
                [playerLayerView setPlayer:self.avPlayer];
                
            } else {
                // You should deal with the error appropriately.
                [self handleErrorCode:kVideoPlayerErrorAssetLoadError track:track];
                DDLogWarn(@"The asset's tracks were not loaded:\n%@", error);
            }
        });
    }];
}

- (void)playerItemReadyToPlay {
    
    DDLogVerbose(@"Player: playerItemReadyToPlay");
    
    RUN_ON_UI_THREAD(^{
        
        switch (self.state) {
            case VKVideoPlayerStateContentPaused:
                break;
            case VKVideoPlayerStateContentLoading:{}
            case VKVideoPlayerStateError:{
                [self pauseContent:NO completionHandler:^{
                    if ([self.delegate respondsToSelector:@selector(videoPlayer:willStartVideo:)]) {
                        [self.delegate videoPlayer:self willStartVideo:self.track];
                    }
                    
                    // To play content once player is set
                    self.view.playButton.selected = YES;
                    [self.view playButtonTapped:self.view.playButton];
                    
                    [self seekToLastWatchedDuration];
                }];
                break;
            }
            default:
                break;
        }
    });
}

- (void)setPlayerItem:(AVPlayerItem *)playerItem {
    [_playerItem removeObserver:self forKeyPath:@"status"];
    [_playerItem removeObserver:self forKeyPath:@"playbackBufferEmpty"];
    [_playerItem removeObserver:self forKeyPath:@"playbackLikelyToKeepUp"];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:_playerItem];
    _playerItem = playerItem;
    _previousIndicatedBandwidth = 0.0f;
    
    if (!playerItem) {
        return;
    }
    [_playerItem addObserver:self forKeyPath:@"status" options:0 context:&ItemStatusContext];
    [_playerItem addObserver:self forKeyPath:@"playbackBufferEmpty" options:NSKeyValueObservingOptionNew context:nil];
    [_playerItem addObserver:self forKeyPath:@"playbackLikelyToKeepUp" options:NSKeyValueObservingOptionNew context:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playerDidPlayToEnd:) name:AVPlayerItemDidPlayToEndTimeNotification object:_playerItem];
    
}

- (void)setAvPlayer:(AVPlayer *)avPlayer {
    self.timeObserver = nil;
    self.captionTopTimer = nil;
    self.captionBottomTimer = nil;
    [_avPlayer removeObserver:self forKeyPath:@"status"];
    _avPlayer = avPlayer;
    
    if (_avPlayer) {
        __weak __typeof(self) weakSelf = self;
        [_avPlayer addObserver:self forKeyPath:@"status" options:0 context:nil];
        
        [self.view setMaximumTime:[NSNumber numberWithDouble:CMTimeGetSeconds(avPlayer.currentItem.asset.duration)]];
        self.timeObserver = [avPlayer addPeriodicTimeObserverForInterval:CMTimeMake(1, 1) queue:NULL usingBlock:^(CMTime time){
            [weakSelf periodicTimeObserver:time];
        }];
    }
}

- (AVPlayer*)playerWithPlayerItem:(AVPlayerItem*)playerItem {
    AVPlayer* player = [AVPlayer playerWithPlayerItem:playerItem];
    if ([player respondsToSelector:@selector(setAllowsExternalPlayback:)]) player.allowsExternalPlayback = NO;
    return player;
}

- (void)reloadCurrentVideoTrack {
    RUN_ON_UI_THREAD(^{
        VoidBlock completionHandler = ^{
            self.state = VKVideoPlayerStateContentLoading;
            [self loadCurrentVideoTrack];
        };
        
        switch (self.state) {
            case VKVideoPlayerStateUnknown:
            case VKVideoPlayerStateContentLoading:
            case VKVideoPlayerStateContentPaused:
            case VKVideoPlayerStateError:
                DDLogVerbose(@"Reload stream now.");
                completionHandler();
                break;
            case VKVideoPlayerStateContentPlaying:
                DDLogVerbose(@"Reload stream after pause.");
                [self pauseContent:NO completionHandler:completionHandler];
                break;
            case VKVideoPlayerStateDismissed:
            case VKVideoPlayerStateSuspend:
                break;
        }
    });
}

- (float)currentBitRateInKbps {
    return [self.playerItem.accessLog.events.lastObject observedBitrate]/1000;
}

- (void)animateWatermark {
    
    float minX = CGRectGetMinX(self.view.watermarkLabel.frame);
    float minY = CGRectGetMinY(self.view.watermarkLabel.frame);
    float maxX = CGRectGetMaxX(self.view.watermarkLabel.frame);
    float maxY = CGRectGetMaxY(self.view.watermarkLabel.frame);
    
    float width = CGRectGetWidth(self.view.bounds) - 10;
    float height = CGRectGetHeight(self.view.bounds) - 10;
    float offset = 5;
    float x = minX;
    float y = minY;
    
    
    if (_moveRight && maxX <= width) {
        x += offset;
    }
    
    if (_moveLeft && minX >= 10) {
        x -= offset;
    }
    
    if (_moveBottom && maxY <= height) {
        y += offset;
    }
    
    if (_moveTop && minY >= 10) {
        y -= offset;
    }
    
    if (maxX >= width) {
        _moveRight = NO;
        _moveLeft = !_moveRight;
    }
    
    if (x <= 10) {
        _moveLeft = NO;
        _moveRight = !_moveLeft;
    }
    
    if (maxY >= height) {
        _moveBottom = NO;
        _moveTop = !_moveBottom;
    }
    
    if(y <= 10) {
        _moveTop = NO;
        _moveBottom = !_moveTop;
    }
    
    
    __weak VKVideoPlayer *weakSelf = self;
    [UIView animateWithDuration:0.7
                     animations:^{
                         weakSelf.view.watermarkLabel.frame = CGRectMake(x, y, CGRectGetWidth(weakSelf.view.watermarkLabel.frame), CGRectGetHeight(weakSelf.view.watermarkLabel.frame));
                     }];
}

- (void)startWatermarkAnimation {
    
    _moveRight = _moveBottom = YES;
    _moveLeft = !_moveRight;
    _moveTop = !_moveBottom;
    
    if (_animationTimer) {
        [self stopWatermarkAnimation];
    }
    
    _animationTimer = [NSTimer timerWithTimeInterval:0.5
                                              target:self
                                            selector:@selector(animateWatermark)
                                            userInfo:nil
                                             repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:_animationTimer forMode:NSRunLoopCommonModes];
}

- (void)stopWatermarkAnimation {
    
    [_animationTimer invalidate];
    _animationTimer = nil;
    self.view.watermarkLabel.frame = CGRectMake(10.0, 10.0, CGRectGetWidth(self.view.watermarkLabel.frame), CGRectGetHeight(self.view.watermarkLabel.frame));
}

#pragma mark -

- (NSTimeInterval)currentTime {
    if (!self.track.isVideoLoadedBefore) {
        return [self.track.lastDurationWatchedInSeconds doubleValue] > 0 ? [self.track.lastDurationWatchedInSeconds doubleValue] : 0.0f;
    } else return CMTimeGetSeconds([self.player currentCMTime]);
}

#pragma mark - captions
- (void)clearCaptions {
    [self setCaptionToTop:nil];
    [self setCaptionToBottom:nil];
}

- (void)setCaption:(id<VKVideoPlayerCaptionProtocol>)caption toCaptionView:(DTAttributedLabel*)captionView playerView:(VKVideoPlayerView*)playerView {
    if (!caption.boundryTimes.count) {
        [self clearCaptionView:captionView];
        if (captionView.tag == VKVideoPlayerCaptionPositionTop) {
            self.captionTopTimer = nil;
            self.captionTop = nil;
        } else if (captionView.tag == VKVideoPlayerCaptionPositionBottom) {
            self.captionBottomTimer = nil;
            self.captionBottom = nil;
        }
        return;
    }
    
    __weak id weakSelf = self;
    
    DDLogVerbose(@"Subs: %@ - segment count %d", caption, (int)caption.segments.count);
    id captionTimer = [self.avPlayer addBoundaryTimeObserverForTimes:caption.boundryTimes queue:NULL usingBlock:^{
        [weakSelf updateCaptionView:captionView caption:caption playerView:playerView];
    }];
    
    if (captionView.tag == VKVideoPlayerCaptionPositionTop) {
        self.captionTopTimer = captionTimer;
        self.captionTop = caption;
    } else if (captionView.tag == VKVideoPlayerCaptionPositionBottom) {
        self.captionBottomTimer = captionTimer;
        self.captionBottom = caption;
    }
    [self updateCaptionView:captionView caption:caption playerView:playerView];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (object == [NSUserDefaults standardUserDefaults]) {
        if ([keyPath isEqualToString:kVKSettingsSubtitlesEnabledKey]) {
            NSString  *fromLang, *toLang;
            if ([[change valueForKeyPath:NSKeyValueChangeNewKey] boolValue]) {
                fromLang = @"null";
                toLang = VKSharedVideoPlayerSettingsManager.subtitleLanguageCode;
            } else {
                self.captionBottomTimer = nil;
                self.captionBottom = nil;
                fromLang = VKSharedVideoPlayerSettingsManager.subtitleLanguageCode;
                toLang = @"null";
            }
            
            if ([self.delegate respondsToSelector:@selector(videoPlayer:didChangeSubtitleFrom:to:)]) {
                [self.delegate videoPlayer:self didChangeSubtitleFrom:fromLang to:toLang];
            }
        }
        if ([keyPath isEqualToString:kVKSettingsTopSubtitlesEnabledKey]) {
            if ([[change valueForKeyPath:NSKeyValueChangeNewKey] boolValue]) {
            } else {
                self.captionTopTimer = nil;
                self.captionTop = nil;
            }
        }
        if ([keyPath isEqualToString:kVKSettingsSubtitleLanguageCodeKey]) {
        }
        if ([keyPath isEqualToString:kVKVideoQualityKey]) {
            [self reloadCurrentVideoTrack];
        }
    }
    
    if (object == self.avPlayer) {
        if ([keyPath isEqualToString:@"status"]) {
            switch ([self.avPlayer status]) {
                case AVPlayerStatusReadyToPlay:
                    DDLogVerbose(@"AVPlayerStatusReadyToPlay");
                    if (self.playerItem.status == AVPlayerItemStatusReadyToPlay) {
                        [[NSNotificationCenter defaultCenter] postNotificationName:kVKVideoPlayerItemReadyToPlay object:nil];
                    }
                    break;
                case AVPlayerStatusFailed:
                    DDLogVerbose(@"AVPlayerStatusFailed");
                    [self handleErrorCode:kVideoPlayerErrorAVPlayerFail track:self.track];
                default:
                    break;
            }
        }
    }
    
    if (object == self.playerItem) {
        if ([keyPath isEqualToString:@"playbackBufferEmpty"]) {
            if (self.playerItem.isPlaybackBufferEmpty && [self.delegate respondsToSelector:@selector(videoPlayer:isBuffering:)]) {
                [self.delegate videoPlayer:self isBuffering:YES];
            }
            
            DDLogVerbose(@"playbackBufferEmpty: %@", self.playerItem.isPlaybackBufferEmpty ? @"yes" : @"no");
            if (self.playerItem.isPlaybackBufferEmpty && [self currentTime] > 0 && [self currentTime] < [self.player currentItemDuration] - 1 && self.state == VKVideoPlayerStateContentPlaying) {
                [[NSNotificationCenter defaultCenter] postNotificationName:kVKVideoPlayerPlaybackBufferEmpty object:nil];
            }
        }
        if ([keyPath isEqualToString:@"playbackLikelyToKeepUp"]) {
            if (self.playerItem.playbackLikelyToKeepUp && [self.delegate respondsToSelector:@selector(videoPlayer:isBuffering:)]) {
                [self.delegate videoPlayer:self isBuffering:NO];
            }
            
            DDLogVerbose(@"playbackLikelyToKeepUp: %@", self.playerItem.playbackLikelyToKeepUp ? @"yes" : @"no");
            if (self.playerItem.playbackLikelyToKeepUp) {
                if (self.state == VKVideoPlayerStateContentPlaying && ![self isPlayingVideo]) {
                    [[NSNotificationCenter defaultCenter] postNotificationName:kVKVideoPlayerPlaybackLikelyToKeepUp object:nil];
                    [self.player play];
                }
            }
        }
        if ([keyPath isEqualToString:@"status"]) {
            switch ([self.playerItem status]) {
                case AVPlayerItemStatusReadyToPlay:
                    DDLogVerbose(@"AVPlayerItemStatusReadyToPlay");
                    if ([self.avPlayer status] == AVPlayerStatusReadyToPlay) {
                        [[NSNotificationCenter defaultCenter] postNotificationName:kVKVideoPlayerItemReadyToPlay object:nil];
                    }
                    break;
                case AVPlayerItemStatusFailed:
                    DDLogVerbose(@"AVPlayerItemStatusFailed");
                    [self handleErrorCode:kVideoPlayerErrorAVPlayerItemFail track:self.track];
                default:
                    break;
            }
        }
    }
}



#pragma mark - Controls

- (NSString*)playerStateDescription:(VKVideoPlayerState)playerState {
    switch (playerState) {
        case VKVideoPlayerStateUnknown:
            return @"Unknown";
            break;
        case VKVideoPlayerStateContentLoading:
            return @"ContentLoading";
            break;
        case VKVideoPlayerStateContentPaused:
            return @"ContentPaused";
            break;
        case VKVideoPlayerStateContentPlaying:
            return @"ContentPlaying";
            break;
        case VKVideoPlayerStateSuspend:
            return @"Player Stay";
            break;
        case VKVideoPlayerStateDismissed:
            return @"Player Dismissed";
            break;
        case VKVideoPlayerStateError:
            return @"Player Error";
            break;
    }
}


- (void)setState:(VKVideoPlayerState)newPlayerState {
    if ([self.delegate respondsToSelector:@selector(shouldVideoPlayer:changeStateTo:)]) {
        if (![self.delegate shouldVideoPlayer:self changeStateTo:newPlayerState]) {
            return;
        }
    }
    RUN_ON_UI_THREAD(^{
        if ([self.delegate respondsToSelector:@selector(videoPlayer:willChangeStateTo:)]) {
            [self.delegate videoPlayer:self willChangeStateTo:newPlayerState];
        }
        
        VKVideoPlayerState oldPlayerState = self.state;
        if (oldPlayerState == newPlayerState) return;
        
        switch (oldPlayerState) {
            case VKVideoPlayerStateContentLoading:
                [self setLoading:NO];
                break;
            case VKVideoPlayerStateContentPlaying:
                break;
            case VKVideoPlayerStateContentPaused:
                self.view.buttonOverlayView.hidden = self.view.buttonHolderView.hidden = self.view.playButtonHolderView.hidden = YES ;
                break;
            case VKVideoPlayerStateDismissed:
                break;
            case VKVideoPlayerStateError:
                break;
            default:
                break;
        }
        
        DDLogVerbose(@"Player State: %@ -> %@", [self playerStateDescription:self.state], [self playerStateDescription:newPlayerState]);
        _state = newPlayerState;
        
        switch (newPlayerState) {
            case VKVideoPlayerStateUnknown:
                break;
            case VKVideoPlayerStateContentLoading:
                [self setLoading:YES];
                self.playerControlsEnabled = NO;
                break;
            case VKVideoPlayerStateContentPlaying: {
                self.view.controlHideCountdown = [self.view.playerControlsAutoHideTime integerValue];
                self.playerControlsEnabled = YES;
                [self.view setPlayButtonsSelected:NO];
                self.view.playerLayerView.hidden = NO;
//                self.view.buttonOverlayView.hidden = YES;
                [self.player play];
            } break;
            case VKVideoPlayerStateContentPaused:
                self.playerControlsEnabled = YES;
                [self.view setPlayButtonsSelected:YES];
                self.view.playerLayerView.hidden = NO;
                self.track.lastDurationWatchedInSeconds = [NSNumber numberWithFloat:[self currentTime]];
                self.view.buttonOverlayView.hidden = NO;
                
                if (self.avNoteEnabled) {
                    self.view.buttonHolderView.hidden = NO;
                } else {
                    self.view.playButtonHolderView.hidden = NO;
                }
                
                [self.player pause];
                break;
            case VKVideoPlayerStateSuspend:
                break;
            case VKVideoPlayerStateError:{
                [self.player pause];
                self.view.playerLayerView.hidden = YES;
                self.playerControlsEnabled = NO;
                self.view.controlHideCountdown = kPlayerControlsDisableAutoHide;
                break;
            }
            case VKVideoPlayerStateDismissed:
                self.view.playerLayerView.hidden = YES;
                self.playerControlsEnabled = NO;
                self.avPlayer = nil;
                self.playerItem = nil;
                break;
        }
        
        if ([self.delegate respondsToSelector:@selector(videoPlayer:didChangeStateFrom:)]) {
            [self.delegate videoPlayer:self didChangeStateFrom:oldPlayerState];
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:kVKVideoPlayerStateChanged object:nil userInfo:@{
                                                                                                                    @"oldState":[NSNumber numberWithInteger:oldPlayerState],
                                                                                                                    @"newState":[NSNumber numberWithInteger:newPlayerState]
                                                                                                                    }];
    });
}

- (void)playContent {
    RUN_ON_UI_THREAD(^{
        if (self.state == VKVideoPlayerStateContentPaused) {
            self.state = VKVideoPlayerStateContentPlaying;
        }
        self.avPlayer.rate = self.playbackRate;
    });
}

- (void)pauseContent {
    [self pauseContent:NO completionHandler:nil];
}

- (void)stopContent {
    [self stopWatermarkAnimation];
    [self pauseContent];
    self.track = nil;
}

- (void)pauseContentWithCompletionHandler:(void (^)())completionHandler {
    [self pauseContent:NO completionHandler:completionHandler];
}

- (void)pauseContent:(BOOL)isUserAction completionHandler:(void (^)())completionHandler {
    
    RUN_ON_UI_THREAD(^{
        
        switch ([self.playerItem status]) {
            case AVPlayerItemStatusFailed:
                self.state = VKVideoPlayerStateError;
                return;
                break;
            case AVPlayerItemStatusUnknown:
                DDLogVerbose(@"Trying to pause content but AVPlayerItemStatusUnknown.");
                self.state = VKVideoPlayerStateContentLoading;
                return;
                break;
            default:
                break;
        }
        
        switch ([self.avPlayer status]) {
            case AVPlayerStatusFailed:
                self.state = VKVideoPlayerStateError;
                return;
                break;
            case AVPlayerStatusUnknown:
                DDLogVerbose(@"Trying to pause content but AVPlayerStatusUnknown.");
                self.state = VKVideoPlayerStateContentLoading;
                return;
                break;
            default:
                break;
        }
        
        switch (self.state) {
            case VKVideoPlayerStateContentLoading:
            case VKVideoPlayerStateContentPlaying:
            case VKVideoPlayerStateContentPaused:
            case VKVideoPlayerStateSuspend:
            case VKVideoPlayerStateError:
                self.state = VKVideoPlayerStateContentPaused;
                if (completionHandler) completionHandler();
                break;
            default:
                break;
        }
    });
}

- (void)setPlayerControlsEnabled:(BOOL)enabled {
    [self.view setControlsEnabled:enabled];
}


- (void)updateTrackControls {
}


#pragma mark - VKScrubberDelegate

- (void)scrubbingBegin {
    [self pauseContent:NO completionHandler:^{
        _scrubbing = YES;
        self.view.controlHideCountdown = -1;
        _beforeSeek = [self currentTime];
    }];
}

- (void)scrubbingEnd {
    _scrubbing = NO;
    float afterSeekTime = self.view.scrubber.value;
    [self scrubbingEndAtSecond:afterSeekTime userAction:YES completionHandler:^(BOOL finished) {
        if (finished) [self playContent];
    }];
}

- (void)zoomInPressed {
    ((AVPlayerLayer *)self.view.layer).videoGravity = AVLayerVideoGravityResizeAspectFill;
    if ([[[UIDevice currentDevice] systemVersion] hasPrefix:@"5"]) {
        self.view.frame = self.view.frame;
    }
}

- (void)zoomOutPressed {
    ((AVPlayerLayer *)self.view.layer).videoGravity = AVLayerVideoGravityResizeAspect;
    if ([[[UIDevice currentDevice] systemVersion] hasPrefix:@"5"]) {
        self.view.frame = self.view.frame;
    }
}

#pragma mark - VKVideoPlayerViewDelegate
- (id<VKVideoPlayerTrackProtocol>)videoTrack {
    return self.track;
}

- (void)videoQualityButtonTapped {
    if ([self.delegate respondsToSelector:@selector(videoPlayer:didControlByEvent:)]) {
        [self.delegate videoPlayer:self didControlByEvent:VKVideoPlayerControlEventTapVideoQuality];
    }
}

- (void)fullScreenButtonTapped {
    self.isFullScreen = self.view.fullscreenButton.selected;
    
    if (self.isFullScreen) {
        [self performOrientationChange:UIInterfaceOrientationLandscapeRight];
    } else {
        [self performOrientationChange:UIInterfaceOrientationPortrait];
    }
    
    if ([self.delegate respondsToSelector:@selector(videoPlayer:didControlByEvent:)]) {
        [self.delegate videoPlayer:self didControlByEvent:VKVideoPlayerControlEventTapFullScreen];
    }
}

- (void)captionButtonTapped {
    if ([self.delegate respondsToSelector:@selector(videoPlayer:didControlByEvent:)]) {
        [self.delegate videoPlayer:self didControlByEvent:VKVideoPlayerControlEventTapCaption];
    }
}

- (void)playButtonPressed {
    [self playContent];
}

- (void)noteButtonTapped {
    [self.delegate addVideoNote:self];
}

- (void)noteSelected:(NSString *)noteId {
    [self.delegate noteSelected:noteId];
}

- (void)pauseButtonPressed {
    switch (self.state) {
        case VKVideoPlayerStateContentPlaying:
            [self pauseContent:YES completionHandler:nil];
            break;
        default:
            break;
    }
}

- (void)nextTrackButtonPressed {
    if (self.track.hasNext) {
        if ([self.delegate respondsToSelector:@selector(videoPlayer:didControlByEvent:)]) {
            [self.delegate videoPlayer:self didControlByEvent:VKVideoPlayerControlEventTapNext];
        }
    }
}

- (void)previousTrackButtonPressed {
    if (self.track.hasPrevious) {
        if ([self.delegate respondsToSelector:@selector(videoPlayer:didControlByEvent:)]) {
            [self.delegate videoPlayer:self didControlByEvent:VKVideoPlayerControlEventTapPrevious];
        }
    }
}

- (void)nextTrackBySwipe {
    if (self.track.hasNext) {
        if ([self.delegate respondsToSelector:@selector(videoPlayer:didControlByEvent:)]) {
            [self.delegate videoPlayer:self didControlByEvent:VKVideoPlayerControlEventSwipeNext];
        }
    }
}

- (void)previousTrackBySwipe {
    if (self.track.hasPrevious) {
        if ([self.delegate respondsToSelector:@selector(videoPlayer:didControlByEvent:)]) {
            [self.delegate videoPlayer:self didControlByEvent:VKVideoPlayerControlEventSwipePrevious];
        }
    }
}

- (void)rewindButtonPressed {
    
    float seekToTime = [self currentTime] - 30;
    [self seekToTimeInSecond:seekToTime userAction:YES completionHandler:^(BOOL finished) {
        if (finished) [self playContent];
    }];
}

- (void)doneButtonTapped {
    if ([self.delegate respondsToSelector:@selector(videoPlayer:didControlByEvent:)]) {
        [self.delegate videoPlayer:self didControlByEvent:VKVideoPlayerControlEventTapDone];
    }
}

- (void)playerViewSingleTapped {
    if ([self.delegate respondsToSelector:@selector(videoPlayer:didControlByEvent:)]) {
        [self.delegate videoPlayer:self didControlByEvent:VKVideoPlayerControlEventTapPlayerView];
    }
}

- (void)presentSubtitleLangaugePickerFromButton:(VKPickerButton*)button {
    if ([self.delegate respondsToSelector:@selector(videoPlayer:didControlByEvent:)]) {
        [self.delegate videoPlayer:self didControlByEvent:VKVideoPlayerControlEventTapDone];
    }
}

- (void)playbackRateChanged:(float)rate {
    self.playbackRate = rate;
    [self playContent];
}

- (void)layoutNavigationAndStatusBarForOrientation:(UIInterfaceOrientation)interfaceOrientation {
    [[UIApplication sharedApplication] setStatusBarOrientation:interfaceOrientation animated:NO];
}

#pragma mark - Auto hide controls

- (void)setForceRotate:(BOOL)forceRotate {
    if (_forceRotate != forceRotate) {
        _forceRotate = forceRotate;
    }
    
    self.view.fullscreenButton.hidden = !self.forceRotate;
}

- (void)setLoading:(BOOL)loading {
    if (loading) {
        [self.view.activityIndicator startAnimating];
    } else {
        [self.view.activityIndicator stopAnimating];
    }
}

#pragma mark - Handle volume change

- (void)volumeChanged:(NSNotification *)notification {
    self.view.controlHideCountdown = [self.view.playerControlsAutoHideTime integerValue];
}



#pragma mark - Remote Control Events handler

- (void)remoteControlReceivedWithEvent:(UIEvent *)receivedEvent {
    if (receivedEvent.type == UIEventTypeRemoteControl) {
        switch (receivedEvent.subtype) {
            case UIEventSubtypeRemoteControlPlay:
                [self playButtonPressed];
                break;
            case UIEventSubtypeRemoteControlPause:
                [self pauseButtonPressed];
            case UIEventSubtypeRemoteControlStop:
                break;
            case UIEventSubtypeRemoteControlNextTrack:
                [self nextTrackButtonPressed];
                break;
            case UIEventSubtypeRemoteControlPreviousTrack:
                [self previousTrackButtonPressed];
                break;
            case UIEventSubtypeRemoteControlBeginSeekingForward:
            case UIEventSubtypeRemoteControlBeginSeekingBackward:
                [self scrubbingBegin];
                break;
            case UIEventSubtypeRemoteControlEndSeekingForward:
            case UIEventSubtypeRemoteControlEndSeekingBackward:
                self.view.scrubber.value = receivedEvent.timestamp;
                [self scrubbingEnd];
                break;
            default:
                break;
        }
    }
}

- (DTCSSStylesheet*)captionStyleSheet:(NSString*)color {
    float fontSize = 1.3f;
    float shadowSize = 1.0f;
    
    switch ([[VKSharedUtility setting:kVKSettingsSubtitleSizeKey] integerValue]) {
        case 1:
            fontSize = 1.5f;
            break;
        case 2:
            fontSize = 2.0f;
            shadowSize = 1.2f;
            break;
        case 3:
            fontSize = 3.5f;
            shadowSize = 1.5f;
            break;
    }
    
    DTCSSStylesheet* stylesheet = [[DTCSSStylesheet alloc] initWithStyleBlock:[NSString stringWithFormat:@"body{\
                                                                               text-align: center;\
                                                                               font-size: %fem;\
                                                                               font-family: Helvetica Neue;\
                                                                               font-weight: bold;\
                                                                               color: %@;\
                                                                               text-shadow: -%fpx -%fpx %fpx #000, %fpx -%fpx %fpx #000, -%fpx %fpx %fpx #000, %fpx %fpx %fpx #000;\
                                                                               vertical-align: bottom;\
                                                                               }", fontSize, color, shadowSize, shadowSize, shadowSize, shadowSize, shadowSize, shadowSize, shadowSize, shadowSize, shadowSize, shadowSize, shadowSize, shadowSize]];
    return stylesheet;
}

- (void)clearCaptionView:(DTAttributedLabel*)captionView {
    [captionView setAttributedString:[[NSAttributedString alloc] initWithHTMLData:[@"" dataUsingEncoding:NSUTF8StringEncoding] options:nil documentAttributes:NULL]];
}

- (CGFloat)captionPadding:(DTAttributedLabel*)captionView {
    CGFloat aspectRatio = self.playerItem.presentationSize.width/self.playerItem.presentationSize.height;
    if (isnan(aspectRatio)) {
        return 0.0f;
    }
    CGFloat activePlayerViewWidth = CGRectGetWidth([self activePlayerView].frame);
    CGFloat videoHeight = activePlayerViewWidth/aspectRatio;
    CGFloat padding = (CGRectGetHeight([self activePlayerView].frame) - videoHeight)/2;
    
    if ([self activePlayerView] == self.view) {
        if (captionView.tag == VKVideoPlayerCaptionPositionBottom && !self.view.isControlsHidden) {
            padding = MAX(CGRectGetHeight(self.view.bottonControlOverlay.frame), padding);
        }
    }
    
    return MAX(padding, 0.0f);
}

- (void)updateCaptionView:(DTAttributedLabel*)captionView caption:(id<VKVideoPlayerCaptionProtocol>)caption playerView:(VKVideoPlayerView*)playerView {
    float timeInSeconds = CMTimeGetSeconds([self.player currentCMTime]);
    float timeInMilliseconds = timeInSeconds * 1000;
    NSString* html = [caption contentAtTime:timeInMilliseconds];
    int padding = VKCaptionPadding;
    CGFloat extraPadding = [self captionPadding:captionView];
    NSString* color = nil;
    if (captionView.tag == VKVideoPlayerCaptionPositionTop) {
        color = @"#CCC";
        [captionView setFrameHeight:CGRectGetHeight(playerView.frame)];
    } else {
        color = @"#FFF";
        captionView.frame = CGRectMake(padding, padding, playerView.frame.size.width - padding*2, playerView.frame.size.height - padding - extraPadding);
    }
    
    NSMutableDictionary* options = [NSMutableDictionary dictionaryWithObject:[self captionStyleSheet:color] forKey:DTDefaultStyleSheet];
    NSAttributedString *string = [[NSAttributedString alloc] initWithHTMLData:[html dataUsingEncoding:NSUTF8StringEncoding] options:options documentAttributes:NULL];
    captionView.attributedString = string;
    captionView.isAccessibilityElement = YES;
    captionView.accessibilityLabel = [html stripHtml];
    
    if (captionView.tag == VKVideoPlayerCaptionPositionTop) {
        [captionView setFrameOriginY:padding + extraPadding];
        DDLogVerbose(@"Set top caption: %@", [html stripHtml]);
    } else if (captionView.tag == VKVideoPlayerCaptionPositionBottom) {
        [captionView sizeToFit];
        captionView.center = CGPointMake(playerView.frame.size.width * 0.5f, captionView.center.y);
        [captionView setFrameOriginY:playerView.frame.size.height - captionView.frame.size.height - padding - extraPadding];
        DDLogVerbose(@"Set bottom caption: %@", [html stripHtml]);
    }
}

- (void)setCaptionToBottom:(id<VKVideoPlayerCaptionProtocol>)caption {
    [self setCaptionToBottom:caption playerView:[self activePlayerView]];
}
- (void)setCaptionToBottom:(id<VKVideoPlayerCaptionProtocol>)caption playerView:(VKVideoPlayerView*)playerView {
}

- (void)setCaptionToTop:(id<VKVideoPlayerCaptionProtocol>)caption {
    [self setCaptionToTop:caption playerView:[self activePlayerView]];
}
- (void)setCaptionToTop:(id<VKVideoPlayerCaptionProtocol>)caption playerView:(VKVideoPlayerView*)playerView {
}

#pragma mark - Orientation
- (void)orientationChanged:(NSNotification *)note {
    UIDevice * device = note.object;
    
    UIInterfaceOrientation rotateToOrientation;
    switch(device.orientation) {
        case UIDeviceOrientationPortrait:
            DDLogVerbose(@"ORIENTATION: Portrait");
            rotateToOrientation = UIInterfaceOrientationPortrait;
            break;
        case UIDeviceOrientationPortraitUpsideDown:
            DDLogVerbose(@"ORIENTATION: PortraitDown");
            rotateToOrientation = UIInterfaceOrientationPortraitUpsideDown;
            break;
        case UIDeviceOrientationLandscapeLeft:
            DDLogVerbose(@"ORIENTATION: LandscapeRight");
            rotateToOrientation = UIInterfaceOrientationLandscapeRight;
            break;
        case UIDeviceOrientationLandscapeRight:
            DDLogVerbose(@"ORIENTATION: LandscapeLeft");
            rotateToOrientation = UIInterfaceOrientationLandscapeLeft;
            break;
        default:
            rotateToOrientation = self.visibleInterfaceOrientation;
            break;
    }
    
    //    if ((1 << rotateToOrientation) & self.supportedOrientations && rotateToOrientation != self.visibleInterfaceOrientation) {
    //        [self performOrientationChange:rotateToOrientation];
    //    }
}

- (void)performOrientationChange:(UIInterfaceOrientation)deviceOrientation {
    
    //    if (!self.forceRotate) {
    //        return;
    //    }
    //    if ([self.delegate respondsToSelector:@selector(videoPlayer:willChangeOrientationTo:)]) {
    //        [self.delegate videoPlayer:self willChangeOrientationTo:deviceOrientation];
    //    }
    
    //    CGFloat degrees = [self degreesForOrientation:deviceOrientation];
    //    __weak __typeof__(self) weakSelf = self;
    //    UIInterfaceOrientation lastOrientation = self.visibleInterfaceOrientation;
    //    self.visibleInterfaceOrientation = deviceOrientation;
    //    [UIView animateWithDuration:0.3f animations:^{
    //        CGRect bounds = [[UIScreen mainScreen] bounds];
    //        CGRect parentBounds;
    //        CGRect viewBoutnds;
    //        if (UIInterfaceOrientationIsLandscape(deviceOrientation)) {
    //            viewBoutnds = CGRectMake(0, 0, CGRectGetWidth(self.landscapeFrame), CGRectGetHeight(self.landscapeFrame));
    //            parentBounds = CGRectMake(0, 0, CGRectGetHeight(bounds), CGRectGetWidth(bounds));
    //        } else {
    //            viewBoutnds = CGRectMake(0, 0, CGRectGetWidth(self.portraitFrame), CGRectGetHeight(self.portraitFrame));
    //            parentBounds = CGRectMake(0, 0, CGRectGetWidth(bounds), CGRectGetHeight(bounds));
    //        }
    //
    //        weakSelf.view.superview.transform = CGAffineTransformMakeRotation(degreesToRadians(degrees));
    //        weakSelf.view.superview.bounds = parentBounds;
    //        [weakSelf.view.superview setFrameOriginX:0.0f];
    //        [weakSelf.view.superview setFrameOriginY:0.0f];
    //
    //        CGRect wvFrame = weakSelf.view.superview.superview.frame;
    //        if (wvFrame.origin.y > 0) {
    //            wvFrame.size.height = CGRectGetHeight(bounds) ;
    //            wvFrame.origin.y = 0;
    //            weakSelf.view.superview.superview.frame = wvFrame;
    //        }
    //
    //        weakSelf.view.bounds = viewBoutnds;
    //        [weakSelf.view setFrameOriginX:0.0f];
    //        [weakSelf.view setFrameOriginY:0.0f];
    //        [weakSelf.view layoutForOrientation:deviceOrientation];
    //
    //    } completion:^(BOOL finished) {
    //        if ([self.delegate respondsToSelector:@selector(videoPlayer:didChangeOrientationFrom:)]) {
    //            [self.delegate videoPlayer:self didChangeOrientationFrom:lastOrientation];
    //        }
    //    }];
    
    //    if ([self.delegate respondsToSelector:@selector(videoPlayer:didChangeOrientationFrom:)]) {
    //        [self.delegate videoPlayer:self didChangeOrientationFrom:lastOrientation];
    //    }
    
    //    [[UIApplication sharedApplication] setStatusBarOrientation:self.visibleInterfaceOrientation animated:YES];
    //    self.view.fullscreenButton.selected = self.isFullScreen = UIInterfaceOrientationIsLandscape(deviceOrientation);
}

- (CGFloat)degreesForOrientation:(UIInterfaceOrientation)deviceOrientation {
    switch (deviceOrientation) {
        case UIInterfaceOrientationUnknown:
        case UIInterfaceOrientationPortrait:
            return 0;
            break;
        case UIInterfaceOrientationLandscapeRight:
            return 90;
            break;
        case UIInterfaceOrientationLandscapeLeft:
            return -90;
            break;
        case UIInterfaceOrientationPortraitUpsideDown:
            return 180;
            break;
    }
}


- (BOOL)resourceLoader:(AVAssetResourceLoader *)resourceLoader shouldWaitForLoadingOfRequestedResource:(AVAssetResourceLoadingRequest *)loadingRequest {
    
    NSString *scheme = loadingRequest.request.URL.scheme;
    
    if ([scheme isEqualToString:@"ckey"]) {
        
        NSString *request = loadingRequest.request.URL.host;
        NSData *data = [[NSUserDefaults standardUserDefaults] objectForKey:request];
        
        if (data) {
            loadingRequest.contentInformationRequest.contentType = AVStreamingKeyDeliveryPersistentContentKeyType;
            loadingRequest.contentInformationRequest.byteRangeAccessSupported = YES;
            loadingRequest.contentInformationRequest.contentLength = data.length;
            [loadingRequest.dataRequest respondWithData:data];
            [loadingRequest finishLoading];
        } else {
            // Data loading fail
        }
    }
    
    return YES;
}

@end


@implementation AVPlayer (VKPlayer)

- (void)seekToTimeInSeconds:(float)time completionHandler:(void (^)(BOOL finished))completionHandler {
    if ([self respondsToSelector:@selector(seekToTime:toleranceBefore:toleranceAfter:completionHandler:)]) {
        [self seekToTime:CMTimeMakeWithSeconds(time, 1) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:completionHandler];
    } else {
        [self seekToTime:CMTimeMakeWithSeconds(time, 1) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
        completionHandler(YES);
    }
}

- (NSTimeInterval)currentItemDuration {
    return CMTimeGetSeconds([self.currentItem duration]);
}

- (CMTime)currentCMTime {
    return [self currentTime];
}

@end

