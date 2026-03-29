const std = @import("std");

// ── Lightweight fibers for cooperative scheduling ──
// Each process gets its own stack. context_switch saves/restores
// callee-saved registers and swaps the stack pointer.
// x86-64 Linux only (cross-platform is Priority 5).

pub const FIBER_STACK_SIZE = 16 * 1024; // 16KB per process stack (was 64KB)

/// Saved execution context — just the stack pointer.
/// Callee-saved registers (rbx, rbp, r12-r15) are pushed onto the fiber's stack
/// by context_switch, so restoring rsp restores everything.
pub const Context = struct {
    rsp: usize = 0,
};

pub const FiberState = enum {
    fresh, // initialized but never run
    running, // currently executing
    yielded, // paused via yield, has more work
    done, // entry function returned
};

pub const Fiber = struct {
    context: Context = .{},
    stack_base: [*]u8 = undefined,
    stack_total: usize = 0,
    state: FiberState = .fresh,
};

/// Allocate a fiber with its own stack. Sets up the initial stack frame so the
/// first context_switch into this fiber calls entry_fn(arg).
pub fn fiber_init(f: *Fiber, entry_fn: *const fn (usize) void, arg: usize) !void {
    return fiber_init_sized(f, entry_fn, arg, FIBER_STACK_SIZE);
}

/// Allocate a fiber with a custom stack size.
pub fn fiber_init_sized(fiber: *Fiber, entry_fn: *const fn (usize) void, arg: usize, stack_size: usize) !void {
    // Allocate stack + guard page (PROT_NONE at bottom to catch overflow)
    const total = stack_size + 4096;
    const page_align: std.mem.Alignment = @enumFromInt(12); // 2^12 = 4096
    const mem = try std.heap.page_allocator.alignedAlloc(u8, page_align, total);

    // Protect the guard page (first page) — segfault on stack overflow
    std.posix.mprotect(@alignCast(mem[0..4096]), std.posix.PROT.NONE) catch {};

    fiber.stack_base = mem.ptr;
    fiber.stack_total = total;
    fiber.state = .fresh;

    // Stack grows downward. Top of usable stack (16-byte aligned):
    const stack_top = @intFromPtr(fiber.stack_base) + total;
    var sp = stack_top;

    // Set up initial stack frame for first context_switch entry.
    // context_switch does: pop r15, r14, r13, r12, rbp, rbx, ret
    // So we push: return_addr, rbx, rbp, r12, r13, r14, r15 (reverse order on stack)

    // First, push the trampoline that calls entry_fn(arg)
    // We use a small wrapper: fiber_trampoline reads entry_fn and arg from r12/r13
    sp -= @sizeOf(usize);
    @as(*usize, @ptrFromInt(sp)).* = @intFromPtr(&fiber_trampoline); // "return address" for ret

    // Push fake callee-saved registers (context_switch will pop these)
    sp -= @sizeOf(usize);
    @as(*usize, @ptrFromInt(sp)).* = 0; // rbx
    sp -= @sizeOf(usize);
    @as(*usize, @ptrFromInt(sp)).* = 0; // rbp
    sp -= @sizeOf(usize);
    @as(*usize, @ptrFromInt(sp)).* = @intFromPtr(entry_fn); // r12 = entry_fn
    sp -= @sizeOf(usize);
    @as(*usize, @ptrFromInt(sp)).* = arg; // r13 = arg
    sp -= @sizeOf(usize);
    @as(*usize, @ptrFromInt(sp)).* = 0; // r14
    sp -= @sizeOf(usize);
    @as(*usize, @ptrFromInt(sp)).* = 0; // r15

    fiber.context.rsp = sp;
}

/// Reinitialize a fiber that already has stack memory. Resets the stack frame
/// without reallocating. Much cheaper than fiber_init (no mmap/mprotect).
pub fn fiber_reinit(f: *Fiber, entry_fn: *const fn (usize) void, arg: usize) void {
    if (f.stack_total == 0) return; // no stack allocated

    f.state = .fresh;
    const stack_top = @intFromPtr(f.stack_base) + f.stack_total;
    var sp = stack_top;

    sp -= @sizeOf(usize);
    @as(*usize, @ptrFromInt(sp)).* = @intFromPtr(&fiber_trampoline);
    sp -= @sizeOf(usize);
    @as(*usize, @ptrFromInt(sp)).* = 0; // rbx
    sp -= @sizeOf(usize);
    @as(*usize, @ptrFromInt(sp)).* = 0; // rbp
    sp -= @sizeOf(usize);
    @as(*usize, @ptrFromInt(sp)).* = @intFromPtr(entry_fn); // r12
    sp -= @sizeOf(usize);
    @as(*usize, @ptrFromInt(sp)).* = arg; // r13
    sp -= @sizeOf(usize);
    @as(*usize, @ptrFromInt(sp)).* = 0; // r14
    sp -= @sizeOf(usize);
    @as(*usize, @ptrFromInt(sp)).* = 0; // r15

    f.context.rsp = sp;
}

/// Free the fiber's stack memory.
pub fn fiber_free(f: *Fiber) void {
    if (f.stack_total > 0) {
        // Unprotect guard page before freeing
        const guard: [*]align(4096) u8 = @alignCast(f.stack_base);
        std.posix.mprotect(guard[0..4096], std.posix.PROT.READ | std.posix.PROT.WRITE) catch {};
        const slice: []align(4096) u8 = @alignCast(f.stack_base[0..f.stack_total]);
        std.heap.page_allocator.free(slice);
        f.stack_total = 0;
    }
}

/// Trampoline: called when a fiber is entered for the first time.
/// Reads entry_fn from r12 and arg from r13 (placed there by fiber_init).
fn fiber_trampoline() callconv(.naked) void {
    // r12 = entry_fn, r13 = arg (set up in fiber_init's fake register frame)
    asm volatile (
        \\ mov %%r13, %%rdi
        \\ callq *%%r12
        ::: .{ .memory = true });
    // If entry_fn returns, we need to switch back to the scheduler.
    // The process module handles this by having entry_fn loop forever
    // and context_switch back when idle. If we get here, it's a bug.
    unreachable;
}

// context_switch_asm: standalone assembly routine (no compiler prologue/epilogue).
// Expects: rdi = pointer to from.rsp, rsi = pointer to to.rsp
comptime {
    asm (
        \\.globl context_switch_asm
        \\.type context_switch_asm, @function
        \\context_switch_asm:
        \\    push %rbx
        \\    push %rbp
        \\    push %r12
        \\    push %r13
        \\    push %r14
        \\    push %r15
        \\    mov %rsp, (%rdi)
        \\    mov (%rsi), %rsp
        \\    pop %r15
        \\    pop %r14
        \\    pop %r13
        \\    pop %r12
        \\    pop %rbp
        \\    pop %rbx
        \\    ret
    );
}

extern fn context_switch_asm(from_rsp: *usize, to_rsp: *usize) void;

pub fn context_switch(from: *Context, to: *Context) void {
    context_switch_asm(&from.rsp, &to.rsp);
}
