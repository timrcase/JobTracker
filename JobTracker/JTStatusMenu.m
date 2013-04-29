//
//  JTStatusMenu.m
//  JobTracker
//
//  Created by Brad Greenlee on 10/21/12.
//  Copyright (c) 2012 Etsy. All rights reserved.
//

#import "JTStatusMenu.h"
#import "JTState.h"

@implementation JTStatusMenu

@synthesize jobTrackerURL, usernames, refreshInterval, startingJobNotificationsEnabled, completedJobNotificationsEnabled,
failedJobNotificationsEnabled;

- (void)awakeFromNib {
    statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    statusImage = [NSImage imageNamed:@"pith helmet small.png"];
    [statusItem setImage:statusImage];
    [statusItem setAlternateImage:statusHighlightImage];
    [statusItem setHighlightMode:YES];
    [statusMenu setAutoenablesItems:NO];
    [statusItem setMenu:statusMenu];
    
    // Listen for events when the computer wakes from sleep, which otherwise
    // throws off the refresh schedule.
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                           selector:@selector(receiveWakeNote:)
                                                               name:NSWorkspaceDidWakeNotification
                                                             object:nil];
    
    [GrowlApplicationBridge setGrowlDelegate:self];
    
    [self loadPreferences];
    if ([self isConfigured]) {
        jtState = [JTState sharedInstance];
        jtState.url = [NSURL URLWithString:[jobTrackerURL stringByAppendingString:@"/jobtracker.jsp"]];
        [jtState setUsernameString:usernames];
        jtState.delegate = self;
        [self refresh:nil];
        [self startTimer];
    } else {
        [self showPreferences:nil];
    }
}

- (void)loadPreferences {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    // this replace just fixes the url generated by an earlier version and can eventually be removed
    jobTrackerURL = [[defaults stringForKey:@"jobTrackerURL"] stringByReplacingOccurrencesOfString:@"/jobtracker.jsp" withString:@""];
    if ([jobTrackerURL length] > 7 && !([[jobTrackerURL substringToIndex:7] isEqualToString:@"http://"] ||
        [[jobTrackerURL substringToIndex:8] isEqualToString:@"https://"]))
    {
        jobTrackerURL = [@"http://" stringByAppendingString:jobTrackerURL];
    }
    usernames = [defaults stringForKey:@"usernames"];
    refreshInterval = [defaults integerForKey:@"refreshInterval"];
    if (refreshInterval == 0) {
        refreshInterval = DEFAULT_REFRESH_INTERVAL;
    }
    startingJobNotificationsEnabled = [defaults boolForKey:@"startingJobNotificationsEnabled"];
    completedJobNotificationsEnabled = [defaults boolForKey:@"completedJobNotificationsEnabled"];
    failedJobNotificationsEnabled = [defaults boolForKey:@"failedJobNotificationsEnabled"];
}

- (NSWindowController *)preferencesWindowController {
    if (_preferencesWindowController == nil) {
        _preferencesWindowController = [[JTPreferencesWindowController alloc] init];
        _preferencesWindowController.delegate = self;
    }
    return _preferencesWindowController;
}

- (IBAction)showPreferences:(id)sender {
    [self.preferencesWindowController showWindow:nil];
}

- (BOOL)isConfigured {
    if (self.jobTrackerURL == nil || [self.jobTrackerURL isEqualToString:@""]) {
        return NO;
    }
    return YES;
}

- (void)startTimer {
    [self stopTimer];
    
    refreshTimer = [NSTimer scheduledTimerWithTimeInterval:refreshInterval
                                                    target:self
                                                  selector:@selector(refresh:)
                                                  userInfo:nil
                                                   repeats:YES];
}


- (void)stopTimer {
    if (refreshTimer != nil) {
        [refreshTimer invalidate];
        refreshTimer = nil;
    }
}

- (void)receiveWakeNote:(NSNotification*)note {
    if ([self isConfigured]) {
        // Kill off the current refresh schedule.
        [self stopTimer];
        
        // Wait a bit after wake before refreshing, so we don't make wake slower.
        [NSTimer scheduledTimerWithTimeInterval:10.0
                                         target:self
                                       selector:@selector(refresh:)
                                       userInfo:nil
                                        repeats:NO];
        
        // Reset the refresh schedule after the wake refresh.
        [self startTimer];
    }
}

- (IBAction)refresh:(id)sender {
    [self startRefresh];
    [jtState refresh];
    if (jtState.currentError) {
        [self setError:jtState.currentError];
    } else {
        [self clearError];
    }
}

- (void)setError:(NSError *)error {
    NSMenuItem *refresh = [statusMenu itemWithTag:REFRESH_TAG];
    NSMutableAttributedString *errorString = [[NSMutableAttributedString alloc] initWithString:@"Error: Please check your JobTracker URL"];
    [errorString addAttribute:NSForegroundColorAttributeName value:[NSColor redColor] range:NSMakeRange(0, [errorString length])];
    [refresh setAttributedTitle:errorString];
    
    [statusItem setImage:[NSImage imageNamed:@"pith helmet error.png"]];

    [refresh setEnabled:NO];
}

-(void)clearError {
    [statusItem setImage:[NSImage imageNamed:@"pith helmet small.png"]];
}

- (void)stateUpdated {
    [self updateMenuItemWithTag:RUNNING_JOBS_TAG withJobs:[jtState.jobs objectForKey:@"running"]];
    [self updateMenuItemWithTag:COMPLETED_JOBS_TAG withJobs:[jtState.jobs objectForKey:@"completed"]];
    [self updateMenuItemWithTag:FAILED_JOBS_TAG withJobs:[jtState.jobs objectForKey:@"failed"]];
    [self endRefresh];
}

- (void) growlNotificationWasClicked:(id)clickContext {
    NSString *jobId = [clickContext objectForKey:@"jobId"];
    [self openJobInBrowser:jobId];
}

- (void)sendNotificationWithTitle:(NSString *)title withJob:(JTJob *)job {
    [GrowlApplicationBridge notifyWithTitle:title
                                description:job.displayName
                           notificationName:title
                                   iconData:nil
                                   priority:0
                                   isSticky:NO
                               clickContext:[NSDictionary dictionaryWithObject:job.jobId forKey:@"jobId"]];
}

- (void)jobStarted:(JTJob *)job {
    if (startingJobNotificationsEnabled) {
        [self sendNotificationWithTitle:@"Job Started" withJob:job];
    }
}

- (void)jobCompleted:(JTJob *)job {
    if (completedJobNotificationsEnabled) {
        [self sendNotificationWithTitle:@"Job Completed" withJob:job];
    }
}

- (void)jobFailed:(JTJob *)job {
    if (failedJobNotificationsEnabled) {
        [self sendNotificationWithTitle:@"Job Failed" withJob:job];
    }
}

- (void)startRefresh {
    NSMenuItem *refresh = [statusMenu itemWithTag:REFRESH_TAG];
    [refresh setAttributedTitle:nil];
    [refresh setTitle:@"Refreshing..."];
    [refresh setEnabled:NO];
}

- (void)endRefresh {
    NSMenuItem *refresh = [statusMenu itemWithTag:REFRESH_TAG];
    [refresh setAttributedTitle:nil];
    [refresh setTitle:@"Refresh"];
    [refresh setEnabled:YES];
}

- (void)updateMenuItemWithTag:(NSInteger)tag withJobs:(NSArray *)jobs {
    NSMenu *jobsMenu = [[NSMenu alloc] init];
    NSMenuItem *jobsMenuItem = [statusMenu itemWithTag:tag];
    if ([jobs count] == 0) {
        NSMenuItem *noneItem = [[NSMenuItem alloc] init];
        [noneItem setTitle:@"None"];
        [noneItem setEnabled:NO];
        [jobsMenu addItem:noneItem];
    } else {
        for (JTJob *job in jobs) {
            NSMenuItem *jobItem = [[NSMenuItem alloc] initWithTitle:job.displayName action:@selector(jobSelected:) keyEquivalent:@""];
            [jobItem setRepresentedObject:job];
            [jobItem setTarget:self];
            [jobItem setEnabled:YES];
            [jobsMenu addItem:jobItem];
        }
    }
    [statusMenu setSubmenu:jobsMenu forItem:jobsMenuItem];
}

- (void)jobSelected:(id)sender {
    NSMenuItem *menuItem = sender;
    JTJob *job = [menuItem representedObject];
    [self openJobInBrowser:job.jobId];
}

- (void)openJobInBrowser:(NSString *)jobId {
    NSString *jobUrl = [NSString stringWithFormat:@"%@/jobdetails.jsp?jobid=%@", jobTrackerURL, jobId];
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:jobUrl]];
}

- (IBAction)openInBrowser:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:[jobTrackerURL stringByAppendingString:@"/jobtracker.jsp"]]];
}

- (void)preferencesUpdated {
    [self loadPreferences];
    if ([self isConfigured]) {
        jtState = [JTState sharedInstance];
        jtState.url = [NSURL URLWithString:[jobTrackerURL stringByAppendingString:@"/jobtracker.jsp"]];
        [jtState setUsernameString:usernames];
        jtState.delegate = self;
        [self refresh:nil];
        [self startTimer];
    } else {
        [self showPreferences:nil];
    }
}

@end
