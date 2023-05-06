#import <Foundation/Foundation.h>
#import <os/log.h>
#import <pthread.h>

#define PREFS_PATH "/var/mobile/Library/Preferences/ch.xxtou.webkitnetworkingdumper.plist"

@interface NSURL (PrivateMatches)
- (NSString *)wkValidScheme;
- (NSString *)wkValidHost;
- (NSString *)wkValidPath;
- (BOOL)wkRuleMatches:(NSArray <NSString *> *)matches;
- (NSString *)wkSuggestedPathAtRoot:(NSString *)rootPath inSession:(NSString *)sessionID isRequest:(BOOL)isRequest isHeader:(BOOL)isHeader;
@end

@implementation NSURL (PrivateMatches)

+ (NSURL *)wkValidURLWithString:(NSString *)urlString
{
    NSURL *url;
    
    if ([urlString hasPrefix:@"*:"])
    {
        url = [NSURL URLWithString:[@"ANY:" stringByAppendingString:[urlString substringFromIndex:2]]];
    }
    else
    {
        url = [NSURL URLWithString:urlString];
    }
    
    NSString *urlScheme = [url.scheme uppercaseString];
    if (![urlScheme isEqualToString:@"ANY"]
        && ![urlScheme isEqualToString:@"HTTP"]
        && ![urlScheme isEqualToString:@"HTTPS"]
        && ![urlScheme isEqualToString:@"FILE"]
        && ![urlScheme isEqualToString:@"FTP"]
        && ![urlScheme isEqualToString:@"URN"])
    {
        return nil;
    }
    
    return url;
}

- (NSString *)wkValidScheme
{
    if ([self.scheme isEqualToString:@"ANY"])
        return @"*";
    return self.scheme;
}

- (NSString *)wkValidHost
{
    if (!self.port)
        return self.host;
    return [self.host stringByAppendingFormat:@":%@", self.port];
}

- (NSString *)wkValidPath
{
    if (self.scheme && !self.host && !self.path)
    {
        NSString *validPath = [@"/" stringByAppendingString:[self.absoluteString substringFromIndex:self.scheme.length + 1]];
        return validPath;
    }
    return self.path;
}

- (BOOL)wkRuleMatches:(NSArray <NSString *> *)matches
{
	BOOL validPass = NO;
	NSURL *url = self;

	for (NSString *match in matches)
	{
		if (![match isKindOfClass:[NSString class]])
			continue;

		if (![match isEqualToString:@"<all_urls>"])
		{
			NSURL *matchURL = [NSURL wkValidURLWithString:match];
			if (!matchURL)
				continue;

			NSString *validScheme = [matchURL wkValidScheme];
			NSString *urlValidScheme = [url wkValidScheme];
			if (validScheme && ![validScheme isEqualToString:@"*"] && ![validScheme isEqualToString:urlValidScheme])
				continue;

			else if ([validScheme isEqualToString:@"*"] && !([[urlValidScheme uppercaseString] isEqualToString:@"HTTP"] || [[urlValidScheme uppercaseString] isEqualToString:@"HTTPS"]))
				continue;

			NSString *validHost = [matchURL wkValidHost];
			NSString *urlValidHost = [url wkValidHost];
			if (validHost && ![validHost isEqualToString:@"*"] && ![validHost isEqualToString:urlValidHost])
			{
				if (![validHost hasPrefix:@"*."])
					continue;

				NSString *hostSuffix = [validHost substringFromIndex:2];
				if (![urlValidHost hasSuffix:hostSuffix])
					continue;
			}

			NSString *validPath = [matchURL wkValidPath];
			if (!validPath.length)
				continue;

			NSString *urlValidPath = [url wkValidPath];
			if ([validPath containsString:@"*"])
			{
				NSString *escapedPath = [NSRegularExpression escapedPatternForString:validPath];
				escapedPath = [escapedPath stringByReplacingOccurrencesOfString:@"\\*" withString:@".*"];
				escapedPath = [NSString stringWithFormat:@"^%@$", escapedPath];

				NSRegularExpression *pathRegex = [NSRegularExpression regularExpressionWithPattern:escapedPath options:kNilOptions error:nil];
				if (!pathRegex)
					continue;

				NSTextCheckingResult *pathRes = [pathRegex firstMatchInString:urlValidPath options:kNilOptions range:NSMakeRange(0, urlValidPath.length)];
				if (!pathRes)
					continue;
			}
			else if (![validPath isEqualToString:urlValidPath])
			{
				continue;
			}
		}
		else
		{
			NSString *urlValidScheme = [url.scheme uppercaseString];
			if (![urlValidScheme isEqualToString:@"HTTP"]
				&& ![urlValidScheme isEqualToString:@"HTTPS"]
				&& ![urlValidScheme isEqualToString:@"FILE"]
				&& ![urlValidScheme isEqualToString:@"FTP"]
				&& ![urlValidScheme isEqualToString:@"URN"])
				continue;
		}

		validPass = YES;
		break;
	}

	return validPass;
}

- (NSString *)wkSuggestedPathAtRoot:(NSString *)rootPath inSession:(NSString *)sessionID isRequest:(BOOL)isRequest isHeader:(BOOL)isHeader
{
	NSString *lastPathComponent = [[self pathComponents] lastObject];
	NSString *fullName = [NSString stringWithFormat:
			@"%@_%@.%@", 
			lastPathComponent, 
			sessionID, 
			(isRequest ? (
				isHeader ? @"req-header" : @"req"
			) : (
				isHeader ? @"resp-header" : @"resp"
			))];
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSString *fullPath = [rootPath stringByAppendingPathComponent:fullName];
	if (![fileManager fileExistsAtPath:fullPath]) {
		return fullPath;
	}
	NSString *fileName = [fullName stringByDeletingPathExtension];
	NSString *extension = [fullName pathExtension];
	NSInteger i = 1;
	do {
		fullPath = [rootPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%ld.%@", fileName, (long)i++, extension]];
	} while ([fileManager fileExistsAtPath:fullPath]);
	return fullPath;
}

@end

// [
// 	{
// 		"matches": ["<all_urls>"],
// 		"statusCodes": [200, 201, 202, 203, 204, 205, 206, 207, 208, 226],
// 		"contentTypes": ["application/json", "text/html"],
// 	}
// ]

static os_log_t mLogger_A;
static os_log_t mLogger_FS;
static os_log_t mLogger_REQ;
static os_log_t mLogger_RESP;
static NSMutableArray <NSDictionary *> *mRules;
static pthread_rwlock_t mRulesLock;
static NSMutableDictionary <NSString *, NSMutableData *> *mDataPool;
static pthread_mutex_t mDataPoolMutex;

NS_INLINE
NSString *GlobalTaskIdentifierInSession(NSURLSession *session, NSURLSessionTask *task)
{
	return [NSString stringWithFormat:@"%p-%lu", session, [task taskIdentifier]];
}

static NSString *HostPathForURL(NSURL *url)
{
	static NSString *sRootPath = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		NSFileManager *fileManager = [NSFileManager defaultManager];
		NSURL *cachesURL = [fileManager URLForDirectory:NSCachesDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:nil];
		sRootPath = [[cachesURL path] stringByAppendingPathComponent:@"com.apple.WebKit.Networking"];
		sRootPath = [sRootPath stringByAppendingPathComponent:@"ch.xxtou.webkitnetworkingdumper"];
		BOOL sRootCreated = [fileManager createDirectoryAtPath:sRootPath withIntermediateDirectories:YES attributes:nil error:nil];
		if (!sRootCreated) {
			os_log_error(mLogger_FS, "Failed to create root path %{public}@", sRootPath);
		} else {
			os_log_debug(mLogger_FS, "Root path %{public}@", sRootPath);
		}
	});

	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSString *currentHost = [url host];
	NSString *hostPath = [sRootPath stringByAppendingPathComponent:currentHost];
	BOOL sHostCreated = [fileManager createDirectoryAtPath:hostPath withIntermediateDirectories:YES attributes:nil error:nil];
	if (!sHostCreated) {
		os_log_error(mLogger_FS, "Failed to create host path %{public}@", hostPath);
	} else {
		os_log_debug(mLogger_FS, "Host path %{public}@", hostPath);
	}

	return hostPath;
}

%hook WKNetworkSessionDelegate

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler
{
	if (!session || !dataTask || ![response isKindOfClass:[NSHTTPURLResponse class]]) {
		os_log_debug(mLogger_RESP, "Invalid session or response");
		%orig;
		return;
	}

	NSString *globalIdentifier = GlobalTaskIdentifierInSession(session, dataTask);
	NSURL *currentURL = response.URL;
	if (!currentURL) {
		os_log_debug(mLogger_RESP, "%{public}@: Invalid URL", globalIdentifier);
		%orig;
		return;
	}

	BOOL shouldDump = NO;
	NSInteger statusCode = [(NSHTTPURLResponse *)response statusCode];
	NSString *contentType = [(NSHTTPURLResponse *)response valueForHTTPHeaderField:@"Content-Type"];
	contentType = [[contentType componentsSeparatedByString:@";"] firstObject];

	if (!contentType.length)
		contentType = @"application/octet-stream";

	pthread_rwlock_rdlock(&mRulesLock);
	os_log_debug(mLogger_RESP, "%{public}@: Checking %lu rules", globalIdentifier, mRules.count);
	NSUInteger ruleIndex = 0;
	for (NSDictionary *mRule in mRules) {
		ruleIndex++;

		if (![mRule isKindOfClass:[NSDictionary class]]) {
			os_log_debug(mLogger_RESP, "%{public}@: Invalid rule #%lu", globalIdentifier, ruleIndex);
			continue;
		}

		BOOL requiresMatches = [mRule[@"matches"] isKindOfClass:[NSArray class]];
		BOOL requiresStatusCodes = [mRule[@"statusCodes"] isKindOfClass:[NSArray class]];
		BOOL requiresContentTypes = [mRule[@"contentTypes"] isKindOfClass:[NSArray class]];

		if (!requiresMatches && !requiresStatusCodes && !requiresContentTypes) {
			os_log_debug(mLogger_RESP, "%{public}@: Rule #%lu does not have any requirements", globalIdentifier, ruleIndex);
			continue;
		}

		BOOL validMatches = requiresMatches && [currentURL wkRuleMatches:mRule[@"matches"]];
		BOOL validStatusCodes = requiresStatusCodes && [mRule[@"statusCodes"] containsObject:@(statusCode)];
		BOOL validContentTypes = requiresContentTypes && [mRule[@"contentTypes"] containsObject:contentType];

		if (requiresMatches && !validMatches) {
			os_log_debug(mLogger_RESP, "%{public}@: Rule #%lu does not match url %{public}@", globalIdentifier, ruleIndex, currentURL);
			continue;
		}

		if (requiresStatusCodes && !validStatusCodes) {
			os_log_debug(mLogger_RESP, "%{public}@: Rule #%lu does not match status code %ld", globalIdentifier, ruleIndex, statusCode);
			continue;
		}

		if (requiresContentTypes && !validContentTypes) {
			os_log_debug(mLogger_RESP, "%{public}@: Rule #%lu does not match content type %{public}@", globalIdentifier, ruleIndex, contentType);
			continue;
		}

		shouldDump = YES;
		break;
	}
	pthread_rwlock_unlock(&mRulesLock);

	if (!shouldDump) {
		os_log_debug(mLogger_RESP, "%{public}@: No rule matched for url %{public}@ statusCode %ld contentType %{public}@", globalIdentifier, currentURL, statusCode, contentType);
		%orig;
		return;
	}

	NSString *hostPath = HostPathForURL(currentURL);
	NSString *dumpPath = [currentURL wkSuggestedPathAtRoot:hostPath inSession:globalIdentifier isRequest:NO isHeader:YES];
	NSDictionary *allHeaders = [(NSHTTPURLResponse *)response allHeaderFields];
	BOOL dumped = [allHeaders writeToFile:dumpPath atomically:YES];
	if (dumped) {
		os_log_debug(mLogger_RESP, "%{public}@: Dumped %lu header enteries to %{public}@", globalIdentifier, allHeaders.count, dumpPath);
	} else {
		os_log_debug(mLogger_RESP, "%{public}@: Failed to dump data to %{public}@", globalIdentifier, dumpPath);
	}

	pthread_mutex_lock(&mDataPoolMutex);
	NSMutableData *data = [[NSMutableData alloc] init];
	mDataPool[globalIdentifier] = data;
	os_log_debug(mLogger_RESP, "%{public}@: Begin dumping data for url %{public}@", globalIdentifier, currentURL);
	pthread_mutex_unlock(&mDataPoolMutex);

	%orig;
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data
{
	if (!session || !dataTask) {
		os_log_debug(mLogger_RESP, "Invalid session");
		%orig;
		return;
	}

	NSString *globalIdentifier = GlobalTaskIdentifierInSession(session, dataTask);

	pthread_mutex_lock(&mDataPoolMutex);
	NSMutableData *dataPool = mDataPool[globalIdentifier];
	if (dataPool) {
		[dataPool appendData:data];
		os_log_debug(mLogger_RESP, "%{public}@: Received %lu bytes, %lu bytes in total", globalIdentifier, data.length, dataPool.length);
	}
	pthread_mutex_unlock(&mDataPoolMutex);

	%orig;
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error
{
	if (!session || !task) {
		os_log_debug(mLogger_RESP, "Invalid session");
		%orig;
		return;
	}

	NSString *globalIdentifier = GlobalTaskIdentifierInSession(session, task);
	if (error) {
		os_log_debug(mLogger_RESP, "%{public}@: Completed with error %{public}@", globalIdentifier, error);
	} else {
		os_log_debug(mLogger_RESP, "%{public}@: Completed without any error", globalIdentifier);
	}

	NSURL *currentURL = [[task currentRequest] URL];
	NSString *hostPath = HostPathForURL(currentURL);
	NSString *dumpPath = [currentURL wkSuggestedPathAtRoot:hostPath inSession:globalIdentifier isRequest:NO isHeader:NO];

	pthread_mutex_lock(&mDataPoolMutex);
	NSMutableData *dataPool = mDataPool[globalIdentifier];
	if (dataPool) {
		BOOL dumped = [dataPool writeToFile:dumpPath atomically:YES];
		if (dumped) {
			os_log_debug(mLogger_RESP, "%{public}@: Dumped %lu bytes to %{public}@", globalIdentifier, dataPool.length, dumpPath);
		} else {
			os_log_debug(mLogger_RESP, "%{public}@: Failed to dump data to %{public}@", globalIdentifier, dumpPath);
		}
	} else {
		os_log_debug(mLogger_RESP, "%{public}@: No data to dump", globalIdentifier);
	}
	[mDataPool removeObjectForKey:globalIdentifier];
	pthread_mutex_unlock(&mDataPoolMutex);

	%orig;
}

%end

@interface NSURLSessionTask (SPI)
@property (retain, readonly) NSURLSession *session; 
@end

%hook NSURLSessionTask

- (void)resume
{
	NSString *globalIdentifier = GlobalTaskIdentifierInSession([self session], self);
	os_log_debug(mLogger_REQ, "%{public}@: Resumed", globalIdentifier);

	NSURLRequest *request = [self currentRequest] ?: [self originalRequest];
	NSURL *currentURL = request.URL;
	if (!currentURL) {
		os_log_debug(mLogger_REQ, "%{public}@: Invalid URL", globalIdentifier);
		%orig;
		return;
	}

	NSString *hostPath = HostPathForURL(currentURL);
	NSString *headerDumpPath = [currentURL wkSuggestedPathAtRoot:hostPath inSession:globalIdentifier isRequest:YES isHeader:YES];
	NSDictionary *allHeaders = [request allHTTPHeaderFields];
	BOOL headerDumped = [allHeaders writeToFile:headerDumpPath atomically:YES];
	if (headerDumped) {
		os_log_debug(mLogger_REQ, "%{public}@: Dumped %lu header enteries to %{public}@", globalIdentifier, allHeaders.count, headerDumpPath);
	} else {
		os_log_debug(mLogger_REQ, "%{public}@: Failed to dump data to %{public}@", globalIdentifier, headerDumpPath);
	}

	NSData *requestData = [request HTTPBody];
	if (!requestData.length) {
		os_log_debug(mLogger_REQ, "%{public}@: No HTTP body", globalIdentifier);
		%orig;
		return;
	}

	BOOL shouldDump = NO;
	NSString *httpMethod = [request HTTPMethod];
	NSString *contentType = [request valueForHTTPHeaderField:@"Content-Type"];
	contentType = [[contentType componentsSeparatedByString:@";"] firstObject];

	if (!contentType.length)
		contentType = @"application/octet-stream";
	
	pthread_rwlock_rdlock(&mRulesLock);
	os_log_debug(mLogger_REQ, "%{public}@: Checking %lu rules", globalIdentifier, mRules.count);
	NSUInteger ruleIndex = 0;

	for (NSDictionary *mRule in mRules) {
		ruleIndex++;

		if (![mRule isKindOfClass:[NSDictionary class]]) {
			os_log_debug(mLogger_REQ, "%{public}@: Invalid rule #%lu", globalIdentifier, ruleIndex);
			continue;
		}

		BOOL isRequest = [mRule[@"request"] isKindOfClass:[NSNumber class]] && [mRule[@"request"] boolValue];
		if (!isRequest) {
			os_log_debug(mLogger_REQ, "%{public}@: Rule #%lu is not a request rule", globalIdentifier, ruleIndex);
			continue;
		}

		BOOL requiresMatches = [mRule[@"matches"] isKindOfClass:[NSArray class]];
		BOOL requiresMethods = [mRule[@"methods"] isKindOfClass:[NSArray class]];
		BOOL requiresContentTypes = [mRule[@"contentTypes"] isKindOfClass:[NSArray class]];

		if (!requiresMatches && !requiresMethods && !requiresContentTypes) {
			os_log_debug(mLogger_REQ, "%{public}@: Rule #%lu does not have any requirements", globalIdentifier, ruleIndex);
			continue;
		}

		BOOL validMatches = requiresMatches && [currentURL wkRuleMatches:mRule[@"matches"]];
		BOOL validMethods = requiresMethods && [mRule[@"methods"] containsObject:httpMethod];
		BOOL validContentTypes = requiresContentTypes && [mRule[@"contentTypes"] containsObject:contentType];

		if (requiresMatches && !validMatches) {
			os_log_debug(mLogger_REQ, "%{public}@: Rule #%lu does not match url %{public}@", globalIdentifier, ruleIndex, currentURL);
			continue;
		}

		if (requiresMethods && !validMethods) {
			os_log_debug(mLogger_REQ, "%{public}@: Rule #%lu does not match method %{public}@", globalIdentifier, ruleIndex, httpMethod);
			continue;
		}

		if (requiresContentTypes && !validContentTypes) {
			os_log_debug(mLogger_REQ, "%{public}@: Rule #%lu does not match content type %{public}@", globalIdentifier, ruleIndex, contentType);
			continue;
		}

		shouldDump = YES;
		break;
	}
	pthread_rwlock_unlock(&mRulesLock);

	if (!shouldDump) {
		os_log_debug(mLogger_REQ, "%{public}@: No rule matched for url %{public}@ method %{public}@ contentType %{public}@", globalIdentifier, currentURL, httpMethod, contentType);
		%orig;
		return;
	}

	NSString *bodyDumpPath = [currentURL wkSuggestedPathAtRoot:hostPath inSession:globalIdentifier isRequest:YES isHeader:NO];
	
	BOOL bodyDumped = [requestData writeToFile:bodyDumpPath atomically:YES];
	if (bodyDumped) {
		os_log_debug(mLogger_REQ, "%{public}@: Dumped %lu bytes to %{public}@", globalIdentifier, requestData.length, bodyDumpPath);
	} else {
		os_log_debug(mLogger_REQ, "%{public}@: Failed to dump data to %{public}@", globalIdentifier, bodyDumpPath);
	}

	%orig;
}

%end

static void LoadRules()
{
	pthread_rwlock_wrlock(&mRulesLock);
	[mRules removeAllObjects];
	NSDictionary <NSString *, id> *prefs = [NSDictionary dictionaryWithContentsOfFile:@PREFS_PATH];
	BOOL enabled = [prefs[@"enabled"] boolValue];
	if (enabled) {
		NSArray <NSDictionary *> *rules = prefs[@"rules"];
		if (rules) {
			[mRules addObjectsFromArray:rules];
		}
		os_log_debug(mLogger_A, "%lu rules loaded", mRules.count);
	} else {
		os_log_debug(mLogger_A, "Disabled");
	}
	pthread_rwlock_unlock(&mRulesLock);
}

%ctor {
	mLogger_A = os_log_create("ch.xxtou.webkitnetworkingdumper", "A");
	mLogger_FS = os_log_create("ch.xxtou.webkitnetworkingdumper", "FS");
	mLogger_REQ = os_log_create("ch.xxtou.webkitnetworkingdumper", "REQ");
	mLogger_RESP = os_log_create("ch.xxtou.webkitnetworkingdumper", "RESP");

	mRules = [[NSMutableArray alloc] init];
	pthread_rwlock_init(&mRulesLock, NULL);

	mDataPool = [[NSMutableDictionary alloc] init];
	pthread_mutex_init(&mDataPoolMutex, NULL);

	LoadRules();
	CFNotificationCenterAddObserver(
		CFNotificationCenterGetDarwinNotifyCenter(),
		NULL,
		(CFNotificationCallback)LoadRules,
		CFSTR("ch.xxtou.webkitnetworkingdumper/ReloadRules"),
		NULL,
		CFNotificationSuspensionBehaviorCoalesce
	);
}