//
//  BookmarksSyncManager.m
//  DocSets
//
//  Created by Julien Poissonnier on 2/13/12.
//  Copyright (c) 2012 Julien Poissonnier. All rights reserved.
//

#import <DropboxSDK/DropboxSDK.h>
#import "BookmarksSyncManager.h"
#import "DocSet.h"
#import "DocSetDownloadManager.h"

@interface BookmarksSyncManager () <DBRestClientDelegate>
- (void)startNextSync;
- (void)syncFinished;
@property (nonatomic, strong) DocSet *currentDocSet;
@property (nonatomic, strong) NSMutableArray *queue;
@property (nonatomic, strong) DBRestClient *restClient;
@property (nonatomic, strong) NSString *metadataHash;
@end

@implementation BookmarksSyncManager
@synthesize queue = _queue;
@synthesize currentDocSet = _currentDocSet;
@synthesize restClient = _restClient;
@synthesize metadataHash = _metadataHash;

- (id)init
{
	self = [super init];
	if (self) {
		_queue = [[NSMutableArray alloc] init];
	}
	return self;
}

+ (BookmarksSyncManager *)sharedBookmarksSyncManager
{
	static id sharedBookmarksSyncManager = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		sharedBookmarksSyncManager = [[self alloc] init];
	});
	return sharedBookmarksSyncManager;
}

- (DBRestClient *)restClient
{
	if (!_restClient && [[DBSession sharedSession] isLinked]) {
		_restClient = [[DBRestClient alloc] initWithSession:[DBSession sharedSession]];
		_restClient.delegate = self;
	}
	return _restClient;
}

- (void)sync
{
	if ([self.queue count] > 0) return; //already synching

	if (![[DBSession sharedSession] isLinked]) {
		[[DBSession sharedSession] link];
	} else {
		NSArray *docSets = [[DocSetDownloadManager sharedDownloadManager] downloadedDocSets];
		for (DocSet *docSet in docSets) {
			[self.queue addObject:docSet];
		}
	}
	[self startNextSync];
}

- (void)syncFinished
{
	self.currentDocSet = nil;
	[self startNextSync];
}

- (void)startNextSync
{
	if ([self.queue count] == 0) {
		[[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];
		return;
	}

	self.currentDocSet = [self.queue objectAtIndex:0];
	[self.queue removeObjectAtIndex:0];

	[[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:YES];
	[self.restClient loadMetadata:@"/" withHash:self.metadataHash];
}

- (void)restClient:(DBRestClient *)client loadedMetadata:(DBMetadata *)metadata {
	NSString *bookmarksPath = [[self.currentDocSet path] stringByAppendingPathComponent:@"Bookmarks.plist"];
	NSString *filename = [[[self.currentDocSet path] lastPathComponent] stringByAppendingString:@".bookmarks.plist"];
	NSFileManager *fm = [NSFileManager defaultManager];

	if (metadata.isDirectory) {
		BOOL found = NO;
		for (DBMetadata *file in metadata.contents) {
			if ([file.filename isEqualToString:filename]) {
				found = YES;
				if ([fm fileExistsAtPath:bookmarksPath]) {
					NSError *error;
					NSDictionary *attrs = [fm attributesOfItemAtPath:bookmarksPath error:&error];
					NSDate *localModificationDate = [attrs objectForKey:NSFileModificationDate];
					NSDate *remoteModificationDate = file.lastModifiedDate;
					if ([localModificationDate compare:remoteModificationDate] == NSOrderedDescending) {
						[self.restClient uploadFile:filename toPath:@"/" withParentRev:file.rev fromPath:bookmarksPath];
					} else if ([localModificationDate compare:remoteModificationDate] == NSOrderedAscending) {
						[self.restClient loadFile:[@"/" stringByAppendingString:filename] intoPath:bookmarksPath];
					} else {
						//same modification date, do nothing
						[self syncFinished];
					}
				} else {
					//exists remote only, leave it there and do nothing;
					[self syncFinished];
				}
				break;
			}
		}
		if (!found) {
			//bookmarks.plist doesn't exist on dropbox yet
			[self.restClient uploadFile:filename toPath:@"/" withParentRev:nil fromPath:bookmarksPath];
		}
	}
}

- (void)restClient:(DBRestClient *)client loadMetadataFailedWithError:(NSError *)error
{
	NSLog(@"Error loading metadata: %@", error);
	[self syncFinished];
}

- (void)restClient:(DBRestClient*)client loadedFile:(NSString*)destPath contentType:(NSString*)contentType metadata:(DBMetadata*)metadata;
{
	//update local modification date to that of dropbox
	NSFileManager *fm = [NSFileManager defaultManager];
	NSString *bookmarksPath = [[self.currentDocSet path] stringByAppendingPathComponent:@"Bookmarks.plist"];
	NSError *error;
	NSDictionary *attrs = [NSDictionary dictionaryWithObject:metadata.lastModifiedDate forKey:NSFileModificationDate];
	[fm setAttributes:attrs ofItemAtPath:bookmarksPath error:&error];
	[self.currentDocSet refreshBookmarks]; //bookmarks table needs to reload
	[self syncFinished];
}

- (void)restClient:(DBRestClient *)client loadFileFailedWithError:(NSError *)error
{
	NSLog(@"Error loading file: %@", error);
	[self syncFinished];
}

- (void)restClient:(DBRestClient*)client uploadedFile:(NSString*)destPath from:(NSString*)srcPath metadata:(DBMetadata*)metadata
{
	//update local modification date to that of dropbox
	NSFileManager *fm = [NSFileManager defaultManager];
	NSString *bookmarksPath = [[self.currentDocSet path] stringByAppendingPathComponent:@"Bookmarks.plist"];
	NSError *error;
	NSDictionary *attrs = [NSDictionary dictionaryWithObject:metadata.lastModifiedDate forKey:NSFileModificationDate];
	[fm setAttributes:attrs ofItemAtPath:bookmarksPath error:&error];
	[self syncFinished];
}

- (void)restClient:(DBRestClient *)client uploadFileFailedWithError:(NSError *)error
{
	NSLog(@"Error uploading file: %@", error);
	[self syncFinished];
}

@end
