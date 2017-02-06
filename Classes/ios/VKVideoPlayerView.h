//
//  Created by Viki.
//  Copyright (c) 2014 Viki Inc. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>

#import "VKScrubber.h"
//#import "VKButtonPanel.h"
#import "VKPickerButton.h"
#import "VKView.h"
#import "VKVideoPlayerConfig.h"

#define kPlayerControlsDisableAutoHide -1

@class VKVideoPlayerTrack;
@class VKVideoPlayerLayerView;

@protocol VKVideoPlayerViewDelegate <VKScrubberDelegate>
@property (nonatomic, readonly) VKVideoPlayerTrack* videoTrack;
@property (nonatomic, readonly) UIInterfaceOrientation visibleInterfaceOrientation;
- (void)fullScreenButtonTapped;
- (void)playButtonPressed;
- (void)pauseButtonPressed;
- (void)noteButtonTapped;
- (void)noteSelected:(NSString *)noteId;

- (void)nextTrackButtonPressed;
- (void)previousTrackButtonPressed;
- (void)rewindButtonPressed;

- (void)nextTrackBySwipe;
- (void)previousTrackBySwipe;

- (void)captionButtonTapped;
- (void)videoQualityButtonTapped;

- (void)doneButtonTapped;

- (void)playerViewSingleTapped;

- (void)scrubbingBegin;
- (void)scrubbingEnd;

@end

@interface VKVideoPlayerView : UIView
@property (nonatomic, strong) IBOutlet UIView* view;
@property (nonatomic, strong) IBOutlet VKVideoPlayerLayerView* playerLayerView;
@property (nonatomic, strong) IBOutlet UIView* controls;
@property (nonatomic, strong) IBOutlet UIView* bottomControlOverlay;
@property (weak, nonatomic) IBOutlet UIView *buttonOverlayView;
@property (nonatomic, strong) IBOutlet UIActivityIndicatorView* activityIndicator;

@property (nonatomic, strong) IBOutlet UIButton* playButton;
@property (nonatomic, strong) IBOutlet UILabel* currentTimeLabel;
@property (nonatomic, strong) IBOutlet VKScrubber* scrubber;
@property (weak, nonatomic) IBOutlet UIView *scrubberHolderView;
@property (nonatomic, strong) IBOutlet UILabel* totalTimeLabel;
@property (nonatomic, strong) IBOutlet UIButton* fullscreenButton;

@property (weak, nonatomic) IBOutlet UIView *buttonHolderView;
@property (nonatomic, strong) IBOutlet UIButton* bigPlayButton;
@property (weak, nonatomic) IBOutlet UIButton *addNoteButton;
@property (unsafe_unretained, nonatomic) IBOutlet UIView *playButtonHolderView;
@property (unsafe_unretained, nonatomic) IBOutlet UIButton *bigPlayButton2;

@property (weak, nonatomic) IBOutlet UILabel *watermarkLabel;
@property (nonatomic, readonly) BOOL isControlsEnabled;
@property (nonatomic, readonly) BOOL isControlsHidden;

@property (nonatomic, weak) id<VKVideoPlayerViewDelegate> delegate;
@property (nonatomic, assign) NSInteger controlHideCountdown;
@property (nonatomic, strong) NSNumber* playerControlsAutoHideTime;
@property (nonatomic, strong) NSMutableArray *cuesArray;
@property (nonatomic, assign) float videoDuration;


- (IBAction)fullscreenButtonTapped:(id)sender;
- (IBAction)playButtonTapped:(id)sender;
- (IBAction)addNoteButtonTapped:(UIButton *)sender;

- (void)loadCuesOnScrubber;
- (void)removeCuesFromScrubber;
- (void)removeCueFromScrubber:(NSString *)cueId;
- (void)addCueToScrubber:(NSDictionary *)cue;

- (IBAction)handleSingleTap:(id)sender;
- (IBAction)handleSwipeLeft:(id)sender;
- (IBAction)handleSwipeRight:(id)sender;

- (void)setMaximumTime:(NSNumber *)maxDuration;
- (void)updateTimeLabels;
- (void)setControlsHidden:(BOOL)hidden;
- (void)setControlsEnabled:(BOOL)enabled;
- (void)hideControlsIfNecessary;

- (void)setPlayButtonsSelected:(BOOL)selected;
- (void)setPlayButtonsEnabled:(BOOL)enabled;

- (void)layoutForOrientation:(UIInterfaceOrientation)interfaceOrientation;
- (void)addSubviewForControl:(UIView *)view;
- (void)addSubviewForControl:(UIView *)view toView:(UIView*)parentView;
- (void)addSubviewForControl:(UIView *)view toView:(UIView*)parentView forOrientation:(UIInterfaceOrientationMask)orientation;
- (void)removeControlView:(UIView*)view;
@end
