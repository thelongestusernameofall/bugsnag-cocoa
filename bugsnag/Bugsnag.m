//
//  Bugsnag.m
//  Bugsnag
//
//  Created by Simon Maynard on 8/28/13.
//  Copyright (c) 2013 Simon Maynard. All rights reserved.
//

#import <mach/mach.h>

#include "TargetConditionals.h"
#import "Bugsnag.h"
#import "BugsnagLogger.h"

#if TARGET_IPHONE_SIMULATOR || TARGET_OS_IPHONE
    // iOS Simulator or iOS device
    #import "BugsnagIosNotifier.h"
    static NSString *notiferClass = @"BugsnagIosNotifier";
#elif TARGET_OS_MAC
    // Other kinds of Mac OS
    #import "BugsnagOSXNotifier.h"
    static NSString *notiferClass = @"BugsnagOSXNotifier";
#else
    // Unsupported platform
    #import "BugsnagNotifier.h"
    static NSString *notiferClass = @"BugsnagNotifier";
#endif

static BugsnagNotifier *notifier = nil;

/*
 TODO:
 - We should access the ASL http://www.cocoanetics.com/2011/03/accessing-the-ios-system-log/
 */

static int signals[] = {
    SIGABRT,
    SIGBUS,
    SIGFPE,
    SIGILL,
    SIGSEGV,
    SIGTRAP
};

static int signals_count = (sizeof(signals) / sizeof(signals[0]));

void remove_handlers(void);
void handle_signal(int, siginfo_t *, void *);
void handle_exception(NSException *);

void remove_handlers() {
    for (NSUInteger i = 0; i < signals_count; i++) {
        struct sigaction action;
        
        memset(&action, 0, sizeof(action));
        action.sa_handler = SIG_DFL;
        sigemptyset(&action.sa_mask);
        
        sigaction(signals[i], &action, NULL);
    }
    NSSetUncaughtExceptionHandler(NULL);
}

// Handles a raised signal
void handle_signal(int signo, siginfo_t *info, void *uapVoid) {
    if (notifier) {
        // We dont want to be double notified
        remove_handlers();
        
        [notifier notifySignal:signo];
    }
    
    //Propagate the signal back up to take the app down
    raise(signo);
}

// Handles an uncaught exception
void handle_exception(NSException *exception) {
    if (notifier) {
        // We dont want to be double notified
        remove_handlers();
        [notifier notifyUncaughtException:exception];
    }
}

@interface Bugsnag ()
+ (BugsnagNotifier*)notifier;
+ (BOOL) bugsnagStarted;
@end

@implementation Bugsnag

+ (void)startBugsnagWithApiKey:(NSString*)apiKey {
    BugsnagConfiguration *configuration = [[BugsnagConfiguration alloc] init];
    configuration.apiKey = apiKey;
    
    [self startBugsnagWithConfiguration:configuration];
}

+ (void)startBugsnagWithConfiguration:(BugsnagConfiguration*) configuration {

    notifier = [[NSClassFromString(notiferClass) alloc] initWithConfiguration:configuration];
    // Register the notifier to receive exceptions and signals
    NSSetUncaughtExceptionHandler(&handle_exception);
    
    stack_t stack;
    stack.ss_size = SIGSTKSZ;
    stack.ss_sp = malloc(stack.ss_size);
    stack.ss_flags = 0;
    
    if (sigaltstack(&stack, 0) < 0) {
        BugsnagLog(@"Unable to generate sigalstack: %d", errno);
    }
    
    struct sigaction action;
    struct sigaction prev_action;
    
    /* Configure action */
    memset(&action, 0, sizeof(action));
    action.sa_flags = SA_SIGINFO|SA_ONSTACK;
    sigemptyset(&action.sa_mask);
    action.sa_sigaction = &handle_signal;
    
    for (NSUInteger i = 0; i < signals_count; i++) {
        int signalType = signals[i];
        if (sigaction(signalType, &action, &prev_action) != 0) {
            BugsnagLog(@"Unable to register signal handler for %s: %d", strsignal(signalType), errno);
        }
    }
}

+ (BugsnagConfiguration*)configuration {
    if([self bugsnagStarted]) {
        return notifier.configuration;
    }
    return nil;
}

+ (BugsnagConfiguration*)instance {
    return [self configuration];
}

+ (BugsnagNotifier*)notifier {
    return notifier;
}

+ (void) notify:(NSException *)exception {
    [notifier notifyException:exception withData:nil atSeverity: @"warning" inBackground: true];
}

+ (void) notify:(NSException *)exception withData:(NSDictionary*)metaData {
    [notifier notifyException:exception withData:metaData atSeverity: @"warning" inBackground: true];
}

+ (void) notify:(NSException *)exception withData:(NSDictionary*)metaData atSeverity:(NSString*)severity {
    [notifier notifyException:exception withData:nil atSeverity: severity inBackground: true];
}

+ (void) setUserAttribute:(NSString*)attributeName withValue:(id)value {
    [self addAttribute:attributeName withValue:value toTabWithName:USER_TAB_NAME];
}

+ (void) clearUser {
    [self clearTabWithName:USER_TAB_NAME];
}

+ (void) addAttribute:(NSString*)attributeName withValue:(id)value toTabWithName:(NSString*)tabName {
    if([self bugsnagStarted]) {
        [notifier.configuration.metaData addAttribute:attributeName withValue:value toTabWithName:tabName];
    }
}

+ (void) clearTabWithName:(NSString*)tabName {
    if([self bugsnagStarted]) {
        [notifier.configuration.metaData clearTab:tabName];
    }
}

+ (BOOL) bugsnagStarted {
    if (notifier == nil) {
        BugsnagLog(@"Ensure you have started Bugsnag with startWithApiKey: before calling any other Bugsnag functions.");

        return false;
    }
    return true;
}

@end