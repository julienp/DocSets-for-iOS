//
//  BookmarksSyncManager.h
//  DocSets
//
//  Created by Julien Poissonnier on 2/13/12.
//  Copyright (c) 2012 Julien Poissonnier. All rights reserved.
//

#import <Foundation/Foundation.h>

#define sync_enabled_preference		@"sync_enabled"

@interface BookmarksSyncManager : NSObject

+ (BookmarksSyncManager *)sharedBookmarksSyncManager;
- (void)sync;

@end
