module std::os::darwin::uikit @if(env::OS_TYPE == IOS) @link("UIKit.framework");

extern fn int uiApplicationMain(
	int argc,
	char** argv,
	void* principalClassName,
	void* delegateClassName
) @cname("UIApplicationMain");