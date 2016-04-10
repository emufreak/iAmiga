//
//  DOTCEmulationViewController.m
//  iAmiga
//
//  Created by Stuart Carnie on 7/11/11.
//  Copyright 2011 Manomio LLC. All rights reserved.
//
//  Changed by Emufr3ak on 29.05.14.
//
//  iUAE is free software: you may copy, redistribute
//  and/or modify it under the terms of the GNU General Public License as
//  published by the Free Software Foundation, either version 2 of the
//  License, or (at your option) any later version.
//
//  This file is distributed in the hope that it will be useful, but
//  WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
//  General Public License for more details.
//
// You should have received a copy of the GNU General Public License
//along with this program; if not, write to the Free Software
//Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

#import "MainEmulationViewController.h"
#import "VirtualKeyboard.h"
#import "IOSKeyboard.h"
#import "uae.h"
#import "sysconfig.h"
#import "sysdeps.h"
#import "options.h"
#import "SDL.h"
#import "UIKitDisplayView.h"
#import "savestate.h"
#import "Settings.h"
#import "SettingsGeneralController.h"
#import "DiskDriveService.h"
#import <GameController/GameController.h>
#import "MultiPeerConnectivityController.h"
#import "VPadMotionController.h"

extern SDL_Joystick *uae4all_joy0, *uae4all_joy1;
extern void init_joystick();

@interface MainEmulationViewController()
@end

@implementation MainEmulationViewController {
    DiskDriveService *_diskDriveService;
    NSTimer *_menuHidingTimer;
    Settings *_settings;
    NSTimer *_checkForPausedTimer;
    NSTimer *_checkForGControllerTimer;
}

MultiPeerConnectivityController *mpcController = [[MultiPeerConnectivityController alloc] init]; //Needs to be called this early and out of class context to ensure it loads first
UIButton *btnSettings;
IOSKeyboard *ioskeyboard;

extern void uae_reset();

- (IBAction)restart:(id)sender {
    uae_reset();
}

- (void)webViewDidFinishLoad:(UIWebView *)webView {
    NSString *fn = [NSString stringWithFormat:@"setVersion('%@');", self.bundleVersion];
    [webView stringByEvaluatingJavaScriptFromString:fn];
}

- (CGFloat)screenHeight {
    CGRect screenRect = CGRectZero;
    screenRect = [[UIScreen mainScreen] bounds];
    return screenRect.size.height;
}

- (CGFloat)screenWidth {
    CGRect screenRect = CGRectZero;
    screenRect = [[UIScreen mainScreen] bounds];
    return screenRect.size.width;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    _diskDriveService = [[DiskDriveService alloc] init];
    _settings = [[Settings alloc] init];
    
    [self.view setMultipleTouchEnabled:TRUE];
    
    [_btnJoypad setImage:[UIImage imageNamed:@"controller_selected.png"] forState:UIControlStateSelected];
    [_btnSettings setImage:[UIImage imageNamed:@"gear_selected.png"] forState: UIControlStateHighlighted];
    [_btnKeyboard setImage:[UIImage imageNamed:@"keyboard_selected.png"] forState:UIControlStateHighlighted];
    [_btnPin setImage:[UIImage imageNamed:@"sticky_selected.png"] forState:UIControlStateSelected];
    
    [self initMenuBarHidingTimer];
    [self initCheckForPausedTimer];
    
    if (_settings.autoloadConfig)
    {
        // enabling things here uses timers because the disk subsystem of the emulator isn't initialized yet right here - we need to delay disk drive related tasks by a little bit
        [self initDriveSetupTimer:_settings.driveState];
        [self initDiskInsertTimer:_settings.insertedFloppies];
    }
    
    [self initializeControls];
    paused = 0;
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(controllerStateChange)
                                                 name:GCControllerDidConnectNotification
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(controllerStateChange)
                                                 name:GCControllerDidDisconnectNotification
                                               object:nil];
    
    // we start out with the mouse activated
    [_mouseHandler onMouseActivated];

}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self applyConfiguredEffect];
    set_joystickactive();

   
    [_mouseHandler reloadMouseSettings];
    [_joyController reloadJoypadSettings];
    
    if (joyactive && _settings.DPadModeIsMotion){
        [VPadMotionController setActive];
    }
    
    [mpcController configure: self];
}

- (void)viewDidDisappear:(BOOL)animated {
    [VPadMotionController disable];
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    [super prepareForSegue:segue sender:sender];
    UITabBarController *tabBarController = segue.destinationViewController;
    SettingsGeneralController *settingsController = [tabBarController.viewControllers objectAtIndex:0];
    settingsController.resetDelegate = self;
}

- (void)didSelectReset:(DriveState *)driveState {
    uae_reset();
    _settings.driveState = driveState;
    [self initDriveSetupTimer:driveState];
}

- (void)applyConfiguredEffect {
    SDL_Surface *video = SDL_GetVideoSurface();
    id<DisplayViewSurface> display = (id<DisplayViewSurface>)video->userdata;
    display.displayEffect = (DisplayEffect)_settings.selectedEffectIndex;
}

- (void)initializeJoypad:(InputControllerView *)joyController {
    /* Check if function is still needed */
    _joyController.hidden = TRUE;
    joyactive = FALSE;
    [VPadMotionController disable];
}

- (void)initializeControls {
    joyactive = FALSE;
    _mouseHandler.hidden = FALSE;
    _joyController.hidden = TRUE;
    [VPadMotionController disable];
}

extern  void mousehack_setdontcare_iuae ();
extern  void mousehack_setfollow_iuae ();
extern void togglemouse (void);
- (IBAction)toggleControls:(UIButton *)button {
    
    bool keyboardactiveonstart = keyboardactive;
    
    keyboardactive = (button == _btnKeyboard) ? !keyboardactive : FALSE;
    joyactive = (button == _btnJoypad) ? !joyactive : FALSE;
    
    _btnKeyboard.selected = (button == _btnKeyboard) ? !_btnKeyboard.selected : FALSE;
    _btnJoypad.selected = (button == _btnJoypad) ? !_btnJoypad.selected : FALSE;
    
    //_btnJoypad.tintColor = _btnJoypad.selected ? [UIColor blueColor] : [UIColor blackColor];
    
    _joyController.hidden = !joyactive;

    
    if (joyactive && _settings.DPadModeIsMotion){
        [VPadMotionController setActive];
    }
    else{
        [VPadMotionController disable];
    }
    
    _mouseHandler.hidden = joyactive;

    if (joyactive)
    {
        [_joyController onJoypadActivated];
         mousehack_setdontcare_iuae();
    }
    else
    {
        [_mouseHandler onMouseActivated];
         mousehack_setfollow_iuae();
    }
    
    if (keyboardactive != keyboardactiveonstart)
    {
        [ioskeyboard toggleKeyboard];
    }    
}

- (IBAction)togglePinstatus:(id)sender {
    
    _btnPin.selected = !_btnPin.selected;
    //_btnPin.tintColor = _btnPin.selected ? [UIColor blueColor] : [UIColor blackColor];
    
    _mouseHandler.clickedscreen = false;
    _joyController.clickedscreen = false;
}

- (void)initializeKeyboard:(UITextField *)p_dummy_textfield dummytextf:(UITextField *)p_dummy_textfield_f dummytexts:(UITextField *)p_dummy_textfield_s {
    
    keyboardactive = FALSE;
    
    ioskeyboard = [[IOSKeyboard alloc] initWithDummyFields:p_dummy_textfield fieldf:p_dummy_textfield_f fieldspecial:p_dummy_textfield_s];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardDidHide:)
                                                 name:UIKeyboardDidHideNotification
                                               object:nil];
}

-(IBAction)enableMenuBar:(id)sender {
    _menuBar.hidden = false;
    _menuBarEnabler.hidden = true;
    _mouseHandler.clickedscreen = false;
    _joyController.clickedscreen = false;
    [self initMenuBarHidingTimer];
}

-(void)checkForMenuBarHiding:(NSTimer*)timer {
    if((_mouseHandler || _joyController) && !_btnPin.selected && _menuBar.hidden == false)
    {
        if(_mouseHandler.clickedscreen || _joyController.clickedscreen)
        {
            _mouseHandler.clickedscreen = false;
            _joyController.clickedscreen = false;
            _menuBar.hidden = true;
            _menuBarEnabler.hidden = false;

            [_menuHidingTimer invalidate];
            [_menuHidingTimer release];
            _menuHidingTimer = nil;
        }
    }
}

-(void)checkForPaused:(NSTimer *)timer {
    
    //As emulator is paused this methods needs to be called to check for Joypad as it wont get called by the emulator
    if(paused) SDL_JoystickUpdate();
    
    int pausednew;
    pausednew = SDL_JoystickGetPaused(uae4all_joy0);
    
    if(pausednew != paused )
    {
        paused = pausednew;
        
        if(paused == 1)
        {
            [self pauseEmulator];
        }
        else
        {
            [self resumeEmulator];
        }
    }
}

-(void)controllerStateChange {
    init_joystick();
}

- (void)initDriveSetupTimer:(DriveState *)driveState {
    [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(setupDrives:) userInfo:driveState repeats:NO];
}

- (void)initDiskInsertTimer:(NSArray *)insertedFloppies {
    [NSTimer scheduledTimerWithTimeInterval:.5 target:self selector:@selector(insertConfiguredDisks:) userInfo:insertedFloppies repeats:NO];
}

- (void)initMenuBarHidingTimer {
    if (_menuHidingTimer) {
        [_menuHidingTimer release];
    }
    _menuHidingTimer = [[NSTimer scheduledTimerWithTimeInterval:0.020 target:self
                                                       selector:@selector(checkForMenuBarHiding:) userInfo:nil repeats:YES] retain];
    _menuHidingTimer.tolerance = 0.0020;
}

- (void)initCheckForPausedTimer {
    if (_checkForPausedTimer) {
        [_checkForPausedTimer release];
    }
    
    _checkForPausedTimer = [[NSTimer scheduledTimerWithTimeInterval:0.020 target:self
                                                           selector:@selector(checkForPaused:) userInfo:nil repeats:YES] retain];
    
    _checkForPausedTimer.tolerance = 0.0020;
    
}

- (void)insertConfiguredDisks:(NSTimer *)timer {
    NSArray *insertedFloppies = timer.userInfo;
    if ([insertedFloppies count] > 0)
    {
        [_diskDriveService insertDisks:insertedFloppies];
        [_settings setFloppyConfigurations:insertedFloppies];
    }
}

- (void)setupDrives:(NSTimer *)timer {
    DriveState *driveState = timer.userInfo;
    [_diskDriveService setDriveState:driveState];
}

- (void)dealloc
{
    [_btnJoypad release];
    [_btnKeyboard release];
    [_btnPin release];
    [_diskDriveService release];
    [_mouseHandler release];
    [_menuBar release];
    [_menuBarEnabler release];
    [_menuHidingTimer invalidate];
    [_menuHidingTimer release];
    [_settings release];
    [super dealloc];
}

@end
