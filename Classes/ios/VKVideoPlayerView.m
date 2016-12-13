//
//  Created by Viki.
//  Copyright (c) 2014 Viki Inc. All rights reserved.
//

#import "VKVideoPlayerView.h"
#import "VKScrubber.h"
#import <QuartzCore/QuartzCore.h>
#import "DDLog.h"
#import "VKVideoPlayerConfig.h"
#import "VKFoundation.h"
#import "VKScrubber.h"
#import "VKVideoPlayerTrack.h"
#import "UIImage+VKFoundation.h"
#import "VKVideoPlayerSettingsManager.h"

#define VIDEO_BACKGROUND_COLOR                      @"#181818"
#define SEEK_BAR_BACKGROUND_COLOR                   @"#000000"
#define VIDEO_CONTROL_COLOR                         @"#e9b81f"
#define VIDEO_NOTE_NORMAL_COLOR                     @"#e9b81f"
#define VIDEO_NOTE_SELECTED_COLOR                   @"#da5a56"



#ifdef DEBUG
static const int ddLogLevel = LOG_LEVEL_WARN;
#else
static const int ddLogLevel = LOG_LEVEL_WARN;
#endif

@interface VKVideoPlayerView()
@property (nonatomic, strong) NSMutableArray* customControls;
@property (nonatomic, strong) NSMutableArray* portraitControls;
@property (nonatomic, strong) NSMutableArray* landscapeControls;

@property (nonatomic, assign) BOOL isControlsEnabled;
@property (nonatomic, assign) BOOL isControlsHidden;
@end

@implementation VKVideoPlayerView

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.scrubber removeObserver:self forKeyPath:@"maximumValue"];
}

- (void)initialize {
    
    self.customControls = [NSMutableArray array];
    self.portraitControls = [NSMutableArray array];
    self.landscapeControls = [NSMutableArray array];
    [[NSBundle mainBundle] loadNibNamed:NSStringFromClass([self class]) owner:self options:nil];
    self.view.frame = self.frame;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [self addSubview:self.view];
    
    // ** To solve audio playback issue when device is in silent mode.
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    [audioSession setCategory:AVAudioSessionCategoryPlayback error:NULL];
    
    self.currentTimeLabel.font = THEMEFONT(@"fontRegular", DEVICEVALUE(16.0f, 10.0f));
    self.currentTimeLabel.textColor = THEMECOLOR(@"colorFont4");
    self.totalTimeLabel.font = THEMEFONT(@"fontRegular", DEVICEVALUE(16.0f, 10.0f));
    self.totalTimeLabel.textColor = THEMECOLOR(@"colorFont4");
    
    [self.scrubber addObserver:self forKeyPath:@"maximumValue" options:0 context:nil];
    
    NSNotificationCenter *defaultCenter = [NSNotificationCenter defaultCenter];
    [defaultCenter addObserver:self selector:@selector(durationDidLoad:) name:kVKVideoPlayerDurationDidLoadNotification object:nil];
    [defaultCenter addObserver:self selector:@selector(scrubberValueUpdated:) name:kVKVideoPlayerScrubberValueUpdatedNotification object:nil];
    
    [self.scrubber addTarget:self action:@selector(updateTimeLabels) forControlEvents:UIControlEventValueChanged];
    self.fullscreenButton.hidden = NO;
    self.playerControlsAutoHideTime = @5;
    
    self.backgroundColor = [VKVideoPlayerView colorFromHexString:VIDEO_BACKGROUND_COLOR];
    self.view.backgroundColor = [VKVideoPlayerView colorFromHexString:VIDEO_BACKGROUND_COLOR];
    self.buttonOverlayView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.5];
    self.bottomControlOverlay.backgroundColor = [[VKVideoPlayerView colorFromHexString:VIDEO_BACKGROUND_COLOR] colorWithAlphaComponent:0.5];
    
    UIColor *controlColor = [VKVideoPlayerView colorFromHexString:VIDEO_CONTROL_COLOR];
    [self.playButton setTitleColor:controlColor forState:UIControlStateNormal];
    [self.playButton setTitleColor:controlColor forState:UIControlStateHighlighted];
    [self.playButton setTitleColor:controlColor forState:UIControlStateSelected];
    [self.fullscreenButton setTitleColor:controlColor forState:UIControlStateNormal];
    [self.fullscreenButton setTitleColor:controlColor forState:UIControlStateHighlighted];
    [self.fullscreenButton setTitleColor:controlColor forState:UIControlStateSelected];
    [self.bigPlayButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [self.bigPlayButton setTitleColor:[UIColor whiteColor] forState:UIControlStateHighlighted];
    [self.bigPlayButton setTitleColor:[UIColor whiteColor] forState:UIControlStateSelected];
    [self.bigPlayButton2 setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [self.bigPlayButton2 setTitleColor:[UIColor whiteColor] forState:UIControlStateHighlighted];
    [self.bigPlayButton2 setTitleColor:[UIColor whiteColor] forState:UIControlStateSelected];
    [self.addNoteButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [self.addNoteButton setTitleColor:[UIColor whiteColor] forState:UIControlStateHighlighted];
    [self.addNoteButton setTitleColor:[UIColor whiteColor] forState:UIControlStateSelected];
    
    UIFont *roboFont = [UIFont fontWithName:@"Robo" size:[VKSharedUtility isPad] ? 80.0 : 50];
    self.bigPlayButton.titleLabel.font = roboFont;
    self.bigPlayButton2.titleLabel.font = roboFont;
    self.addNoteButton.titleLabel.font = roboFont;
        
    self.scrubber.minimumTrackTintColor = controlColor;
    self.scrubber.maximumTrackTintColor = [UIColor lightGrayColor];
    self.scrubber.thumbTintColor = controlColor;
    
    self.playButtonHolderView.hidden = self.buttonHolderView.hidden = YES;
    self.cuesArray = [NSMutableArray array];
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self initialize];
    }
    return self;
}

- (void) awakeFromNib {
    [super awakeFromNib];
    [self initialize];
}

- (void)layoutSubviews {
    [super layoutSubviews];
}

#pragma - VKVideoPlayerViewDelegates

- (void)loadCuesOnScrubber {
    
    for (int i = 0; i < _cuesArray.count; i++) {
        [self addCue:_cuesArray[i] atIndex:i];
    }
}

- (void)removeCuesFromScrubber {
    
    for (UIView *view in _scrubberHolderView.subviews) {
        if ([view isMemberOfClass:[UIButton class]]) {
            [view removeFromSuperview];
        }
    }
}

- (void)removeCueFromScrubber:(NSString *)cueId {
    
    NSInteger index = [_cuesArray indexOfObjectPassingTest:^BOOL(NSDictionary *obj, NSUInteger idx, BOOL * _Nonnull stop) {
        
        if ([obj[@"cueId"] isEqualToString:cueId]) {
            *stop = YES;
            return YES;
        }
        return NO;
    }];
    
    if (index != NSNotFound) {
        
        [_cuesArray removeObjectAtIndex:index];
        NSInteger subViewindex = [_scrubberHolderView.subviews indexOfObjectPassingTest:^BOOL(UIView * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            
            if (obj.tag == (index +1)) {
                *stop = YES;
                return YES;
            }
            return NO;
        }];
        
        if (subViewindex != NSNotFound) {
            
            UIView *view = _scrubberHolderView.subviews[subViewindex];
            [view removeFromSuperview];
        }
    }
}

- (void)addCueToScrubber:(NSDictionary *)cue {
    
    NSInteger index = [_cuesArray indexOfObjectPassingTest:^BOOL(NSDictionary *obj, NSUInteger idx, BOOL * _Nonnull stop) {
        
        if ([obj[@"cueId"] isEqualToString:cue[@"cueId"]]) {
            *stop = YES;
            return YES;
        }
        return NO;
    }];
    
    if (index == NSNotFound) {
        
        [_cuesArray addObject:cue];
        index = [_cuesArray indexOfObject:cue];
        [self addCue:cue atIndex:index];
    } else {
        
        [_cuesArray removeObjectAtIndex:index];
        [_cuesArray insertObject:cue atIndex:index];
        
        NSInteger subViewindex = [_scrubberHolderView.subviews indexOfObjectPassingTest:^BOOL(UIView * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            
            if (obj.tag == (index +1)) {
                *stop = YES;
                return YES;
            }
            return NO;
        }];
        
        if (subViewindex != NSNotFound) {
            
            UIButton *button = _scrubberHolderView.subviews[subViewindex];
            UIColor *color = [cue[@"important"] boolValue] ? [VKUtility colorWithHexString:@"#DA5C59"] : [VKUtility colorWithHexString:@"#F7ED82"];
            [button setTitleColor:color forState:UIControlStateNormal];
        }
    }
}

- (void)addCue:(NSDictionary *)cue atIndex:(NSInteger)index {
    
    NSNumber *number = cue[@"duration"];
    NSInteger sec = [number integerValue];
    float x = (sec / _videoDuration) * CGRectGetWidth(self.scrubber.bounds);
    
    x+= CGRectGetMinX(self.scrubber.frame);
    
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.tag = index + 1; // 1 based index;
    button.frame = [VKSharedUtility isPad] ? CGRectMake(x-15, 0, 30, 50) : CGRectMake(x-10, 0, 20, 40);
    
    button.titleLabel.font = [UIFont fontWithName:@"robo" size:[VKSharedUtility isPad] ? 40.0 : 28.0];
    [button setTitle:@"Ë" forState:UIControlStateNormal];
    
    UIColor *color = [cue[@"important"] boolValue] ? [VKUtility colorWithHexString:@"#DA5C59"] : [VKUtility colorWithHexString:@"#F7ED82"];
    [button setTitleColor:color forState:UIControlStateNormal];
    [button addTarget:self action:@selector(noteCueTapped:) forControlEvents:UIControlEventTouchUpInside];
    
    [_scrubberHolderView addSubview:button];
}

- (IBAction)playButtonTapped:(id)sender {
    
    UIButton* playButton;
    if ([sender isKindOfClass:[UIButton class]]) {
        playButton = (UIButton*)sender;
    }
    
    if (playButton.selected)  {
        [self.delegate playButtonPressed];
        [self setPlayButtonsSelected:NO];
    } else {
        [self.delegate pauseButtonPressed];
        [self setPlayButtonsSelected:YES];
    }
}

- (IBAction)addNoteButtonTapped:(UIButton *)sender {
    
    if ([VKSharedUtility isPad]) {
        [self.delegate noteButtonTapped];
    } else {
        
        if (self.fullscreenButton.selected) {
            [self fullscreenButtonTapped:self.fullscreenButton];
        }
        [self.delegate noteButtonTapped];
    }
}

- (void)noteCueTapped:(UIButton *)button {
    
    // Pause video before opening VNote
    [self.delegate pauseButtonPressed];
    [self setPlayButtonsSelected:YES];
    
    NSDictionary *cue = _cuesArray[button.tag-1];
    if ([VKSharedUtility isPad]) {
        [self.delegate noteSelected:cue[@"cueId"]];
    } else {
        if (self.fullscreenButton.selected) {
            [self fullscreenButtonTapped:self.fullscreenButton];
        }
        [self.delegate noteSelected:cue[@"cueId"]];
    }
}

- (void)callNoteButtonTappedWithDelay {
    [self.delegate noteButtonTapped];
}

- (void)callNoteSelectedWithDelay:(NSString *)noteId {
    [self.delegate noteSelected:noteId];
}


- (IBAction)fullscreenButtonTapped:(id)sender {
    self.fullscreenButton.selected = !self.fullscreenButton.selected;
    [self.delegate fullScreenButtonTapped];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (object == self.scrubber) {
        if ([keyPath isEqualToString:@"maximumValue"]) {
            DDLogVerbose(@"scrubber Value change: %f", self.scrubber.value);
            RUN_ON_UI_THREAD(^{
                [self updateTimeLabels];
            });
        }
    }
}

- (void)setDelegate:(id<VKVideoPlayerViewDelegate>)delegate {
    _delegate = delegate;
    self.scrubber.delegate = delegate;
}

- (void)durationDidLoad:(NSNotification *)notification {
    NSDictionary *info = [notification userInfo];
    NSNumber* duration = [info objectForKey:@"duration"];
    [self.delegate videoTrack].totalVideoDuration = duration;
    RUN_ON_UI_THREAD(^{
        self.scrubber.maximumValue = [duration floatValue];
        self.scrubber.hidden = NO;
    });
}

- (void)scrubberValueUpdated:(NSNotification *)notification {
    NSDictionary *info = [notification userInfo];
    RUN_ON_UI_THREAD(^{
        DDLogVerbose(@"scrubberValueUpdated: %@", [info objectForKey:@"scrubberValue"]);
        [self.scrubber setValue:[[info objectForKey:@"scrubberValue"] floatValue] animated:YES];
        [self updateTimeLabels];
    });
}

- (void)updateTimeLabels {
    DDLogVerbose(@"Updating TimeLabels: %f", self.scrubber.value);
    
    self.currentTimeLabel.text = [VKSharedUtility timeStringFromSecondsValue:(int)self.scrubber.value];
    self.totalTimeLabel.text = [VKSharedUtility timeStringFromSecondsValue:(int)self.scrubber.maximumValue];
    
    [self layoutSlider];
}

- (void)layoutSliderForOrientation:(UIInterfaceOrientation)interfaceOrientation {
    if (UIInterfaceOrientationIsPortrait(interfaceOrientation)) {
    } else {
    }
}

- (void)layoutSlider {
    [self layoutSliderForOrientation:self.delegate.visibleInterfaceOrientation];
}

- (void)setPlayButtonsSelected:(BOOL)selected {
    self.playButton.selected = selected;
    self.bigPlayButton.selected = selected;
    self.bigPlayButton2.selected = selected;
}

- (void)setPlayButtonsEnabled:(BOOL)enabled {
    self.playButton.enabled = enabled;
    self.bigPlayButton.enabled = enabled;
    self.bigPlayButton2.enabled = enabled;
}

- (void)setControlsEnabled:(BOOL)enabled {
    
    [self setPlayButtonsEnabled:enabled];
    
    self.scrubber.enabled = enabled;
    self.fullscreenButton.enabled = enabled;
    
    self.isControlsEnabled = enabled;
    
    NSMutableArray *controlList = self.customControls.mutableCopy;
    [controlList addObjectsFromArray:self.portraitControls];
    [controlList addObjectsFromArray:self.landscapeControls];
    for (UIView *control in controlList) {
        if ([control isKindOfClass:[UIButton class]]) {
            UIButton *button = (UIButton*)control;
            button.enabled = enabled;
        }
    }
}

- (IBAction)handleSingleTap:(id)sender {
    [self setControlsHidden:!self.isControlsHidden];
    if (!self.isControlsHidden) {
        self.controlHideCountdown = [self.playerControlsAutoHideTime integerValue];
    }
    [self.delegate playerViewSingleTapped];
}

- (IBAction)handleSwipeLeft:(id)sender {
    [self.delegate nextTrackBySwipe];
}

- (IBAction)handleSwipeRight:(id)sender {
    [self.delegate previousTrackBySwipe];
}

- (void)setControlHideCountdown:(NSInteger)controlHideCountdown {
    if (controlHideCountdown == 0) {
        [self setControlsHidden:YES];
    } else {
        [self setControlsHidden:NO];
    }
    _controlHideCountdown = controlHideCountdown;
}

- (void)hideControlsIfNecessary {
    if (self.isControlsHidden) return;
    if (self.controlHideCountdown == -1) {
        [self setControlsHidden:NO];
    } else if (self.controlHideCountdown == 0) {
        [self setControlsHidden:YES];
    } else {
        self.controlHideCountdown--;
    }
}

- (void)setControlsHidden:(BOOL)hidden {
    DDLogVerbose(@"Controls: %@", hidden ? @"hidden" : @"visible");
    
    if (self.isControlsHidden != hidden) {
        self.isControlsHidden = hidden;
        self.controls.hidden = hidden;
        
        if (UIInterfaceOrientationIsLandscape(self.delegate.visibleInterfaceOrientation)) {
            for (UIView *control in self.landscapeControls) {
                control.hidden = hidden;
            }
        }
        if (UIInterfaceOrientationIsPortrait(self.delegate.visibleInterfaceOrientation)) {
            for (UIView *control in self.portraitControls) {
                control.hidden = hidden;
            }
        }
        for (UIView *control in self.customControls) {
            control.hidden = hidden;
        }
    }
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    if ([touch.view isKindOfClass:[VKScrubber class]] ||
        [touch.view isKindOfClass:[UIButton class]]) {
        // prevent recognizing touches on the slider
        return NO;
    }
    return YES;
}

- (void)layoutForOrientation:(UIInterfaceOrientation)interfaceOrientation {
    if (UIInterfaceOrientationIsPortrait(interfaceOrientation)) {
    }
    
    [self layoutSliderForOrientation:interfaceOrientation];
}

- (void)addSubviewForControl:(UIView *)view {
    [self addSubviewForControl:view toView:self];
}
- (void)addSubviewForControl:(UIView *)view toView:(UIView*)parentView {
    [self addSubviewForControl:view toView:parentView forOrientation:UIInterfaceOrientationMaskAll];
}
- (void)addSubviewForControl:(UIView *)view toView:(UIView*)parentView forOrientation:(UIInterfaceOrientationMask)orientation {
    view.hidden = self.isControlsHidden;
    if (orientation == UIInterfaceOrientationMaskAll) {
        [self.customControls addObject:view];
    } else if (orientation == UIInterfaceOrientationMaskPortrait) {
        [self.portraitControls addObject:view];
    } else if (orientation == UIInterfaceOrientationMaskLandscape) {
        [self.landscapeControls addObject:view];
    }
    [parentView addSubview:view];
}
- (void)removeControlView:(UIView*)view {
    [view removeFromSuperview];
    [self.customControls removeObject:view];
    [self.landscapeControls removeObject:view];
    [self.portraitControls removeObject:view];
}

+ (UIColor *)colorFromHexString:(NSString *)hexCode{
    
    unsigned rgbValue = 0;
    NSScanner *scanner = [NSScanner scannerWithString:hexCode];
    [scanner setScanLocation:1]; // bypass '#' character
    [scanner scanHexInt:&rgbValue]; // Convert string to hexInt
    return [UIColor colorWithRed:((rgbValue & 0xFF0000) >> 16)/255.0
                           green:((rgbValue & 0xFF00) >> 8)/255.0
                            blue:(rgbValue & 0xFF)/255.0
                           alpha:1.0];
}

@end
