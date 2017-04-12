//
//  Created by Viki.
//  Copyright (c) 2014 Viki Inc. All rights reserved.
//

#import "VKVideoPlayerViewController.h"
#import "VKVideoPlayerConfig.h"
#import "VKFoundation.h"
#import "VKVideoPlayerCaptionSRT.h"
#import "VKVideoPlayerAirPlay.h"
#import "VKVideoPlayerSettingsManager.h"


@interface VKVideoPlayerViewController () {
}

@property (assign) BOOL applicationIdleTimerDisabled;
@end

@implementation VKVideoPlayerViewController

- (id)init {
  self = [super initWithNibName:NSStringFromClass([self class]) bundle:nil];
  if (self) {
    self.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    [self initialize];
  }
  return self;
}


- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
  self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
  if (self) {
    self.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    [self initialize];
  }
  return self;
}

- (void)initialize {
  [VKSharedAirplay setup];
}
- (void)dealloc {
  [VKSharedAirplay deactivate];
}

- (void)viewDidUnload {
  [super viewDidUnload];
}

- (void)viewDidLoad {
  [super viewDidLoad];
  
  self.player = [[VKVideoPlayer alloc] init];
  self.player.delegate = self;
  self.player.view.frame = self.view.bounds;
  self.player.forceRotate = YES;
  [self.view addSubview:self.player.view];
  
  if (VKSharedAirplay.isConnected) {
    [VKSharedAirplay activate:self.player];
  }
}

- (void)viewWillAppear:(BOOL)animated {
  [super viewWillAppear:animated];
  self.applicationIdleTimerDisabled = [UIApplication sharedApplication].isIdleTimerDisabled;
  [UIApplication sharedApplication].idleTimerDisabled = YES;
  [[UIApplication sharedApplication] setStatusBarHidden:NO];
}

- (void)viewDidAppear:(BOOL)animated {
  [super viewDidAppear:animated];
}

- (void)viewWillDisappear:(BOOL)animated {
  [UIApplication sharedApplication].idleTimerDisabled = self.applicationIdleTimerDisabled;
  [super viewWillDisappear:animated];
}

- (BOOL)prefersStatusBarHidden {
  return NO;
}

- (void)playVideoWithStreamURL:(NSURL*)streamURL {
  [self.player loadVideoWithTrack:[[VKVideoPlayerTrack alloc] initWithStreamURL:streamURL]];
}

- (void)playEncryptedVideo {
    
        NSURL *URL = [NSURL URLWithString:@"http://mtmedia.streaming.mediaservices.windows.net/309457b8-e5ca-427b-b977-0b2c5432d5b8/Module_08.ism/manifest(format=m3u8-aapl)"];
    
    VKVideoPlayerTrack *videoPlayerTrack = [[VKVideoPlayerTrack alloc] initWithStreamURL:URL
                                                                           authorization:@{@"Authorization": @"Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJ1cm46bWljcm9zb2Z0OmF6dXJlOm1lZGlhc2VydmljZXM6Y29udGVudGtleWlkZW50aWZpZXIiOiI0MjFiZDJkZi1lNjg3LTRmNDAtYjc4NC1jZjQ0MTdmNTJlM2IiLCJpc3MiOiJodHRwOi8vdGVzdGFjcyIsImF1ZCI6InVybjp0ZXN0IiwiZXhwIjoxNDkzNTU4NDIzfQ.Zm5TkHGRTtyCJF9GYcP8fA5QSLcR4zftP531HkKY7mA"}];
    
    [self.player loadVideoWithTrack:videoPlayerTrack];
}

- (void)playBlankEncryptedVideo {
    
    NSURL *URL = [NSURL URLWithString:@"http://mtmedia.streaming.mediaservices.windows.net/04c37741-ecad-48f8-b481-013affe133af/nature.ism/manifest(format=m3u8-aapl)"];
    VKVideoPlayerTrack *videoPlayerTrack = [[VKVideoPlayerTrack alloc] initWithStreamURL:URL];
    [self.player loadVideoWithTrack:videoPlayerTrack];
}

- (void)setSubtitle:(VKVideoPlayerCaption*)subtitle {
  [self.player setCaptionToBottom:subtitle];
}

#pragma mark - App States

- (void)applicationWillResignActive {
  self.player.view.controlHideCountdown = -1;
  if (self.player.state == VKVideoPlayerStateContentPlaying) [self.player pauseContent:NO completionHandler:nil];
}

- (void)applicationDidBecomeActive {
  self.player.view.controlHideCountdown = kPlayerControlsDisableAutoHide;
}

#pragma mark - VKVideoPlayerControllerDelegate
- (void)videoPlayer:(VKVideoPlayer*)videoPlayer didControlByEvent:(VKVideoPlayerControlEvent)event {
  if (event == VKVideoPlayerControlEventTapDone) {
    [self dismissViewControllerAnimated:YES completion:nil];
  }
}

- (void)videoPlayer:(VKVideoPlayer *)videoPlayer willStartVideo:(id<VKVideoPlayerTrackProtocol>)track {
}

- (void)videoPlayer:(VKVideoPlayer *)videoPlayer didStartVideo:(id<VKVideoPlayerTrackProtocol>)track {
    [videoPlayer pauseContent];
}


#pragma mark - Orientation
//- (BOOL)shouldAutorotate {
//  return YES;
//}

//- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
//  if (self.player.isFullScreen) {
//    return UIInterfaceOrientationIsLandscape(interfaceOrientation);
//  } else {
//    return NO;
//  }
//}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskLandscape;
}

@end
