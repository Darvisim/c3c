module std::os::posix @if(env::POSIX);
import libc, std::os::darwin;

struct Posix_spawn_file_actions_t
{
	int __allocated;
	int __used;
	void* __actions;
	int[16] __pad;
}

struct Posix_spawnattr_t
{
	void*[42] opaque;
}

extern fn CInt posix_spawn_file_actions_init(Posix_spawn_file_actions_t *file_actions);
extern fn CInt posix_spawn_file_actions_destroy(Posix_spawn_file_actions_t *file_actions);
extern fn CInt posix_spawn_file_actions_addclose(Posix_spawn_file_actions_t *file_actions, CInt fd);
extern fn CInt posix_spawn_file_actions_adddup2(Posix_spawn_file_actions_t *file_actions, CInt fd, CInt newfd);

extern fn CInt get_nprocs() @if(!env::DARWIN || !env::BSD_FAMILY);
extern fn CInt get_nprocs_conf() @if(!env::DARWIN || !env::BSD_FAMILY);

alias spawn_file_actions_init = posix_spawn_file_actions_init;
alias spawn_file_actions_destroy = posix_spawn_file_actions_destroy;
alias spawn_file_actions_addclose = posix_spawn_file_actions_addclose;
alias spawn_file_actions_adddup2 = posix_spawn_file_actions_adddup2;

extern fn CInt posix_spawnp(Pid_t* pid, char* file, Posix_spawn_file_actions_t* file_actions,
	Posix_spawnattr_t* attrp, ZString* argv, ZString* envp);
extern fn CInt posix_spawn(Pid_t* pid, char* file, Posix_spawn_file_actions_t* file_actions,
	Posix_spawnattr_t* attrp, ZString* argv, ZString* envp);
alias spawnp = posix_spawnp;
alias spawn = posix_spawn;

extern fn CInt getpid();
extern fn CInt kill(Pid_t pid, CInt sig);
extern fn Pid_t waitpid(Pid_t pid, CInt* stat_loc, int options);
extern fn CInt raise(CInt sig);
extern fn usz backtrace(void** buffer, CInt size) @if(env::BSD_FAMILY);
extern fn CInt backtrace(void** buffer, CInt size) @if(!env::BSD_FAMILY && !env::LINUX && !env::ANDROID && !env::EMSCRIPTEN);
extern fn ZString* backtrace_symbols(void** buffer, usz size) @if(env::BSD_FAMILY);
extern fn ZString* backtrace_symbols(void** buffer, CInt size) @if(!env::BSD_FAMILY);
extern fn CInt backtrace_symbols_fd(void** buffer, usz size, CInt fd) @if(env::BSD_FAMILY);
extern fn void backtrace_symbols_fd(void** buffer, CInt size, CInt fd) @if(!env::BSD_FAMILY);
macro CInt wEXITSTATUS(CInt status) => (status & 0xff00) >> 8;
macro CInt wTERMSIG(CInt status) => status & 0x7f;
macro CInt wSTOPSIG(CInt status) => wEXITSTATUS(status);
macro bool wIFEXITED(CInt status) => wTERMSIG(status) == 0;
macro bool wIFSIGNALED(CInt status) => ((ichar) ((status & 0x7f) + 1) >> 1) > 0;
macro bool wIFSTOPPED(CInt status) => (status & 0xff) == 0x7f;
macro bool wIFCONTINUED(CInt status) => status == __W_CONTINUED;
macro CInt wWCOREDUMP(CInt status) => status & __WCOREFLAG;
macro CInt w_EXITCODE(CInt ret, CInt sig) => (ret << 8) | sig;
macro CInt w_STOPCODE(CInt sig) => (sig << 8) | 0x7f;
const CInt __WCOREFLAG = 0x80;
const CInt __W_CONTINUED = 0xffff;
const CInt WNOHANG = 1;
const CInt WUNTRACES = 2;

tlocal SigJmpBuf backtrace_jmpbuf @local;
alias BacktraceFn = fn CInt(void** buffer, CInt size);

fn void install_signal_handler(CInt signal, SigActionFunction func)
{
    CInt flags = libc::SA_SIGINFO;

    $if env::LINUX:
        flags |= libc::SA_ONSTACK;
    $endif

    Sigaction action = {
        .sa_sigaction = func,
        .sa_flags = flags
    };
    libc::sigemptyset(&action.sa_mask);

    Sigaction old;
    libc::sigaction(signal, &action, &old);
}

fn CInt backtrace(void** buffer, CInt size) @if(env::LINUX || env::ANDROID || env::EMSCRIPTEN)
{
	if (size < 1) return 0;
	void* handle = libc::dlopen("libc.so.6", libc::RTLD_LAZY|libc::RTLD_NODELETE);
	if (handle)
	{
		defer libc::dlclose(handle);
		BacktraceFn backtrace_fn = libc::dlsym(handle, "backtrace");
		if (backtrace_fn)
		{
			return backtrace_fn(buffer, size);
		}
	}
	// Loop through the return addresses until we hit a signal.
	// This avoids using the frame address.
	Sigaction restore_backtrace = {
		.sa_sigaction = fn void(CInt, void*, void*) { libc::siglongjmp(&backtrace_jmpbuf, 1); },
		.sa_flags = libc::SA_SIGINFO
	};
	Sigaction sig_bus, sig_segv, sig_ill;
	libc::sigaction(libc::SIGBUS, &restore_backtrace, &sig_bus);
	libc::sigaction(libc::SIGSEGV, &restore_backtrace, &sig_segv);
	libc::sigaction(libc::SIGILL, &restore_backtrace, &sig_ill);

	int i = 0;
	if (libc::sigsetjmp(&backtrace_jmpbuf, 1) == 0)
	{
		for (i = 0; i < size; i++)
		{
			void* addr = builtin::get_returnaddress(i);
			if (!addr) break;
			buffer[i] = addr;
		}
	}

	Sigaction old;
	libc::sigaction(libc::SIGBUS, &sig_bus, &old);
	libc::sigaction(libc::SIGSEGV, &sig_segv, &old);
	libc::sigaction(libc::SIGILL, &sig_ill, &old);

	return i;
}

struct PosixUContext_t @if(env::DARWIN)
{
	int                     uc_onstack;
	__Darwin_sigset_t       uc_sigmask;     /* signal mask used by this context */
	__Darwin_sigaltstack    uc_stack;       /* stack used by this context */
	PosixUContext_t*        uc_link;        /* pointer to resuming context */
	__Darwin_size_t         uc_mcsize;      /* size of the machine context passed in */
	__Darwin_mcontext64*    uc_mcontext;    /* pointer to machine specific context */
}

/* taken from sys/ucontext.h */
typedef Greg_t     @if(env::LINUX && env::X86_64) = long;
typedef Greg_t     @if(env::NETBSD && env::X86_64) = ulong;
const REG_RIP      @if(env::LINUX && env::X86_64) = 16;
const _REG_RIP     @if(env::NETBSD && env::X86_64) = 21;
struct LibcFPState @if(env::LINUX && env::X86_64) { char[512] __data; }
typedef Fpregset_t @if(env::NETBSD && env::X86_64) = char[512];
struct Fxsave64 @if(env::OPENBSD && env::X86_64) { char[512] __data; }

struct MContext_t @align(16) @if(env::LINUX && env::X86_64)
{
	Greg_t[23] gregs;
	LibcFPState* fpregs;
	ulong[8] __reserved1;
}

struct MContext_t @align(16) @if(env::LINUX && env::AARCH64)
{
	ulong fault_address;
	ulong[31] regs;
	ulong sp;
	ulong pc;
	ulong pstate;
	char[4096] __reserved;
}

struct PosixUContext_t @if(env::LINUX && env::X86_64)
{
	ulong            uc_flags;
	PosixUContext_t* uc_link;
	Stack_t          uc_stack;
	MContext_t       uc_mcontext;
	Sigset_t         uc_sigmask;
	LibcFPState		 __fpregs_mem;
	ulong[4]		 __ssp;
}

struct MContext_t @align(8) @if(env::NETBSD && env::X86_64)
{
	Greg_t[26] __gregs;
	Greg_t _mc_tlsbase;
	Fpregset_t __fpregs;
}

struct PosixUContext_t @if(env::NETBSD && env::X86_64)
{
	uint uc_flags;
	PosixUContext_t* uc_link;
	Sigset_t uc_sigmask;
	Stack_t uc_stack;
	MContext_t uc_mcontext;
}

struct MContext_t @align(16) @if(env::FREEBSD && env::X86_64)
{
	long mc_onstack;
    long mc_rdi;
    long mc_rsi;
    long mc_rdx;
    long mc_rcx;
    long mc_r8;
    long mc_r9;
    long mc_rax;
    long mc_rbx;
    long mc_rbp;
    long mc_r10;
    long mc_r11;
    long mc_r12;
    long mc_r13;
    long mc_r14;
    long mc_r15;
	uint mc_trapno;
    ushort mc_fs;
    ushort mc_gs;
    long mc_addr;
    uint mc_flags;
    ushort mc_es;
    ushort mc_ds;
	long mc_err;
    long mc_rip;
    long mc_cs;
    long mc_rflags;
    long mc_rsp;
    long mc_ss;
	long mc_len;
    long mc_fpformat;
    long mc_ownedfp;
	long[64] mc_fpstate;
	long mc_fsbase;
    long mc_gsbase;
    long mc_xfpustate;
    long mc_xfpustate_len;
    long mc_tlsbase;
	long[3] mc_spare;
}

struct PosixUContext_t @if(env::FREEBSD && env::X86_64)
{
	Sigset_t uc_sigmask;
	MContext_t uc_mcontext;
	PosixUContext_t *uc_link;
	Stack_t uc_stack;
	int uc_flags;
	int[4] __spare__;
}

struct Sigcontext @packed @if(env::OPENBSD && env::X86_64)
{
	long	sc_rdi;
	long	sc_rsi;
	long	sc_rdx;
	long	sc_rcx;
	long	sc_r8;
	long	sc_r9;
	long	sc_r10;
	long	sc_r11;
	long	sc_r12;
	long	sc_r13;
	long	sc_r14;
	long	sc_r15;
	long	sc_rbp;
	long	sc_rbx;
	long	sc_rax;
	long	sc_gs;
	long	sc_fs;
	long	sc_es;
	long	sc_ds;
	long	sc_trapno;
	long	sc_err;
	long	sc_rip;
	long	sc_cs;
	long	sc_rflags;
	long	sc_rsp;
	long	sc_ss;
    Fxsave64 *sc_fpstate;
    int	    __sc_unused;
	int	    sc_mask;
	long	sc_cookie;
}

typedef PosixUContext_t @if(env::OPENBSD && env::X86_64) = Sigcontext;

alias PosixUContext_t @if(!env::DARWIN && !((env::LINUX || env::BSD_FAMILY) && env::X86_64)) = void;

macro void* stack_instruction(PosixUContext_t* uc)
{
	$switch:
		$case env::DARWIN && env::AARCH64:
			return (void*)uc.uc_mcontext.__ss.__pc + 1;
/*		$case env::DARWIN && env::X86_64:
			return (void*)uc.uc_mcontext.__ss.__rip;
		$case env::LINUX && env::X86:
			return uc.uc_mcontext.gregs[REG_EIP];*/
		$case env::LINUX && env::X86_64:
			return (void*)uc.uc_mcontext.gregs[REG_RIP];
/*		$case env::LINUX && env::AARCH64:
			return (void*)uc.uc_mcontext.pc;*/
		$case env::FREEBSD && env::X86_64:
			return (void*)uc.uc_mcontext.mc_rip;
		$case env::OPENBSD && env::X86_64:
			return (void*)uc.sc_rip;
		$case env::NETBSD && env::X86_64:
			return (void*)uc.uc_mcontext.__gregs[_REG_RIP];
		$default:
			return null;
	$endswitch
}
