#import <QuartzCore/QuartzCore.h>

#import "SpectacleConstants.h"
#import "SpectacleLoginItemHelper.h"
#import "SpectaclePreferencesController.h"
#import "SpectacleRegisteredShortcutValidator.h"
#import "SpectacleShortcut.h"
#import "SpectacleShortcutManager.h"
#import "SpectacleShortcutRecorder.h"
#import "SpectacleUtilities.h"
#import "SpectacleWindowPositionManager.h"

@interface SpectaclePreferencesController ()

@property (nonatomic, weak) SpectacleShortcutManager *shortcutManager;
@property (nonatomic, weak) SpectacleWindowPositionManager *windowPositionManager;
@property (nonatomic, weak) id<SpectacleShortcutStorageProtocol> shortcutStorage;

@property (nonatomic) NSDictionary *shortcutRecorders;

@end

#pragma mark -

@implementation SpectaclePreferencesController

- (instancetype)initWithShortcutManager:(SpectacleShortcutManager *)shortcutManager
                  windowPositionManager:(SpectacleWindowPositionManager *)windowPositionManager
                        shortcutStorage:(id<SpectacleShortcutStorageProtocol>)shortcutStorage
{
  if ((self = [super initWithWindowNibName:kPreferencesWindowNibName])) {
    _shortcutManager = shortcutManager;
    _windowPositionManager = windowPositionManager;
    _shortcutStorage = shortcutStorage;
  }
  
  return self;
}

#pragma mark -

- (void)windowDidLoad
{
  NSNotificationCenter *notificationCenter = NSNotificationCenter.defaultCenter;
  NSInteger loginItemEnabledState = NSOffState;
  BOOL isStatusItemEnabled = [NSUserDefaults.standardUserDefaults boolForKey:kStatusItemEnabledPreference];

  self.shortcutRecorders = @{kWindowActionMoveToCenter: _moveToCenterShortcutRecorder,
                             kWindowActionMoveToFullscreen: _moveToFullscreenShortcutRecorder,
                             kWindowActionMoveToLeftHalf: _moveToLeftShortcutRecorder,
                             kWindowActionMoveToRightHalf: _moveToRightShortcutRecorder,
                             kWindowActionMoveToTopHalf: _moveToTopShortcutRecorder,
                             kWindowActionMoveToBottomHalf: _moveToBottomShortcutRecorder,
                             kWindowActionMoveToUpperLeft: _moveToUpperLeftShortcutRecorder,
                             kWindowActionMoveToLowerLeft: _moveToLowerLeftShortcutRecorder,
                             kWindowActionMoveToUpperRight: _moveToUpperRightShortcutRecorder,
                             kWindowActionMoveToLowerRight: _moveToLowerRightShortcutRecorder,
                             kWindowActionMoveToNextDisplay: _moveToNextDisplayShortcutRecorder,
                             kWindowActionMoveToPreviousDisplay: _moveToPreviousDisplayShortcutRecorder,
                             kWindowActionMoveToNextThird: _moveToNextThirdShortcutRecorder,
                             kWindowActionMoveToPreviousThird: _moveToPreviousThirdShortcutRecorder,
                             kWindowActionMakeLarger: _makeLargerShortcutRecorder,
                             kWindowActionMakeSmaller: _makeSmallerShortcutRecorder,
                             kWindowActionUndoLastMove: _undoLastMoveShortcutRecorder,
                             kWindowActionRedoLastMove: _redoLastMoveShortcutRecorder};
  
  [self loadRegisteredShortcuts];

  [notificationCenter addObserver:self
                         selector:@selector(loadRegisteredShortcuts)
                             name:kRestoreDefaultShortcutsNotification
                           object:nil];

  if ([SpectacleLoginItemHelper isLoginItemEnabledForBundle:NSBundle.mainBundle]) {
    loginItemEnabledState = NSOnState;
  }
  
  self.loginItemEnabled.state = loginItemEnabledState;
  
  [self.statusItemEnabled selectItemWithTag:isStatusItemEnabled ? 0 : 1];

  self.window.title = [@"Spectacle " stringByAppendingString:SpectacleUtilities.applicationVersion];

  self.footerView.wantsLayer = YES;
}

#pragma mark -

- (void)shortcutRecorder:(SpectacleShortcutRecorder *)shortcutRecorder
   didReceiveNewShortcut:(SpectacleShortcut *)shortcut
{
  [shortcut setShortcutAction:^(SpectacleShortcut *shortcut) {
    SpectacleWindowAction windowAction = [self.windowPositionManager windowActionForShortcut:shortcut];

    [self.windowPositionManager moveFrontMostWindowWithWindowAction:windowAction];
  }];

  [self.shortcutManager registerShortcut:shortcut];

  [NSNotificationCenter.defaultCenter postNotificationName:kShortcutChangedNotification object:self];
}

- (void)shortcutRecorder:(SpectacleShortcutRecorder *)shortcutRecorder
didClearExistingShortcut:(SpectacleShortcut *)shortcut
{
  [self.shortcutManager unregisterShortcutForName:shortcut.shortcutName];

  [NSNotificationCenter.defaultCenter postNotificationName:kShortcutChangedNotification object:self];
}

#pragma mark -

- (IBAction)swapFooterViews:(id)sender
{
  CATransition *transition = [CATransition animation];
  NSView *currentFooterView = self.footerView.subviews[0];
  NSView *nextFooterView = nil;

  transition.type = kCATransitionPush;

  if (currentFooterView == self.shortcutModifierLegendFooterView) {
    nextFooterView = self.optionsFooterView;

    transition.subtype = kCATransitionFromRight;
  } else {
    nextFooterView = self.shortcutModifierLegendFooterView;

    transition.subtype = kCATransitionFromLeft;
  }

  self.footerView.animations = @{@"subviews": transition};

  [self.footerView.animator replaceSubview:currentFooterView
                                      with:nextFooterView];
}

#pragma mark -

- (IBAction)restoreDefaults:(id)sender
{
  [SpectacleUtilities displayRestoreDefaultsAlertWithConfirmationCallback:^() {
    NSArray *shortcuts = [self.shortcutStorage defaultShortcutsWithAction:^(SpectacleShortcut *shortcut) {
      SpectacleWindowAction windowAction = [self.windowPositionManager windowActionForShortcut:shortcut];

      [self.windowPositionManager moveFrontMostWindowWithWindowAction:windowAction];
    }];

    [self.shortcutManager registerShortcuts:shortcuts];

    [NSNotificationCenter.defaultCenter postNotificationName:kRestoreDefaultShortcutsNotification
                                                      object:self];
  }];
}

#pragma mark -

- (IBAction)toggleLoginItem:(id)sender
{
  NSBundle *applicationBundle = NSBundle.mainBundle;
  
  if (self.loginItemEnabled.state == NSOnState) {
    [SpectacleLoginItemHelper enableLoginItemForBundle:applicationBundle];
  } else {
    [SpectacleLoginItemHelper disableLoginItemForBundle:applicationBundle];
  }
}

- (IBAction)toggleStatusItem:(id)sender
{
  NSString *notificationName = kStatusItemEnabledNotification;
  BOOL isStatusItemEnabled = YES;
  __block BOOL statusItemStateChanged = YES;
  NSUserDefaults *userDefaults = NSUserDefaults.standardUserDefaults;
  
  if ([userDefaults boolForKey:kStatusItemEnabledPreference] == ([[sender selectedItem] tag] == 0)) {
    return;
  }
  
  if ([sender selectedItem].tag != 0) {
    notificationName = kStatusItemDisabledNotification;
    isStatusItemEnabled = NO;
    
    if (![userDefaults boolForKey:kBackgroundAlertSuppressedPreference]) {
      [SpectacleUtilities displayRunningInBackgroundAlertWithCallback:^(BOOL isConfirmed, BOOL isSuppressed) {
        if (!isConfirmed) {
          statusItemStateChanged = NO;
          
          [sender selectItemWithTag:0];
        }
        
        [userDefaults setBool:isSuppressed forKey:kBackgroundAlertSuppressedPreference];
      }];
    }
  }
  
  if (statusItemStateChanged) {
    [NSNotificationCenter.defaultCenter postNotificationName:notificationName object:self];
    
    [userDefaults setBool:isStatusItemEnabled forKey:kStatusItemEnabledPreference];
  }
}

#pragma mark -

- (void)loadRegisteredShortcuts
{
  SpectacleRegisteredShortcutValidator *shortcutValidator = [SpectacleRegisteredShortcutValidator new];

  for (NSString *shortcutName in self.shortcutRecorders.allKeys) {
    SpectacleShortcutRecorder *shortcutRecorder = self.shortcutRecorders[shortcutName];
    SpectacleShortcut *shortcut = [self.shortcutManager registeredShortcutForName:shortcutName];
    
    shortcutRecorder.shortcutName = shortcutName;
    
    if (shortcut) {
      shortcutRecorder.shortcut = shortcut;
    }
    
    shortcutRecorder.delegate = self;
    
    [shortcutRecorder setAdditionalShortcutValidators:@[shortcutValidator] shortcutManager:self.shortcutManager];
  }
  
  
  [self enableShortcutRecorders:YES];
}

#pragma mark -

- (void)enableShortcutRecorders:(BOOL)enabled
{
  for (SpectacleShortcutRecorder *shortcutRecorder in self.shortcutRecorders.allValues) {
    if (!enabled) {
      shortcutRecorder.shortcut = nil;
    }
    
    shortcutRecorder.enabled = enabled;
  }
}

@end
