var cached_data = {};
var func_name_0 = "WKNetworkSessionDelegate [- URLSession:dataTask:didReceiveResponse:completionHandler:] method";
console.warn("\n[*] Hooking: " + func_name_0);
var hook_0 = ObjC.classes.WKNetworkSessionDelegate["- URLSession:dataTask:didReceiveResponse:completionHandler:"];
Interceptor.attach(hook_0.implementation, {
	onEnter: function(args) {
		console.info("[*] Detected call to method: " + func_name_0);
		var dataTask = ObjC.Object(args[3]);
		console.info("    - URL: " + dataTask.currentRequest().URL().toString());
		console.info("    - Headers: " + dataTask.response().allHeaderFields().toString());
		var contentType = dataTask.response().valueForHTTPHeaderField_("Content-Type");
		if (contentType)
			contentType = contentType.toString();
		if (contentType && contentType.startsWith("application/json"))
			cached_data[dataTask.taskIdentifier().toString()] = new Uint8Array();
	},
});
var func_name_1 = "WKNetworkSessionDelegate [- URLSession:dataTask:didReceiveData:] method";
console.warn("\n[*] Hooking: " + func_name_1);
var hook_1 = ObjC.classes.WKNetworkSessionDelegate["- URLSession:dataTask:didReceiveData:"];
Interceptor.attach(hook_1.implementation, {
	onEnter: function(args) {
		console.info("[*] Detected call to method: " + func_name_1);
		var dataTask = ObjC.Object(args[3]);
		var data = ObjC.Object(args[4]);
		console.info("    - URL: " + dataTask.currentRequest().URL().toString());
		console.info("    - This data: <" + data.length() + " bytes>");
		var arrayOne = cached_data[dataTask.taskIdentifier().toString()];
		if (arrayOne) {
			var arrayTwo = new Uint8Array(data.bytes().readByteArray(data.length()));
			var mergedArray = new Uint8Array(arrayOne.length + arrayTwo.length);
			mergedArray.set(arrayOne);
			mergedArray.set(arrayTwo, arrayOne.length);
			console.info("    - All data: <" + mergedArray.length + " bytes>");
			cached_data[dataTask.taskIdentifier().toString()] = mergedArray;
		}
	},
});
var func_name_2 = "WKNetworkSessionDelegate [- URLSession:task:didCompleteWithError:] method";
console.warn("\n[*] Hooking: " + func_name_2);
var hook_2 = ObjC.classes.WKNetworkSessionDelegate["- URLSession:task:didCompleteWithError:"];
Interceptor.attach(hook_2.implementation, {
	onEnter: function(args) {
		console.warn("[*] Detected call to method: " + func_name_2);
		var dataTask = ObjC.Object(args[3]);
		console.warn("    - URL: " + dataTask.currentRequest().URL().toString());
		var mergedArray = cached_data[dataTask.taskIdentifier().toString()];
		if (typeof mergedArray !== 'undefined' && mergedArray.length > 0) {
			console.warn("    - All data: <" + mergedArray.length + " bytes>");
			let buf = Memory.alloc(mergedArray.byteLength);
			buf.writeByteArray(mergedArray);
			let data = ObjC.classes.NSData.dataWithBytes_length_(buf, mergedArray.byteLength);
			let string = ObjC.classes.NSString.alloc().initWithData_encoding_(data, 4);
			console.error(string.toString());
		}
		delete cached_data[dataTask.taskIdentifier().toString()];
	},
});