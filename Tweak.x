#import <Foundation/Foundation.h>
#import <os/log.h>
#import <os/activity.h>
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
				isHeader ? @"req-header" : @"req-body"
			) : (
				isHeader ? @"resp-header" : @"resp-body"
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
		fullPath = [rootPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@_%ld.%@", fileName, (long)i++, extension]];
	} while ([fileManager fileExistsAtPath:fullPath]);
	return fullPath;
}

@end

@interface NSData (Private)
- (NSString *)wkTextRepresentationWithContentType:(NSString *)contentType;
@end

@implementation NSData (Private)

- (NSString *)wkTextRepresentationWithContentType:(NSString *)contentType
{
	contentType = [contentType lowercaseString];
	if ([contentType hasPrefix:@"text/"]
		|| [contentType isEqualToString:@"application/x-www-form-urlencoded"]
		|| [contentType isEqualToString:@"application/json"])
	{
		if ([contentType hasSuffix:@"charset=utf-8"])
		{
			return [[NSString alloc] initWithData:self encoding:NSUTF8StringEncoding];
		}
	}
	return [self description];
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

static BOOL mEnabled = NO;
static NSMutableArray <NSDictionary *> *mRules;
static pthread_rwlock_t mRulesLock;
static NSMutableDictionary <NSString *, NSMutableData *> *mDataPool;
static NSMutableDictionary <NSString *, NSString *> *mDataContentTypes;
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

		NSError *err = nil;
		BOOL sRootCreated = [fileManager createDirectoryAtPath:sRootPath withIntermediateDirectories:YES attributes:nil error:&err];
		if (!sRootCreated) {
			os_log_error(mLogger_FS, "Failed to create root path %{public}@, error %{public}@", sRootPath, err);
		} else {
			os_log_info(mLogger_FS, "Root path is: %{public}@", sRootPath);
		}
	});

	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSString *currentHost = [url host];
	NSString *hostPath = [sRootPath stringByAppendingPathComponent:currentHost];

	NSError *err = nil;
	BOOL sHostCreated = [fileManager createDirectoryAtPath:hostPath withIntermediateDirectories:YES attributes:nil error:&err];
	if (!sHostCreated) {
		os_log_error(mLogger_FS, "Failed to create host path %{public}@, error %{public}@", hostPath, err);
	} else {
		os_log_debug(mLogger_FS, "Host path is: %{public}@", hostPath);
	}

	return hostPath;
}

%hook WKNetworkSessionDelegate

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler
{
	if (!mEnabled) {
		%orig;
		return;
	}

	if (!session || !dataTask || ![response isKindOfClass:[NSHTTPURLResponse class]]) {
		os_log_fault(mLogger_RESP, "Invalid session or response.");
		%orig;
		return;
	}

	NSString *globalIdentifier = GlobalTaskIdentifierInSession(session, dataTask);
	NSURL *currentURL = response.URL;
	if (!currentURL) {
		os_log_fault(mLogger_RESP, "%{public}@: Invalid URL.", globalIdentifier);
		%orig;
		return;
	}

	os_activity_t dataActivity = os_activity_create("Data task response received", OS_ACTIVITY_CURRENT, OS_ACTIVITY_FLAG_DEFAULT);
	struct os_activity_scope_state_s dataActivityScope;

	os_activity_scope_enter(dataActivity, &dataActivityScope);

	BOOL shouldDump = NO;
	NSInteger statusCode = [(NSHTTPURLResponse *)response statusCode];
	NSString *rawContentType = [(NSHTTPURLResponse *)response valueForHTTPHeaderField:@"Content-Type"];
	NSString *contentType = [[rawContentType componentsSeparatedByString:@";"] firstObject];

	if (!contentType.length)
		contentType = @"application/octet-stream";

	pthread_rwlock_rdlock(&mRulesLock);
	os_log_debug(mLogger_RESP, "%{public}@: Checking %lu rules.", globalIdentifier, mRules.count);
	NSUInteger ruleIndex = 0;
	for (NSDictionary *mRule in mRules) {
		ruleIndex++;

		if (![mRule isKindOfClass:[NSDictionary class]]) {
			os_log_error(mLogger_RESP, "%{public}@: Invalid rule #%lu.", globalIdentifier, ruleIndex);
			continue;
		}

		BOOL requiresMatches = [mRule[@"matches"] isKindOfClass:[NSArray class]];
		BOOL requiresStatusCodes = [mRule[@"statusCodes"] isKindOfClass:[NSArray class]];
		BOOL requiresContentTypes = [mRule[@"contentTypes"] isKindOfClass:[NSArray class]];

		if (!requiresMatches && !requiresStatusCodes && !requiresContentTypes) {
			os_log_error(mLogger_RESP, "%{public}@: Rule #%lu does not have any requirements, you must provide one of the following requirements: matches, statusCodes or contentTypes.", globalIdentifier, ruleIndex);
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
		os_log_info(mLogger_RESP, "%{public}@: No rule matched for statusCode %ld contentType %{public}@ url %{public}@", globalIdentifier, statusCode, contentType, currentURL);
		%orig;
		os_activity_scope_leave(&dataActivityScope);
		return;
	} else {
		os_log_info(mLogger_RESP, "%{public}@: Rule #%lu matched for statusCode %ld contentType %{public}@ url %{public}@", globalIdentifier, ruleIndex, statusCode, contentType, currentURL);
	}

	NSString *hostPath = HostPathForURL(currentURL);
	NSString *dumpPath = [currentURL wkSuggestedPathAtRoot:hostPath inSession:globalIdentifier isRequest:NO isHeader:YES];
	NSDictionary *allHeaders = [(NSHTTPURLResponse *)response allHeaderFields];
	BOOL dumped = [allHeaders writeToFile:dumpPath atomically:YES];
	if (dumped) {
		os_log_info(mLogger_RESP, "%{public}@: Headers received, dumped %lu enteries to %{public}@\n%{public}@", globalIdentifier, allHeaders.count, dumpPath, allHeaders);
	} else {
		os_log_error(mLogger_RESP, "%{public}@: Failed to dump headers to %{public}@\n%{public}@", globalIdentifier, dumpPath, allHeaders);
	}

	pthread_mutex_lock(&mDataPoolMutex);
	NSMutableData *data = [[NSMutableData alloc] init];
	mDataPool[globalIdentifier] = data;
	mDataContentTypes[globalIdentifier] = rawContentType;
	os_log_debug(mLogger_RESP, "%{public}@: Begin dumping data for url %{public}@", globalIdentifier, currentURL);
	pthread_mutex_unlock(&mDataPoolMutex);

	%orig;
	os_activity_scope_leave(&dataActivityScope);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data
{
	if (!mEnabled) {
		%orig;
		return;
	}

	if (!session || !dataTask) {
		os_log_fault(mLogger_RESP, "Invalid session.");
		%orig;
		return;
	}

	NSString *globalIdentifier = GlobalTaskIdentifierInSession(session, dataTask);

	os_activity_t dataActivity = os_activity_create("Data task data received", OS_ACTIVITY_CURRENT, OS_ACTIVITY_FLAG_DEFAULT);
	struct os_activity_scope_state_s dataActivityScope;

	os_activity_scope_enter(dataActivity, &dataActivityScope);

	pthread_mutex_lock(&mDataPoolMutex);
	NSMutableData *dataPool = mDataPool[globalIdentifier];
	if (dataPool) {
		[dataPool appendData:data];
		os_log_debug(mLogger_RESP, "%{public}@: Received %lu bytes, %lu bytes in total.", globalIdentifier, data.length, dataPool.length);
	}
	pthread_mutex_unlock(&mDataPoolMutex);

	%orig;
	os_activity_scope_leave(&dataActivityScope);
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error
{
	if (!mEnabled) {
		%orig;
		return;
	}

	if (!session || !task) {
		os_log_error(mLogger_RESP, "Invalid session.");
		%orig;
		return;
	}

	NSString *globalIdentifier = GlobalTaskIdentifierInSession(session, task);
	if (error) {
		os_log_error(mLogger_RESP, "%{public}@: Completed with error %{public}@", globalIdentifier, error);
	}

	os_activity_t dataActivity = os_activity_create("Data task completed", OS_ACTIVITY_CURRENT, OS_ACTIVITY_FLAG_DEFAULT);
	struct os_activity_scope_state_s dataActivityScope;

	os_activity_scope_enter(dataActivity, &dataActivityScope);

	NSURL *currentURL = [[task currentRequest] URL];
	NSString *hostPath = HostPathForURL(currentURL);
	NSString *dumpPath = [currentURL wkSuggestedPathAtRoot:hostPath inSession:globalIdentifier isRequest:NO isHeader:NO];

	pthread_mutex_lock(&mDataPoolMutex);
	NSMutableData *dataPool = mDataPool[globalIdentifier];
	NSString *contentType = mDataContentTypes[globalIdentifier];
	if (dataPool.length) {
		BOOL dumped = [dataPool writeToFile:dumpPath atomically:YES];
		if (dumped) {
			os_log_info(mLogger_RESP, "%{public}@: Task completed, dumped %lu bytes to %{public}@\n%{public}@", globalIdentifier, dataPool.length, dumpPath, [dataPool wkTextRepresentationWithContentType:contentType]);
		} else {
			os_log_error(mLogger_RESP, "%{public}@: Failed to dump data to %{public}@\n%{public}@", globalIdentifier, dumpPath, [dataPool wkTextRepresentationWithContentType:contentType]);
		}
	} else {
		os_log_info(mLogger_RESP, "%{public}@: Task completed, no data to dump.", globalIdentifier);
	}
	[mDataPool removeObjectForKey:globalIdentifier];
	[mDataContentTypes removeObjectForKey:globalIdentifier];
	pthread_mutex_unlock(&mDataPoolMutex);

	%orig;
	os_activity_scope_leave(&dataActivityScope);
}

%end

@interface NSURLSessionTask (SPI)
@property (retain, readonly) NSURLSession *session; 
@end

%hook NSURLSessionTask

- (void)resume
{
	if (!mEnabled) {
		%orig;
		return;
	}

	NSString *globalIdentifier = GlobalTaskIdentifierInSession([self session], self);
	NSURLRequest *request = [self currentRequest] ?: [self originalRequest];
	NSURL *currentURL = request.URL;
	if (!currentURL) {
		os_log_error(mLogger_REQ, "%{public}@: Invalid URL.", globalIdentifier);
		%orig;
		return;
	}

	os_activity_t dataActivity = os_activity_create("Data task resumed", OS_ACTIVITY_CURRENT, OS_ACTIVITY_FLAG_DEFAULT);
	struct os_activity_scope_state_s dataActivityScope;

	os_activity_scope_enter(dataActivity, &dataActivityScope);

	BOOL shouldDump = NO;
	NSString *httpMethod = [request HTTPMethod];
	NSString *contentType = [request valueForHTTPHeaderField:@"Content-Type"];
	contentType = [[contentType componentsSeparatedByString:@";"] firstObject];

	if (!contentType.length)
		contentType = @"application/octet-stream";
	
	pthread_rwlock_rdlock(&mRulesLock);
	os_log_debug(mLogger_REQ, "%{public}@: Checking %lu rules.", globalIdentifier, mRules.count);
	NSUInteger ruleIndex = 0;

	for (NSDictionary *mRule in mRules) {
		ruleIndex++;

		if (![mRule isKindOfClass:[NSDictionary class]]) {
			os_log_error(mLogger_REQ, "%{public}@: Invalid rule #%lu.", globalIdentifier, ruleIndex);
			continue;
		}

		BOOL isRequest = [mRule[@"request"] isKindOfClass:[NSNumber class]] && [mRule[@"request"] boolValue];
		if (!isRequest) {
			os_log_debug(mLogger_REQ, "%{public}@: Rule #%lu is not a request rule.", globalIdentifier, ruleIndex);
			continue;
		}

		BOOL requiresMatches = [mRule[@"matches"] isKindOfClass:[NSArray class]];
		BOOL requiresMethods = [mRule[@"methods"] isKindOfClass:[NSArray class]];
		BOOL requiresContentTypes = [mRule[@"contentTypes"] isKindOfClass:[NSArray class]];

		if (!requiresMatches && !requiresMethods && !requiresContentTypes) {
			os_log_error(mLogger_REQ, "%{public}@: Rule #%lu does not have any requirements, you must provide one of the following requirements: matches, methods or contentTypes.", globalIdentifier, ruleIndex);
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
		os_log_info(mLogger_REQ, "%{public}@: No rule matched for method %{public}@ contentType %{public}@ url %{public}@", globalIdentifier, httpMethod, contentType, currentURL);
		%orig;
		os_activity_scope_leave(&dataActivityScope);
		return;
	} else {
		os_log_info(mLogger_RESP, "%{public}@: Rule #%lu matched for method %{public}@ contentType %{public}@ url %{public}@", globalIdentifier, ruleIndex, httpMethod, contentType, currentURL);
	}

	NSString *hostPath = HostPathForURL(currentURL);
	NSString *headerDumpPath = [currentURL wkSuggestedPathAtRoot:hostPath inSession:globalIdentifier isRequest:YES isHeader:YES];
	NSDictionary *allHeaders = [request allHTTPHeaderFields];
	BOOL headerDumped = [allHeaders writeToFile:headerDumpPath atomically:YES];
	if (headerDumped) {
		os_log_info(mLogger_REQ, "%{public}@: Headers fulfilled, dumped %lu enteries to %{public}@\n%{public}@", globalIdentifier, allHeaders.count, headerDumpPath, allHeaders);
	} else {
		os_log_error(mLogger_REQ, "%{public}@: Failed to dump headers to %{public}@\n%{public}@", globalIdentifier, headerDumpPath, allHeaders);
	}

	NSData *requestData = [request HTTPBody];
	if (!requestData.length) {
		os_log_info(mLogger_REQ, "%{public}@: Task resumed, but no HTTP body to send.", globalIdentifier);
		%orig;
		os_activity_scope_leave(&dataActivityScope);
		return;
	}

	NSString *bodyDumpPath = [currentURL wkSuggestedPathAtRoot:hostPath inSession:globalIdentifier isRequest:YES isHeader:NO];
	
	BOOL bodyDumped = [requestData writeToFile:bodyDumpPath atomically:YES];
	if (bodyDumped) {
		os_log_info(mLogger_REQ, "%{public}@: HTTP body fulfilled, dumped %lu bytes to %{public}@", globalIdentifier, requestData.length, bodyDumpPath);
	} else {
		os_log_error(mLogger_REQ, "%{public}@: Failed to dump data to %{public}@", globalIdentifier, bodyDumpPath);
	}

	%orig;
	os_activity_scope_leave(&dataActivityScope);
}

%end

static void LoadRules()
{
	BOOL priorEnabled = mEnabled;
	pthread_rwlock_wrlock(&mRulesLock);
	[mRules removeAllObjects];
	NSDictionary <NSString *, id> *prefs = [NSDictionary dictionaryWithContentsOfFile:@PREFS_PATH];
	mEnabled = [prefs[@"enabled"] boolValue];
	if (mEnabled) {
		NSArray <NSDictionary *> *rules = prefs[@"rules"];
		if (rules) {
			[mRules addObjectsFromArray:rules];
		}
		os_log_info(mLogger_A, "%lu rules loaded.", mRules.count);
	} else {
		os_log_info(mLogger_A, "Tweak is disabled.");
	}
	pthread_rwlock_unlock(&mRulesLock);
	if (priorEnabled != mEnabled) {
		os_log_info(mLogger_A, "Tweak enabled status changed, clearing data pool.");
		pthread_mutex_lock(&mDataPoolMutex);
		[mDataPool removeAllObjects];
		[mDataContentTypes removeAllObjects];
		pthread_mutex_unlock(&mDataPoolMutex);
	}
}

%ctor {
	mLogger_A = os_log_create("ch.xxtou.webkitnetworkingdumper", "A");
	mLogger_FS = os_log_create("ch.xxtou.webkitnetworkingdumper", "FS");
	mLogger_REQ = os_log_create("ch.xxtou.webkitnetworkingdumper", "REQ");
	mLogger_RESP = os_log_create("ch.xxtou.webkitnetworkingdumper", "RESP");

	mRules = [[NSMutableArray alloc] init];
	pthread_rwlock_init(&mRulesLock, NULL);

	mDataPool = [[NSMutableDictionary alloc] init];
	mDataContentTypes = [[NSMutableDictionary alloc] init];
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