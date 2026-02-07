module std::os::darwin::cf @if(env::DARWIN) @link(env::DARWIN, "CoreFoundation.framework");

typedef CFAllocatorRef = void*;
typedef CFAllocatorContextRef = void*;
alias CFOptionFlags = usz;

macro CFAllocatorRef default_allocator() => darwin_CFAllocatorGetDefault();
macro void CFAllocatorRef.dealloc(CFAllocatorRef allocator, void* ptr) => darwin_CFAllocatorDeallocate(allocator, ptr);
macro void* CFAllocatorRef.alloc(CFAllocatorRef allocator, usz size) => darwin_CFAllocatorAllocate(allocator, size, 0);
macro usz CFAllocatorRef.get_preferred_size(CFAllocatorRef allocator, usz req_size) => darwin_CFAllocatorGetPreferredSizeForSize(allocator, req_size, 0);
macro void CFAllocatorRef.set_default(CFAllocatorRef allocator) => darwin_CFAllocatorSetDefault(allocator);

extern fn CFAllocatorRef darwin_CFAllocatorCreate(CFAllocatorRef allocator, CFAllocatorContextRef context) @cname("CFAllocatorCreate") @builtin;
extern fn void darwin_CFAllocatorDeallocate(CFAllocatorRef allocator, void* ptr) @cname("CFAllocatorDeallocate") @builtin;
extern fn CFAllocatorRef darwin_CFAllocatorGetDefault() @cname("CFAllocatorGetDefault") @builtin;
extern fn void darwin_CFAllocatorSetDefault(CFAllocatorRef allocator) @cname("CFAllocatorSetDefault") @builtin;
extern fn void* darwin_CFAllocatorAllocate(CFAllocatorRef allocator, CFIndex size, CFOptionFlags hint) @cname("CFAllocatorAllocate") @builtin;
extern fn CFIndex darwin_CFAllocatorGetPreferredSizeForSize(CFAllocatorRef allocator, CFIndex size, CFOptionFlags hint) @cname("CFAllocatorGetPreferredSizeForSize") @builtin;
