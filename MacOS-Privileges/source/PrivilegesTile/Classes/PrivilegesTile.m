/*
    PrivilegesTile.m
    Copyright 2016-2024 KhulnaSoft, Ltd
     
    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at
     
    http://www.apache.org/licenses/LICENSE-2.0
     
    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.
*/

#import "PrivilegesTile.h"
#import "MTPrivileges.h"
#import "Constants.h"
#import <AudioToolbox/AudioServices.h>

@interface PrivilegesTile ()
@property (retain) id privilegesObserver;
@property (retain) id timeLeftObserver;
@property (retain) id configurationObserver;
@property (nonatomic, strong, readwrite) MTPrivileges *privilegesApp;
@property (nonatomic, strong, readwrite) NSBundle *pluginBundle;
@property (nonatomic, strong, readwrite) NSString *appPath;
@property (nonatomic, strong, readwrite) NSString *cliPath;
@property (nonatomic, strong, readwrite) NSMenu *dockTileMenu;
@end

@implementation PrivilegesTile

- (void)setDockTile:(NSDockTile *)dockTile
{
    NSNotificationCenter *notificationCenter = [NSDistributedNotificationCenter defaultCenter];
    
    if (dockTile) {
        
        _privilegesApp = [[MTPrivileges alloc] init];
        _pluginBundle = [NSBundle bundleForClass:[self class]];
        
        // get the path to our command line tool
        _appPath = [[[[_pluginBundle bundlePath] stringByDeletingLastPathComponent] stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
        NSBundle *mainBundle = [NSBundle bundleWithPath:_appPath];
        _cliPath = [mainBundle pathForAuxiliaryExecutable:@"PrivilegesCLI"];
        
        // add observers to get notified if something important happens
        _privilegesObserver = [notificationCenter addObserverForName:kMTNotificationNamePrivilegesDidChange
                                                              object:nil
                                                               queue:nil
                                                          usingBlock:^(NSNotification *notification) {
            
            [self updateDockTileIcon:dockTile];
            if (![[self->_privilegesApp currentUser] hasAdminPrivileges]) { [self setBadgeOfDockTile:dockTile toMinutesLeft:0]; }
            
        }];
        
        _timeLeftObserver = [notificationCenter addObserverForName:kMTNotificationNameExpirationTimeLeft
                                                            object:nil
                                                             queue:nil
                                                        usingBlock:^(NSNotification *notification) {
            
            NSDictionary *userInfo = [notification userInfo];

            if (userInfo) {
                
                NSInteger minutesLeft = [[userInfo valueForKey:kMTNotificationKeyTimeLeft] integerValue];
                [self setBadgeOfDockTile:dockTile toMinutesLeft:minutesLeft];
            }
        }];
        
        _configurationObserver = [notificationCenter addObserverForName:kMTNotificationNameConfigDidChange
                                                                 object:nil
                                                                  queue:nil
                                                             usingBlock:^(NSNotification *notification) {
            
            NSDictionary *userInfo = [notification userInfo];
            
            if (userInfo) {
                
                NSString *changedKey = [userInfo objectForKey:kMTNotificationKeyPreferencesChanged];
                NSArray *keysToObserve = [[NSArray alloc] initWithObjects:
                                          kMTDefaultsEnforcePrivilegesKey,
                                          kMTDefaultsLimitToUserKey,
                                          kMTDefaultsLimitToGroupKey,
                                          nil
                ];
                
                if (changedKey && [keysToObserve containsObject:changedKey]) {
                    
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        
                        [self updateDockTileIcon:dockTile];
                    });
                }
            }
        }];
        
        // make sure the Dock tile has the correct icon on load
        [self updateDockTileIcon:dockTile];
                
    } else {
        
        // remove our observers
        [notificationCenter removeObserver:_privilegesObserver];
        [notificationCenter removeObserver:_timeLeftObserver];
        [notificationCenter removeObserver:_configurationObserver];
        _privilegesObserver = nil;
        _timeLeftObserver = nil;
        _configurationObserver = nil;
    }
}

- (NSMenu*)dockMenu
 {
     // initialize our menu if needed
     if (!_dockTileMenu) {
         
         _dockTileMenu = [[NSMenu alloc] init];
         [_dockTileMenu setAutoenablesItems:NO];
         
     } else {
         
         [_dockTileMenu removeAllItems];
     }
     
#pragma mark add the action item
     
     if (_cliPath && [[NSFileManager defaultManager] isExecutableFileAtPath:_cliPath]) {
         
         NSMenuItem *privilegesItem = [[NSMenuItem alloc] init];
         BOOL hasAdminPrivileges = [[_privilegesApp currentUser] hasAdminPrivileges];

         if (hasAdminPrivileges) {
             
             [privilegesItem setTitle:NSLocalizedStringFromTableInBundle(@"revertMenuItem", @"Localizable", _pluginBundle, nil)];
             [privilegesItem setAction:@selector(revertPrivileges)];
             
         } else {
             
             [privilegesItem setTitle:NSLocalizedStringFromTableInBundle(@"requestMenuItem", @"Localizable", _pluginBundle, nil)];
             [privilegesItem setAction:@selector(requestPrivileges)];
         }
         
         [privilegesItem setTarget:self];
         
         if ([_privilegesApp useIsRestrictedForUser:[_privilegesApp currentUser]] ||
             (!hasAdminPrivileges && (([_privilegesApp authenticationRequired] && ![_privilegesApp allowCLIBiometricAuthentication]) || [_privilegesApp reasonRequired]))) {
             [privilegesItem setEnabled:NO];
         }
         
         [_dockTileMenu addItem:privilegesItem];
     }
     
#pragma mark add the settings item
     
     if (_appPath && ![_privilegesApp hideSettingsFromDockMenu]) {
         
         NSNumber *isBundle = nil;
         NSURL *executableURL = [NSURL fileURLWithPath:_appPath];
         
         if ([executableURL getResourceValue:&isBundle forKey:NSURLIsPackageKey error:nil] && [isBundle boolValue]) {
             
             NSMenuItem *settingsItem = [[NSMenuItem alloc] init];
             [settingsItem setTitle:NSLocalizedStringFromTableInBundle(@"settingsMenuItem", @"Localizable", _pluginBundle, nil)];
             [settingsItem setAction:@selector(showSettings)];
             [settingsItem setTarget:self];
             
             [_dockTileMenu addItem:[NSMenuItem separatorItem]];
             [_dockTileMenu addItem:settingsItem];
         }
     }
     
     return _dockTileMenu;
 }

- (void)updateDockTileIcon:(NSDockTile*)dockTile
{
    if (dockTile) {
        
        NSString *soundPath = nil;
        NSString *iconName = nil;
        
        if ([[_privilegesApp currentUser] hasAdminPrivileges]) {
            
            iconName = @"unlocked";
            soundPath = @"/System/Library/Frameworks/SecurityInterface.framework/Versions/A/Resources/lockOpening.aif";
            
        } else {
            
            iconName = @"locked";
            soundPath = @"/System/Library/Frameworks/SecurityInterface.framework/Versions/A/Resources/lockClosing.aif";
        }
        
        if ([_privilegesApp useIsRestrictedForUser:[_privilegesApp currentUser]]) { iconName = [iconName stringByAppendingString:@"_managed"]; }
        
        // play a lock/unlock sound if VoiceOver is enbled
        if ([[NSWorkspace sharedWorkspace] isVoiceOverEnabled]) {
    
            NSURL *soundURL = [NSURL fileURLWithPath:soundPath];
    
            if (soundURL && [[NSFileManager defaultManager] fileExistsAtPath:soundPath]) {
    
                SystemSoundID soundID;
                OSStatus error = AudioServicesCreateSystemSoundID((__bridge CFURLRef)soundURL, &soundID);
                if (error == kAudioServicesNoError) { AudioServicesPlayAlertSoundWithCompletion(soundID, nil); }
            }
        }
        
        NSImage *dockIcon = [_pluginBundle imageForResource:iconName];
        
        if (dockIcon) {
            
            NSImageView *imageView = [NSImageView imageViewWithImage:dockIcon];
            [dockTile setContentView:imageView];
            [dockTile display];
        }
    }
}

- (void)setBadgeOfDockTile:(NSDockTile*)dockTile toMinutesLeft:(NSUInteger)minutesLeft
{
    if (dockTile) {
                
        if (minutesLeft > 0) {

            // make VoiceOver say "x minutes" instead of "x new elements"
            if ([[NSWorkspace sharedWorkspace] isVoiceOverEnabled]) {
                
                NSMeasurement *durationMeasurement = [[NSMeasurement alloc] initWithDoubleValue:minutesLeft
                                                                                           unit:[NSUnitDuration minutes]];
                
                NSMeasurementFormatter *durationFormatter = [[NSMeasurementFormatter alloc] init];
                [[durationFormatter numberFormatter] setMaximumFractionDigits:0];
                [durationFormatter setUnitStyle:NSFormattingUnitStyleMedium];
                [durationFormatter setUnitOptions:NSMeasurementFormatterUnitOptionsProvidedUnit];
                
                [dockTile setBadgeLabel:[durationFormatter stringFromMeasurement:durationMeasurement]];
                
            } else {
                
                [dockTile setBadgeLabel:[NSString stringWithFormat:@"%lu", (unsigned long)minutesLeft]];
            }
            
        } else {
            
            [dockTile setBadgeLabel:nil];
        }
    }
}

#pragma mark Menu actions

- (void)requestPrivileges
{
    [NSTask launchedTaskWithLaunchPath:_cliPath
                             arguments:[NSArray arrayWithObject:@"--add"]
    ];
}

- (void)revertPrivileges
{
    [NSTask launchedTaskWithLaunchPath:_cliPath
                             arguments:[NSArray arrayWithObject:@"--remove"]
    ];
}

- (void)showSettings
{
    if (_appPath) {

        NSNumber *isBundle = nil;
        NSURL *executableURL = [NSURL fileURLWithPath:_appPath];
        
        if ([executableURL getResourceValue:&isBundle forKey:NSURLIsPackageKey error:nil] && [isBundle boolValue]) {

            NSWorkspaceOpenConfiguration *openConfiguration = [NSWorkspaceOpenConfiguration configuration];
            [openConfiguration setArguments:[NSArray arrayWithObject:@"--showSettings"]];
            
            [[NSWorkspace sharedWorkspace] openApplicationAtURL:executableURL
                                                  configuration:openConfiguration
                                              completionHandler:nil
            ];
        }
    }
}

@end
