module std::os::freebsd @if(env::FREEBSD);
import libc, std::os, std::collections::list;

// Top-level identifiers <sys/sysctl.h>
const CTL_SYSCTL	= 0;		// "magic" numbers 
const CTL_KERN		= 1;		// "high kernel": proc, limits 
const CTL_VM		= 2;		// virtual memory 
const CTL_VFS		= 3;		// filesystem, mount type is next 
const CTL_NET		= 4;		// network, see socket.h 
const CTL_DEBUG		= 5;		// debugging parameters 
const CTL_HW		= 6;		// generic cpu/io 
const CTL_MACHDEP	= 7;		// machine dependent 
const CTL_USER		= 8;		// user-level 
const CTL_P1003_1B	= 9;		// POSIX 1003.1B 

// CTL_HW identifiers
const HW_MACHINE		 = 1;		// string: machine class 
const HW_MODEL			 = 2;		// string: specific machine model 
const HW_NCPU			 = 3;		// int: number of cpus 
const HW_BYTEORDER		 = 4;		// int: machine byte order 
const HW_PHYSMEM		 = 5;		// int: total memory 
const HW_USERMEM		 = 6;		// int: non-kernel memory 
const HW_PAGESIZE		 = 7;		// int: software page size 
const HW_DISKNAMES		 = 8;		// strings: disk drive names 
const HW_DISKSTATS		 = 9;		// struct: diskstats[] 
const HW_FLOATINGPT		 = 10;		// int: has hw floating point? 
const HW_MACHINE_ARCH	 = 11;		// string: machine architecture 
const HW_REALMEM		 = 12;		// int: 'real' memory 

fn Backtrace? backtrace_line_parse(Allocator allocator, String obj, String addr2line) @local
{
	@stack_mem(256; Allocator mem)
	{
		String[] parts = addr2line.trim().split(mem, " at ");
		if (parts.len != 2) return NOT_FOUND~;

		int line = 0;
		String source = "";
		if (!parts[1].contains("?") && parts[1].contains(":"))
		{
			sz index = parts[1].rindex_of_char(':')!;
			source = parts[1][:index];
			line = parts[1][index + 1..].to_int()!;
		}
		return {
			.function    = parts[0].copy(allocator),
			.object_file = obj.copy(allocator),
			.file        = source.copy(allocator),
			.line        = line,
			.allocator   = allocator,
			.is_inline   = false,
		};
	};
}

fn void? backtrace_add_addr2line(Allocator allocator, BacktraceList* list, String obj, String addr2line) @local
{
	list.push(backtrace_line_parse(allocator, obj, addr2line)!);
}

fn void? backtrace_add_from_exec(Allocator allocator, BacktraceList* list, String fun, String obj) @local
{
	char[1024] buf @noinit;
	String addr2line = process::run_capture_stdout(&buf, {"llvm-addr2line", "-fpe", obj, fun})!;
	return backtrace_add_addr2line(allocator, list, obj, addr2line);
}

fn void? backtrace_add_element(Allocator allocator, BacktraceList *list, String fun, String obj) @local
{
	return backtrace_add_from_exec(allocator, list, fun, obj);
}

fn BacktraceList? symbolize_backtrace(Allocator allocator, void*[] backtrace)
{
	BacktraceList list;
	list.init(allocator, backtrace.len);
	defer catch
	{
		foreach (trace : list)
		{
			trace.free();
		}
		list.free();
	}

	ZString *strings = posix::backtrace_symbols_fmt(backtrace.ptr, backtrace.len, "%n%D %f");

	for (int i = 0; i < backtrace.len; i++) {
		String full = strings[i].str_view();
		Splitter iter = full.tokenize(" ");
		String fun = iter.next()!;
		String obj = iter.next()!;
		backtrace_add_element(allocator, &list, fun, obj)!;
	}

	free(strings);
	return list;
}

