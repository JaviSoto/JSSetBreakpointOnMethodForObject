//
//  MSDebugger.h
//  MindSnacks
//
//  Created by Javier Soto on 6/24/13.
//
//

#define MSDebugger_Enabled DEBUG

#if MSDebugger_Enabled

/**
 * @discussion MSBreakIntoDebugger() stops the debugger at runtime.
 */
#if TARGET_CPU_ARM
    #define MSDEBUGSTOP(signal) __asm__ __volatile__ ("mov r0, %0\nmov r1, %1\nmov r12, %2\nswi 128\n" : : "r"(getpid ()), "r"(signal), "r"(37) : "r12", "r0", "r1", "cc");
    #define MSBreakIntoDebugger() do { int trapSignal = MSApplicationIsRunningOnDebugger() ? SIGINT : SIGSTOP; MSDEBUGSTOP(trapSignal); if (trapSignal == SIGSTOP) { MSDEBUGSTOP (SIGINT); } } while (false)
#else
    #define MSBreakIntoDebugger() do { int trapSignal = MSApplicationIsRunningOnDebugger() ? SIGINT : SIGSTOP; __asm__ __volatile__ ("pushl %0\npushl %1\npush $0\nmovl %2, %%eax\nint $0x80\nadd $12, %%esp" : : "g" (trapSignal), "g" (getpid ()), "n" (37) : "eax", "cc"); } while (false)
#endif

int MSApplicationIsRunningOnDebugger(void);

#endif