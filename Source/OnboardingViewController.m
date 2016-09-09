//
//  OnboardingViewController.m
//  Onboard
//
//  Created by Mike on 8/17/14.
//  Copyright (c) 2014 Mike Amaral. All rights reserved.
//

#import "OnboardingViewController.h"
#import "OnboardingContentViewController.h"
@import AVFoundation;
@import Accelerate;

static CGFloat const kPageControlHeight = 35;
static CGFloat const kSkipButtonWidth = 100;
static CGFloat const kSkipButtonHeight = 44;
static CGFloat const kBackgroundMaskAlpha = 0.6;

static NSString * const kSkipButtonText = @"Skip";


@interface OnboardingViewController ()

@property (nonatomic, strong) OnboardingContentViewController *currentPage;
@property (nonatomic, strong) OnboardingContentViewController *upcomingPage;

@property (nonatomic, strong) UIPageViewController *pageVC;
@property (nonatomic, weak) UIImageView *backgroundImageView;
@property (nonatomic, weak) UIView *backgroundMaskView;
@property (nonatomic, strong) UIVisualEffectView *blurEffectView;
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) NSURL *videoURL;

@end


@implementation OnboardingViewController

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Initializing with images

+ (instancetype)onboardWithBackgroundImage:(UIImage *)backgroundImage contents:(NSArray *)contents {
    return [[self alloc] initWithBackgroundImage:backgroundImage contents:contents];
 }

- (instancetype)initWithBackgroundImage:(UIImage *)backgroundImage contents:(NSArray *)contents {
    self = [self initWithContents:contents];

    if (self == nil) {
        return nil;
    }

    self.backgroundImage = backgroundImage;
    
    return self;
}


#pragma mark - Initializing with video files

+ (instancetype)onboardWithBackgroundVideoURL:(NSURL *)backgroundVideoURL contents:(NSArray *)contents {
    return [[self alloc] initWithBackgroundVideoURL:backgroundVideoURL contents:contents];
}

- (instancetype)initWithBackgroundVideoURL:(NSURL *)backgroundVideoURL contents:(NSArray *)contents {
    self = [self initWithContents:contents];

    if (self == nil) {
        return nil;
    }

    self.videoURL = backgroundVideoURL;
    
    return self;
}


#pragma mark - Initialization

- (instancetype)initWithContents:(NSArray *)contents {
    self = [super init];

    if (self == nil) {
        return nil;
    }
    
    // Store the passed in view controllers array
    self.viewControllers = contents;
    
    // Set the default properties
    self.shouldMaskBackground = YES;
    self.shouldBlurBackground = NO;
    self.shouldFadeTransitions = NO;
    self.fadePageControlOnLastPage = NO;
    self.fadeSkipButtonOnLastPage = NO;
    self.swipingEnabled = YES;
    
    self.allowSkipping = NO;
    self.skipHandler = ^{};
    
    // Create the initial exposed components so they can be customized
    self.pageControl = [UIPageControl new];
    self.pageControl.numberOfPages = self.viewControllers.count;
    self.pageControl.userInteractionEnabled = NO;

    self.skipButton = [UIButton new];
    [self.skipButton setTitle:kSkipButtonText forState:UIControlStateNormal];
    [self.skipButton addTarget:self action:@selector(handleSkipButtonPressed) forControlEvents:UIControlEventTouchUpInside];
    self.skipButton.titleLabel.adjustsFontSizeToFitWidth = YES;
    
    return self;
}


#pragma mark - View life cycle

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // now that the view has loaded, we can generate the content
    [self generateView];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    // if we have a video URL, start playing
    if (self.videoURL) {
        [self.player play];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];

    if ((self.player.rate != 0.0) && (self.player.error == nil) && self.stopMoviePlayerWhenDisappear) {
        [self.player pause];
    }
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    self.pageVC.view.frame = self.view.bounds;
    self.moviePlayerController.view.frame = self.view.bounds;
    self.skipButton.frame = CGRectMake(CGRectGetMaxX(self.view.bounds) - kSkipButtonWidth, CGRectGetMaxY(self.view.bounds) - self.underPageControlPadding - kSkipButtonHeight, kSkipButtonWidth, kSkipButtonHeight);
    self.pageControl.frame = CGRectMake(0, CGRectGetMaxY(self.view.bounds) - self.underPageControlPadding - kPageControlHeight, self.view.bounds.size.width, kPageControlHeight);
    self.backgroundImageView.frame = self.view.bounds;
    self.backgroundMaskView.frame = self.pageVC.view.frame;
    self.blurEffectView.frame = self.view.bounds;
}

- (void)generateView {
    // create our page view controller
    self.pageVC = [[UIPageViewController alloc] initWithTransitionStyle:UIPageViewControllerTransitionStyleScroll navigationOrientation:UIPageViewControllerNavigationOrientationHorizontal options:nil];
    self.pageVC.view.backgroundColor = [UIColor whiteColor];
    self.pageVC.delegate = self;
    self.pageVC.dataSource = self.swipingEnabled ? self : nil;
    
    // create the background image view and set it to aspect fill so it isn't skewed
    if (self.backgroundImage) {
        if (!_backgroundImageView) {
            UIImageView *backgroundImageView;
            backgroundImageView = [[UIImageView alloc] initWithFrame:CGRectZero];
            backgroundImageView.clipsToBounds = YES;
            backgroundImageView.contentMode = UIViewContentModeScaleAspectFit;
            [self.view addSubview:backgroundImageView];
//            backgroundImageView.alpha = 0.5f;
            _backgroundImageView = backgroundImageView;
        }
        [self.backgroundImageView setImage:self.backgroundImage];
    }else{
        [self.backgroundImageView removeFromSuperview];
        self.backgroundImageView = nil;
    }
    
    // as long as the shouldMaskBackground setting hasn't been set to NO, we want to
    // create a partially opaque view and add it on top of the image view, so that it
    // darkens it a bit for better contrast
    if (self.shouldMaskBackground) {
        if (!_backgroundMaskView) {
            UIView *backgroundMaskView = [[UIView alloc] initWithFrame:self.pageVC.view.frame];
            backgroundMaskView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:kBackgroundMaskAlpha];
            [self.pageVC.view addSubview:backgroundMaskView];
            _backgroundMaskView = backgroundMaskView;
        }
    }else{
        [self.backgroundMaskView removeFromSuperview];
        self.backgroundMaskView = nil;
    }

    // set ourself as the delegate on all of the content views, to handle fading
    // and auto-navigation
    for (OnboardingContentViewController *contentVC in self.viewControllers) {
        contentVC.delegate = self;
    }

    // set the initial current page as the first page provided
    _currentPage = [self.viewControllers firstObject];
    
    // more page controller setup
    [self.pageVC setViewControllers:@[self.currentPage] direction:UIPageViewControllerNavigationDirectionForward animated:YES completion:nil];
    self.pageVC.view.backgroundColor = [UIColor clearColor];
    [self addChildViewController:self.pageVC];
    [self.view addSubview:self.pageVC.view];
    [self.pageVC didMoveToParentViewController:self];
    [self.pageVC.view sendSubviewToBack:self.backgroundMaskView];
    
    // send the background image view to the back if we have one
    if (self.backgroundImageView) {
        [self.pageVC.view sendSubviewToBack:self.backgroundImageView];
    }
    
    // otherwise send the video view to the back if we have one
    else if (self.videoURL) {
        self.player = [[AVPlayer alloc] initWithURL:self.videoURL];

        self.moviePlayerController = [AVPlayerViewController new];
        self.moviePlayerController.player = self.player;
        self.moviePlayerController.showsPlaybackControls = NO;
        
        [self.pageVC.view addSubview:self.moviePlayerController.view];
        [self.pageVC.view sendSubviewToBack:self.moviePlayerController.view];
    }
    
    // create and configure the page control
    [self.view addSubview:self.pageControl];
    
    // if we allow skipping, setup the skip button
    if (self.allowSkipping) {
        [self.view addSubview:self.skipButton];
    }
    
    if (self.shouldBlurBackground && !UIAccessibilityIsReduceTransparencyEnabled()) {
        if (!_blurEffectView) {
            UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleExtraLight];
            UIVisualEffectView *blurEffectView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
            blurEffectView.alpha = 0.65f;
//            [self.view addSubview:blurEffectView];
            [self.view insertSubview:blurEffectView belowSubview:self.pageVC.view];
            _blurEffectView = blurEffectView;
        }
    }else{
        [self.blurEffectView removeFromSuperview];
        self.blurEffectView = nil;
    }
    
    // if we want to fade the transitions, we need to tap into the underlying scrollview
    // so we can set ourself as the delegate, this is sort of hackish but the only current
    // solution I am aware of using a page view controller
    if (self.shouldFadeTransitions) {
        for (UIView *view in self.pageVC.view.subviews) {
            if ([view isKindOfClass:[UIScrollView class]]) {
                [(UIScrollView *)view setDelegate:self];
            }
        }
    }
}


#pragma mark - Skipping

- (void)handleSkipButtonPressed {
    NSLog(@"%s, %@", __FUNCTION__, self.skipHandler ? @"exists" : @"not exists");
    if (self.skipHandler) {
        NSLog(@"1");
        self.skipHandler();
    }
}


#pragma mark - Convenience setters for content pages

- (void)setIconSize:(CGFloat)iconSize {
    for (OnboardingContentViewController *contentVC in self.viewControllers) {
        contentVC.iconWidth = iconSize;
        contentVC.iconHeight = iconSize;
    }
}

- (void)setIconWidth:(CGFloat)iconWidth {
    for (OnboardingContentViewController *contentVC in self.viewControllers) {
        contentVC.iconWidth = iconWidth;
    }
}

- (void)setIconHeight:(CGFloat)iconHeight {
    for (OnboardingContentViewController *contentVC in self.viewControllers) {
        contentVC.iconHeight = iconHeight;
    }
}

- (void)setTitleTextColor:(UIColor *)titleTextColor {
    for (OnboardingContentViewController *contentVC in self.viewControllers) {
        contentVC.titleTextColor = titleTextColor;
    }
}

- (void)setBodyTextColor:(UIColor *)bodyTextColor {
    for (OnboardingContentViewController *contentVC in self.viewControllers) {
        contentVC.bodyTextColor = bodyTextColor;
    }
}

- (void)setButtonTextColor:(UIColor *)buttonTextColor {
    for (OnboardingContentViewController *contentVC in self.viewControllers) {
        contentVC.buttonTextColor = buttonTextColor;
    }
}

- (void)setFontName:(NSString *)fontName {
    for (OnboardingContentViewController *contentVC in self.viewControllers) {
        contentVC.titleFontName = fontName;
        contentVC.bodyFontName = fontName;
        contentVC.buttonFontName = fontName;
    }
}

- (void)setTitleFontName:(NSString *)fontName {
    for (OnboardingContentViewController *contentVC in self.viewControllers) {
        contentVC.titleFontName = fontName;
    }
}

- (void)setTitleFontSize:(CGFloat)titleFontSize {
    for (OnboardingContentViewController *contentVC in self.viewControllers) {
        contentVC.titleFontSize = titleFontSize;
    }
}

- (void)setBodyFontName:(NSString *)fontName {
    for (OnboardingContentViewController *contentVC in self.viewControllers) {
        contentVC.bodyFontName = fontName;
    }
}

- (void)setBodyFontSize:(CGFloat)bodyFontSize {
    for (OnboardingContentViewController *contentVC in self.viewControllers) {
        contentVC.bodyFontSize = bodyFontSize;
    }
}

- (void)setButtonFontName:(NSString *)fontName {
    for (OnboardingContentViewController *contentVC in self.viewControllers) {
        contentVC.buttonFontName = fontName;
    }
}

- (void)setButtonFontSize:(CGFloat)bodyFontSize {
    for (OnboardingContentViewController *contentVC in self.viewControllers) {
        contentVC.buttonFontSize = bodyFontSize;
    }
}

- (void)setTopPadding:(CGFloat)topPadding {
    for (OnboardingContentViewController *contentVC in self.viewControllers) {
        contentVC.topPadding = topPadding;
    }
}

- (void)setUnderIconPadding:(CGFloat)underIconPadding {
    for (OnboardingContentViewController *contentVC in self.viewControllers) {
        contentVC.underIconPadding = underIconPadding;
    }
}

- (void)setUnderTitlePadding:(CGFloat)underTitlePadding {
    for (OnboardingContentViewController *contentVC in self.viewControllers) {
        contentVC.underTitlePadding = underTitlePadding;
    }
}

- (void)setBottomPadding:(CGFloat)bottomPadding {
    for (OnboardingContentViewController *contentVC in self.viewControllers) {
        contentVC.bottomPadding = bottomPadding;
    }
}

- (void)setUnderPageControlPadding:(CGFloat)underPageControlPadding {
    _underPageControlPadding = underPageControlPadding;

    for (OnboardingContentViewController *contentVC in self.viewControllers) {
        contentVC.underPageControlPadding = underPageControlPadding;
    }
}

#pragma mark - Page view controller data source

- (UIViewController *)pageViewController:(UIPageViewController *)pageViewController viewControllerBeforeViewController:(UIViewController *)viewController {
    // return the previous view controller in the array unless we're at the beginning
    if (viewController == [self.viewControllers firstObject]) {
        return nil;
    } else {
        NSInteger priorPageIndex = [self.viewControllers indexOfObject:viewController] - 1;
        return self.viewControllers[priorPageIndex];
    }
}

- (UIViewController *)pageViewController:(UIPageViewController *)pageViewController viewControllerAfterViewController:(UIViewController *)viewController {
    // return the next view controller in the array unless we're at the end
    if (viewController == [self.viewControllers lastObject]) {
        return nil;
    } else {
        NSInteger nextPageIndex = [_viewControllers indexOfObject:viewController] + 1;
        return self.viewControllers[nextPageIndex];
    }
}


#pragma mark - Page view controller delegate

- (void)pageViewController:(UIPageViewController *)pageViewController didFinishAnimating:(BOOL)finished previousViewControllers:(NSArray *)previousViewControllers transitionCompleted:(BOOL)completed {
    // if we haven't completed animating yet, we don't want to do anything because it could be cancelled
    if (!completed) {
        return;
    }
    
    // get the view controller we are moving towards, then get the index, then set it as the current page
    // for the page control dots
    UIViewController *viewController = [pageViewController.viewControllers lastObject];
    NSInteger newIndex = [self.viewControllers indexOfObject:viewController];
    [self.pageControl setCurrentPage:newIndex];
}

- (void)moveNextPage {
    NSUInteger indexOfNextPage = [self.viewControllers indexOfObject:_currentPage] + 1;
    
    if (indexOfNextPage < self.viewControllers.count) {
        [self.pageVC setViewControllers:@[self.viewControllers[indexOfNextPage]] direction:UIPageViewControllerNavigationDirectionForward animated:YES completion:nil];
        [self.pageControl setCurrentPage:indexOfNextPage];
    }
}


#pragma mark - Page scroll status

- (void)setCurrentPage:(OnboardingContentViewController *)currentPage {
    _currentPage = currentPage;
}

- (void)setNextPage:(OnboardingContentViewController *)nextPage {
    _upcomingPage = nextPage;
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    // calculate the percent complete of the transition of the current page given the
    // scrollview's offset and the width of the screen
    CGFloat percentComplete = fabs(scrollView.contentOffset.x - self.view.frame.size.width) / self.view.frame.size.width;
    CGFloat percentCompleteInverse = 1.0 - percentComplete;
    
    // these cases have some funky results given the way this method is called, like stuff
    // just disappearing, so we want to do nothing in these cases
    if (percentComplete == 0) {
        return;
    }

    // set the next page's alpha to be the percent complete, so if we're 90% of the way
    // scrolling towards the next page, its content's alpha should be 90%
    [_upcomingPage updateAlphas:percentComplete];
    
    // set the current page's alpha to the difference between 100% and this percent value,
    // so we're 90% scrolling towards the next page, the current content's alpha sshould be 10%
    [_currentPage updateAlphas:percentCompleteInverse];

    // determine if we're transitioning to or from our last page
    BOOL transitioningToLastPage = (_currentPage != self.viewControllers.lastObject && _upcomingPage == self.viewControllers.lastObject);
    BOOL transitioningFromLastPage = (_currentPage == self.viewControllers.lastObject) && (_upcomingPage == self.viewControllers[self.viewControllers.count - 2]);
    
    // fade the page control to and from the last page
    if (self.fadePageControlOnLastPage) {
        if (transitioningToLastPage) {
            self.pageControl.alpha = percentCompleteInverse;
        }

        else if (transitioningFromLastPage) {
            self.pageControl.alpha = percentComplete;
        }
    }

    // fade the skip button to and from the last page
    if (self.fadeSkipButtonOnLastPage) {
        if (transitioningToLastPage) {
            self.skipButton.alpha = percentCompleteInverse;
        }

        else if (transitioningFromLastPage) {
            self.skipButton.alpha = percentComplete;
        }
    }
}

@end
