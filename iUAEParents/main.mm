//  main.m
//  iAmiga
//
//  Created by Stuart Carnie on 2/7/09.
//  Copyright __MyCompanyName__ 2009. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "SingleWindowAppDelegate.h"

int main(int argc, char *argv[]) {
    
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
    int retVal = UIApplicationMain(argc, argv, nil, NSStringFromClass([SingleWindowAppDelegate class]));
    [pool release];
    return retVal;
}
