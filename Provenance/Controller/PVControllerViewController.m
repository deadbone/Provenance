//
//  PVControllerViewController.m
//  Provenance
//
//  Created by James Addyman on 03/09/2013.
//  Copyright (c) 2013 James Addyman. All rights reserved.
//

#import "PVControllerViewController.h"
#import "PVEmulatorConfiguration.h"
#import "PVButtonGroupOverlayView.h"
#import "Provenance-Swift.h"
#import <PVSupport/NSObject+PVAbstractAdditions.h>
#import "UIView+FrameAdditions.h"
#import <QuartzCore/QuartzCore.h>
#import <AudioToolbox/AudioToolbox.h>
#import "PVControllerManager.h"
#import <PVSupport/PVEmulatorCore.h>
#import "PVEmulatorConstants.h"
#import "UIDevice+Hardware.h"

@interface PVControllerViewController ()

@property (nonatomic, strong) NSArray *controlLayout;

@end

@implementation PVControllerViewController

- (id)initWithControlLayout:(NSArray *)controlLayout systemIdentifier:(NSString *)systemIdentifier
{
	if ((self = [super initWithNibName:nil bundle:nil]))
	{
		self.controlLayout = controlLayout;
        self.systemIdentifier = systemIdentifier;
	}
	
	return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [[GCController controllers] makeObjectsPerformSelector:@selector(setControllerPausedHandler:) withObject:NULL];
}

- (void) viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
}

- (void)viewDidLoad
{
	[super viewDidLoad];
	
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(controllerDidConnect:)
												 name:GCControllerDidConnectNotification
											   object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(controllerDidDisconnect:)
												 name:GCControllerDidDisconnectNotification
											   object:nil];

#if !TARGET_OS_TV
	if (NSClassFromString(@"UISelectionFeedbackGenerator")) {
		self.feedbackGenerator = [[UISelectionFeedbackGenerator alloc] init];
		[self.feedbackGenerator prepare];
	}
#endif

	if ([[PVControllerManager sharedManager] hasControllers])
	{
		[self hideTouchControlsForController:[[PVControllerManager sharedManager] player1]];
		[self hideTouchControlsForController:[[PVControllerManager sharedManager] player2]];
	}
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
	return UIInterfaceOrientationMaskLandscape;
}

- (void)didMoveToParentViewController:(UIViewController *)parent
{
	[super didMoveToParentViewController:parent];
	
	[self.view setFrame:[[self.view superview] bounds]];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    
    [self setupTouchControls];

    if ([[PVControllerManager sharedManager] hasControllers])
    {
        [self hideTouchControlsForController:[[PVControllerManager sharedManager] player1]];
        [self hideTouchControlsForController:[[PVControllerManager sharedManager] player2]];
    }
}

# pragma mark - Controller Position And Size Editing

- (void)setupTouchControls
{
#if !TARGET_OS_TV
    
    UIEdgeInsets safeAreaInsets = UIEdgeInsetsZero;
    if (@available(iOS 11.0, *)) {
        safeAreaInsets = self.view.safeAreaInsets;
    }
    
	CGFloat alpha = [[PVSettingsModel sharedInstance] controllerOpacity];
	
	for (NSDictionary *control in self.controlLayout)
	{
		NSString *controlType = [control objectForKey:PVControlTypeKey];
        CGSize controlSize = CGSizeFromString([control objectForKey:PVControlSizeKey]);

		BOOL compactVertical = self.traitCollection.verticalSizeClass == UIUserInterfaceSizeClassCompact;
		CGFloat kDPadTopMargin = 96.0;
		CGFloat controlOriginY = compactVertical ? self.view.bounds.size.height - controlSize.height : CGRectGetWidth(self.view.frame) + (kDPadTopMargin / 2);
		
		if ([controlType isEqualToString:PVDPad])
		{
			CGFloat xPadding = safeAreaInsets.left + 5;
			CGFloat bottomPadding = 16;
			CGFloat dPadOriginY = MIN(controlOriginY - bottomPadding, CGRectGetHeight(self.view.frame) - controlSize.height - bottomPadding);
			CGRect dPadFrame = CGRectMake(xPadding, dPadOriginY, controlSize.width, controlSize.height);
			
#if 1                 // Wonderswan dual D-Pad hack.
            if (!self.dPad2 && [[control objectForKey:PVControlTitleKey] isEqualToString:@"Y"])
            {
                dPadFrame.origin.y = dPadOriginY - controlSize.height - bottomPadding;
                self.dPad2 = [[JSDPad alloc] initWithFrame:dPadFrame];
                [self.dPad2 setDelegate:self];
                [self.dPad2 setAlpha:alpha];
                [self.dPad2 setAutoresizingMask:UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleRightMargin];
                [self.view addSubview:self.dPad2];
            }
            else
#endif
            if (!self.dPad)
			{
				self.dPad = [[JSDPad alloc] initWithFrame:dPadFrame];
				[self.dPad setDelegate:self];
				[self.dPad setAlpha:alpha];
				[self.dPad setAutoresizingMask:UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleRightMargin];
				[self.view addSubview:self.dPad];
            }
			else
			{
				[self.dPad setFrame:dPadFrame];
			}
            
            self.dPad2.hidden = compactVertical;
		}
		else if ([controlType isEqualToString:PVButtonGroup])
		{
			CGFloat xPadding = safeAreaInsets.right + 5;
			CGFloat bottomPadding = 16;
			
			CGFloat buttonsOriginY = MIN(controlOriginY - bottomPadding, CGRectGetHeight(self.view.frame) - controlSize.height - bottomPadding);
			CGRect buttonsFrame = CGRectMake(CGRectGetMaxX(self.view.bounds) - controlSize.width - xPadding, buttonsOriginY, controlSize.width, controlSize.height);
			
			if (!self.buttonGroup)
			{
				self.buttonGroup = [[UIView alloc] initWithFrame:buttonsFrame];
				[self.buttonGroup setAutoresizingMask:UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleLeftMargin];
				
				NSArray *groupedButtons = [control objectForKey:PVGroupedButtonsKey];
				for (NSDictionary *groupedButton in groupedButtons)
				{
					CGRect buttonFrame = CGRectFromString([groupedButton objectForKey:PVControlFrameKey]);
					JSButton *button = [[JSButton alloc] initWithFrame:buttonFrame];
					[[button titleLabel] setText:[groupedButton objectForKey:PVControlTitleKey]];
					[button setBackgroundImage:[UIImage imageNamed:@"button"]];
					[button setBackgroundImagePressed:[UIImage imageNamed:@"button-pressed"]];
					[button setDelegate:self];
					[self.buttonGroup addSubview:button];
				}
				
				PVButtonGroupOverlayView *buttonOverlay = [[PVButtonGroupOverlayView alloc] initWithButtons:[self.buttonGroup subviews]];
				[buttonOverlay setSize:[self.buttonGroup bounds].size];
				[self.buttonGroup addSubview:buttonOverlay];
				[self.buttonGroup setAlpha:alpha];
				[self.view addSubview:self.buttonGroup];
			}
			else
			{
				[self.buttonGroup setFrame:buttonsFrame];
			}
		}
		else if ([controlType isEqualToString:PVLeftShoulderButton])
		{
			CGFloat xPadding = safeAreaInsets.left + 10;
			CGFloat yPadding = safeAreaInsets.top + 10;

			CGRect leftShoulderFrame = CGRectMake(xPadding, yPadding, controlSize.width, controlSize.height);
			
			if (!self.leftShoulderButton)
			{
				self.leftShoulderButton = [[JSButton alloc] initWithFrame:leftShoulderFrame];
				[[self.leftShoulderButton titleLabel] setText:[control objectForKey:PVControlTitleKey]];
				[self.leftShoulderButton setBackgroundImage:[UIImage imageNamed:@"button-thin"]];
				[self.leftShoulderButton setBackgroundImagePressed:[UIImage imageNamed:@"button-thin-pressed"]];
				[self.leftShoulderButton setDelegate:self];
				[self.leftShoulderButton setTitleEdgeInsets:UIEdgeInsetsMake(0, 0, 4, 0)];
				[self.leftShoulderButton setAlpha:alpha];
				[self.leftShoulderButton setAutoresizingMask:UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleRightMargin];
				[self.view addSubview:self.leftShoulderButton];
			}
//            else if (!self.leftShoulderButton2)
//            {
//                yPadding = yPadding + self.leftShoulderButton.frame.size.height + 20;
//                CGRect leftShoulderFrame = CGRectMake(self.view.frame.size.width - controlSize.width - xPadding, yPadding, controlSize.width, controlSize.height);
//
//                self.leftShoulderButton2 = [[JSButton alloc] initWithFrame:leftShoulderFrame];
//                [[self.leftShoulderButton2 titleLabel] setText:[control objectForKey:PVControlTitleKey]];
//                [self.leftShoulderButton2 setBackgroundImage:[UIImage imageNamed:@"button-thin"]];
//                [self.leftShoulderButton2 setBackgroundImagePressed:[UIImage imageNamed:@"button-thin-pressed"]];
//                [self.leftShoulderButton2 setDelegate:self];
//                [self.leftShoulderButton2 setTitleEdgeInsets:UIEdgeInsetsMake(0, 0, 4, 0)];
//                [self.leftShoulderButton2 setAlpha:alpha];
//                [self.leftShoulderButton2 setAutoresizingMask:UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleLeftMargin];
//                [self.view addSubview:self.leftShoulderButton2];
//            }
			else
			{
				[self.leftShoulderButton setFrame:leftShoulderFrame];
			}
		}
		else if ([controlType isEqualToString:PVRightShoulderButton])
		{
			CGFloat xPadding = safeAreaInsets.right + 10;
			CGFloat yPadding = safeAreaInsets.top + 10;
			
			if (!self.rightShoulderButton)
			{
                CGRect rightShoulderFrame = CGRectMake(self.view.frame.size.width - controlSize.width - xPadding, yPadding, controlSize.width, controlSize.height);

				self.rightShoulderButton = [[JSButton alloc] initWithFrame:rightShoulderFrame];
				[[self.rightShoulderButton titleLabel] setText:[control objectForKey:PVControlTitleKey]];
				[self.rightShoulderButton setBackgroundImage:[UIImage imageNamed:@"button-thin"]];
				[self.rightShoulderButton setBackgroundImagePressed:[UIImage imageNamed:@"button-thin-pressed"]];
				[self.rightShoulderButton setDelegate:self];
				[self.rightShoulderButton setTitleEdgeInsets:UIEdgeInsetsMake(0, 0, 4, 0)];
				[self.rightShoulderButton setAlpha:alpha];
				[self.rightShoulderButton setAutoresizingMask:UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleLeftMargin];
				[self.view addSubview:self.rightShoulderButton];
			}
//            else if (!self.rightShoulderButton2)
//            {
//                yPadding = yPadding + self.rightShoulderButton.frame.size.height + 20;
//                CGRect rightShoulderFrame = CGRectMake(self.view.frame.size.width - controlSize.width - xPadding, yPadding, controlSize.width, controlSize.height);
//
//                self.rightShoulderButton2 = [[JSButton alloc] initWithFrame:rightShoulderFrame];
//                [[self.rightShoulderButton2 titleLabel] setText:[control objectForKey:PVControlTitleKey]];
//                [self.rightShoulderButton2 setBackgroundImage:[UIImage imageNamed:@"button-thin"]];
//                [self.rightShoulderButton2 setBackgroundImagePressed:[UIImage imageNamed:@"button-thin-pressed"]];
//                [self.rightShoulderButton2 setDelegate:self];
//                [self.rightShoulderButton2 setTitleEdgeInsets:UIEdgeInsetsMake(0, 0, 4, 0)];
//                [self.rightShoulderButton2 setAlpha:alpha];
//                [self.rightShoulderButton2 setAutoresizingMask:UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleLeftMargin];
//                [self.view addSubview:self.rightShoulderButton2];
//            }
			else
			{
                CGRect rightShoulderFrame = CGRectMake(self.view.frame.size.width - controlSize.width - xPadding, yPadding, controlSize.width, controlSize.height);
				[self.rightShoulderButton setFrame:rightShoulderFrame];
			}
		}
		else if ([controlType isEqualToString:PVStartButton])
		{
            CGFloat yPadding = MAX(safeAreaInsets.bottom , 10);
			CGRect startFrame = CGRectMake((self.view.frame.size.width - controlSize.width) / 2,
                                           self.view.frame.size.height - controlSize.height - yPadding,
                                           controlSize.width,
                                           controlSize.height);
			
			if (!self.startButton)
			{
				self.startButton = [[JSButton alloc] initWithFrame:startFrame];
				[[self.startButton titleLabel] setText:[control objectForKey:PVControlTitleKey]];
				[self.startButton setBackgroundImage:[UIImage imageNamed:@"button-thin"]];
				[self.startButton setBackgroundImagePressed:[UIImage imageNamed:@"button-thin-pressed"]];
				[self.startButton setDelegate:self];
				[self.startButton setTitleEdgeInsets:UIEdgeInsetsMake(0, 0, 4, 0)];
				[self.startButton setAlpha:alpha];
				[self.startButton setAutoresizingMask:UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin];
				[self.view addSubview:self.startButton];
			}
			else
			{
				[self.startButton setFrame:startFrame];
			}
		}
		else if ([controlType isEqualToString:PVSelectButton])
		{
            CGFloat yPadding = MAX(safeAreaInsets.bottom, 10);
			CGFloat ySeparation = 10;
			CGRect selectFrame = CGRectMake((self.view.frame.size.width - controlSize.width) / 2,
                                            self.view.frame.size.height - yPadding - (controlSize.height * 2) - ySeparation,
                                            controlSize.width,
                                            controlSize.height);
			
			if (!self.selectButton)
			{
				self.selectButton = [[JSButton alloc] initWithFrame:selectFrame];
				[[self.selectButton titleLabel] setText:[control objectForKey:PVControlTitleKey]];
				[self.selectButton setBackgroundImage:[UIImage imageNamed:@"button-thin"]];
				[self.selectButton setBackgroundImagePressed:[UIImage imageNamed:@"button-thin-pressed"]];
				[self.selectButton setDelegate:self];
				[self.selectButton setTitleEdgeInsets:UIEdgeInsetsMake(0, 0, 4, 0)];
				[self.selectButton setAlpha:alpha];
				[self.selectButton setAutoresizingMask:UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin];
				[self.view addSubview:self.selectButton];
			}
			else
			{
				[self.selectButton setFrame:selectFrame];
			}
		}
	}
#endif
}

#pragma mark - GameController Notifications

- (void)controllerDidConnect:(NSNotification *)note
{
    if ([[PVControllerManager sharedManager] hasControllers])
    {
        [self hideTouchControlsForController:[[PVControllerManager sharedManager] player1]];
        [self hideTouchControlsForController:[[PVControllerManager sharedManager] player2]];
    }
    else
    {
        [self.dPad setHidden:NO];
        [self.dPad2 setHidden:self.traitCollection.verticalSizeClass == UIUserInterfaceSizeClassCompact];
        [self.buttonGroup setHidden:NO];
        [self.leftShoulderButton setHidden:NO];
        [self.rightShoulderButton setHidden:NO];
        [self.leftShoulderButton2 setHidden:NO];
        [self.rightShoulderButton2 setHidden:NO];
        [self.startButton setHidden:NO];
        [self.selectButton setHidden:NO];
    }
}

- (void)controllerDidDisconnect:(NSNotification *)note
{
    if ([[PVControllerManager sharedManager] hasControllers])
    {
        [self hideTouchControlsForController:[[PVControllerManager sharedManager] player1]];
        [self hideTouchControlsForController:[[PVControllerManager sharedManager] player2]];
    }
    else
    {
        [self.dPad setHidden:NO];
        [self.dPad2 setHidden:self.traitCollection.verticalSizeClass == UIUserInterfaceSizeClassCompact];
        [self.buttonGroup setHidden:NO];
        [self.leftShoulderButton setHidden:NO];
        [self.rightShoulderButton setHidden:NO];
        [self.leftShoulderButton2 setHidden:NO];
        [self.rightShoulderButton2 setHidden:NO];
        [self.startButton setHidden:NO];
        [self.selectButton setHidden:NO];
    }
}

#pragma mark - Controller handling

- (void)dPad:(JSDPad *)dPad didPressDirection:(JSDPadDirection)direction
{
	[self vibrate];
}

- (void)dPadDidReleaseDirection:(JSDPad *)dPad
{
}

- (void)buttonPressed:(JSButton *)button
{
	[self vibrate];
}

- (void)buttonReleased:(JSButton *)button
{
}

- (void)pressStartForPlayer:(NSUInteger)player
{
	[self vibrate];
}

- (void)releaseStartForPlayer:(NSUInteger)player
{
}

- (void)pressSelectForPlayer:(NSUInteger)player
{
	[self vibrate];
}

- (void)releaseSelectForPlayer:(NSUInteger)player
{
}

// These are private/undocumented API, so we need to expose them here
// Based on GBA4iOS 2.0 by Riley Testut
// https://bitbucket.org/rileytestut/gba4ios/src/6c363f7503ecc1e29a32f6869499113c3a3a6297/GBA4iOS/GBAControllerView.m?at=master#cl-245

void AudioServicesStopSystemSound(int);
void AudioServicesPlaySystemSoundWithVibration(int, id, NSDictionary *);

- (void)vibrate
{
#if !TARGET_OS_TV
	if ([[PVSettingsModel sharedInstance] buttonVibration])
	{
		// only iPhone 7 and 7 Plus support the taptic engine APIs for now.
		// everything else should fall back to the vibration motor.
		if ([UIDevice hasTapticMotor])
		{
			[self.feedbackGenerator selectionChanged];
		}
		else
		{
			AudioServicesStopSystemSound(kSystemSoundID_Vibrate);

			NSInteger vibrationLength = 30;
			NSArray *pattern = @[@NO, @0, @YES, @(vibrationLength)];

			NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
			dictionary[@"VibePattern"] = pattern;
			dictionary[@"Intensity"] = @1;

			AudioServicesPlaySystemSoundWithVibration(kSystemSoundID_Vibrate, nil, dictionary);
		}
	}
#endif
}

#pragma mark -

- (void)hideTouchControlsForController:(GCController *)controller
{
    [self.dPad setHidden:YES];
    [self.buttonGroup setHidden:YES];
    [self.leftShoulderButton setHidden:YES];
    [self.rightShoulderButton setHidden:YES];
    [self.leftShoulderButton2 setHidden:YES];
    [self.rightShoulderButton2 setHidden:YES];

    
    //Game Boy, Game Color, and Game Boy Advance can map Start and Select on a Standard Gamepad, so it's safe to hide them
    NSArray *useStandardGamepad = [NSArray arrayWithObjects: PVGBSystemIdentifier, PVGBCSystemIdentifier, PVGBASystemIdentifier, nil];
    if ([controller extendedGamepad] || [useStandardGamepad containsObject:self.systemIdentifier])
    {
        [self.startButton setHidden:YES];
        [self.selectButton setHidden:YES];
    }
}

@end
