module std::os::darwin::uikit @feat(IOS) @link("UIKit.framework");
import std::os::macos::objc;

extern fn int uiApplicationMain(int argc, char **argv, ObjcId principalClassName, ObjcId delegateClassName) @cname("UIApplicationMain");
