//  Created by Simon Toens on 12.03.15
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
//  You should have received a copy of the GNU General Public License
//  along with this program; if not, write to the Free Software
//  Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

#include "sysconfig.h"
#include "sysdeps.h"
#include "options.h"
#include "savestate.h"

#import "State.h"
#import "StateManagementController.h"
#import "StateFileManager.h"
#import "SVProgressHUD.h"

static NSString *kSaveStateAlertTitle = @"Save";

@implementation StateManagementController {
    @private
    StateFileManager *_stateFileManager;
    NSArray *_states;
    UIBarButtonItem *_saveButton;
    UIBarButtonItem *_restoreButton;
}

# pragma mark - init/dealloc

- (void)dealloc {
    [_stateFileManager release];
    [_states release];
    [_saveButton release];
    [_restoreButton release];
    self.emulatorScreenshot = nil;
    [super dealloc];
}

#pragma mark - Overridden UIViewController methods

- (void)viewDidLoad {
    [super viewDidLoad];
    [self initNavigationBarButtons];
    _stateFileManager = [[StateFileManager alloc] init];
    [_stateNameTextField addTarget:self action:@selector(onStateNameTextFieldChanged) forControlEvents:UIControlEventEditingChanged];
    [self reloadStates];
    [self configureForDevice];
    [self updateUIState];
}

#pragma mark - UITableViewDelegate methods

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    // hack to get rid of empty rows in table view (also see heightForFooterInSection)
    return [[UIView alloc] init];
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    return 1;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    State *selectedState = [_states objectAtIndex:indexPath.row];
    _stateNameTextField.text = selectedState.name;
    _selectedStateScreenshot.image = selectedState.image;
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self updateUIState];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        State *state = [_states objectAtIndex:indexPath.row];
        [_stateFileManager deleteState:state];
        [self reloadStates];
        [tableView beginUpdates];
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
        [tableView endUpdates];
        [self clearSelectedStateScreenshotImage];
        [self updateUIState];
    }
}

#pragma mark - UITableViewDataSource protocol

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [_states count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellReuseIdentifier = @"asfcell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellReuseIdentifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellReuseIdentifier];
    }
    State *state = [_states objectAtIndex:indexPath.row];
    cell.textLabel.text = state.name;
    cell.imageView.image = state.image;
    cell.detailTextLabel.text = state.modificationDate;
    return cell;
}

#pragma mark - Target-action methods

- (IBAction)onSave {
    NSString *stateName = _stateNameTextField.text;
    if (![_stateFileManager isValidStateName:stateName]) {
        [self showAlertWithTitle:kSaveStateAlertTitle message:[NSString stringWithFormat:@"The state name '%@' is invalid", stateName] hasCancelButton:NO hasDelegate:NO];
    } else if ([_stateFileManager stateFileExistsForStateName:stateName]) {
        [self showAlertWithTitle:kSaveStateAlertTitle message:[NSString stringWithFormat:@"State '%@' exists, overwrite?", stateName] hasCancelButton:YES hasDelegate:YES];
    } else {
        [self saveState];
    }
}

- (IBAction)onRestore {
    NSString *stateName = _stateNameTextField.text;
    State *stateToRestore = [_stateFileManager loadState:stateName];
    if (stateToRestore) {
        [self dismissKeyboard];
        [self showAlertWithTitle:@"Restore" message:[NSString stringWithFormat:@"Really restore state '%@'?", stateToRestore.name] hasCancelButton:YES hasDelegate:YES];
    } else {
        [self showAlertWithTitle:@"Restore" message:[NSString stringWithFormat:@"State '%@' does not exist", stateName] hasCancelButton:NO hasDelegate:NO];
    }
}

#pragma mark - AlertView delegate method

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if ([alertView.title isEqualToString:kSaveStateAlertTitle]) {
        if (buttonIndex == 0) { // Overwrite existing state confirmation
            [self saveState];
        }
    } else { // restore
        if (buttonIndex == 0) { // Restore state confirmation
            [self restoreState];
        }
    }
}

#pragma mark - Private methods

- (void)dismissKeyboard {
    [self.view endEditing:YES];
}

- (void)showStatusHUD:(NSString *)message {
    [SVProgressHUD setBackgroundColor:[UIColor lightGrayColor]];
    [SVProgressHUD showSuccessWithStatus:message];
}

- (void)restoreState {
    NSString *stateName = _stateNameTextField.text;
    State *stateToRestore = [_stateFileManager loadState:stateName];
    static char path[1024];
    [stateToRestore.path getCString:path maxLength:sizeof(path) encoding:[NSString defaultCStringEncoding]];
    savestate_filename = path;
    savestate_state = STATE_DORESTORE;
    
    // the state restore logic, including inserting the floppy(ies) associated with the state, only runs when exiting settings.  In order to reduce confusion about what
    // floppies are inserted after the state has been restored, exit settings now
    [self.navigationController popToRootViewControllerAnimated:YES];
}

- (void)saveState {
    NSString *stateName = _stateNameTextField.text;
    State *state = [_stateFileManager newState:stateName];
    if (_emulatorScreenshot) {
        state.image = _emulatorScreenshot;
        _selectedStateScreenshot.image = state.image;
    }
    [_stateFileManager saveState:state];
    static char path[1024];
    [state.path getCString:path maxLength:sizeof(path) encoding:[NSString defaultCStringEncoding]];
    static char description[] = "no description provided";
    save_state(path, description);
    [self reloadStates];
    [_statesTableView reloadData];
    _stateNameTextField.text = @"";
    [self dismissKeyboard];
    [self updateUIState];
    [self showStatusHUD:[NSString stringWithFormat:@"Saved state %@", stateName]];
}

- (void)clearSelectedStateScreenshotImage {
    _selectedStateScreenshot.image = nil;
}

- (void)onStateNameTextFieldChanged {
    [self clearSelectedStateScreenshotImage];
    [self updateUIState];
}

- (void)updateUIState {
    [self updateButtonState];
    [self updateNavigationBarTitle];
    [_statesTableView setNeedsDisplay];
}

- (void)updateNavigationBarTitle {
    self.navigationItem.title = [_states count] == 0 ? @"No saved states" : [NSString stringWithFormat:@"Saved states: %i", [_states count]];
}

- (void)initNavigationBarButtons {
    _saveButton = [[UIBarButtonItem alloc] initWithTitle:@"Save" style:UIBarButtonSystemItemSave target:self action:@selector(onSave)];
    _restoreButton = [[UIBarButtonItem alloc] initWithTitle:@"Restore" style:UIBarButtonSystemItemRewind target:self action:@selector(onRestore)];
    self.navigationItem.rightBarButtonItems = @[_saveButton, _restoreButton];
}

- (void)updateButtonState {
    BOOL buttonsEnabled = [_stateNameTextField.text length] > 0;
    _saveButton.enabled = buttonsEnabled;
    _restoreButton.enabled = buttonsEnabled && [_states count] > 0;
}

- (void)reloadStates {
    if (_states) {
        [_states release];
    }
    _states = [[_stateFileManager loadStates] retain];
}
    
- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message hasCancelButton:(BOOL)hasCancelButton hasDelegate:(BOOL)hasDelegate {
    [[[[UIAlertView alloc] initWithTitle:title
                                 message:message
                                delegate:hasDelegate ? self : nil
                       cancelButtonTitle:@"OK"
                       otherButtonTitles:(hasCancelButton ? @"Cancel" : nil), nil] autorelease] show];
}

- (void)configureForDevice {
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        int distanceFromRightViewEdge = self.view.frame.size.width - _titleLabel.frame.size.width - 30;
        _stateNameTextFieldRightConstraint.constant = distanceFromRightViewEdge;
        _statesTableViewRightConstraint.constant = distanceFromRightViewEdge;
        [_stateNameTextField layoutIfNeeded];
        [_statesTableView layoutIfNeeded];
    } else {
        // no state screenshot preview on iPhone - disconnect the ui image view to make sure it doesn't render
        _selectedStateScreenshot = nil;
    }
}

@end