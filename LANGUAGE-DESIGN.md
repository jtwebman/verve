# Verve Language Design

An implementation language designed for AI to write and verify. Humans describe what they want and test the final product.

- Website: vervelang.org
- File extension: .vv

## Philosophy

- **AI writes it, AI verifies it, humans test the product** — the language is optimized for machine authorship and automated verification. Humans can read the code if they want to, but the system doesn't depend on it. Correctness comes from the verifier, not from code review.
- **One way to do things** — no style debates, no cleverness, every problem has one idiomatic solution
- **Verbose is fine** — explicitness helps the verifier, and AI doesn't care about boilerplate
- **Docs are code** — examples are tests, comments are documentation, everything is mandatory
- **Modules are boundaries** — small, self-contained units that AI can build and verify independently

## Syntax

C/JavaScript style. Curly braces, semicolons. Chosen because AI training data contains more of this syntax than any other.

## Core Constructs

### Types

Built-in types for well-known formats. No regex. Constraints only for domain rules.

```
type Name = string;
type Email = email;                         // built-in, RFC 5322
type Website = uri;                         // built-in, RFC 3986
type Age = int { range: 0..150 };           // domain constraint
type Money = decimal { precision: 2, min: 0 };
type AccountId = uuid;
type CreatedAt = utc_datetime;
type Currency = enum { USD, EUR, GBP };
type Latitude = float64;                    // floating point for math/science
type Port = uint16;                         // fixed-width integer
```

### Structs

Data with no behavior attached. No inheritance. No methods. No default values — every field must be explicitly set at creation.

```
struct Account {
    id: AccountId;
    name: Name;
    currency: Currency;
    active: bool;
}

struct Transaction {
    id: uuid;
    from: AccountId;
    to: AccountId;
    amount: Money;
    timestamp: utc_datetime;
}
```

### Unions

Tagged unions. Every variant is explicitly named. Used with `match` which must be exhaustive — the compiler ensures every variant is handled.

```
type ApiResponse = union {
    :success { data: User };
    :error { code: int; message: string };
    :paginated { data: list<User>; next_cursor: string };
}

// every variant must be handled — compiler error if one is missing
match response {
    :success{data} => process_user(data);
    :error{code, message} => handle_error(code, message);
    :paginated{data, next_cursor} => process_page(data, next_cursor);
}
```

Unions work with `Json.decode` — the decoder figures out which variant based on the JSON shape:

```
type FlexibleId = union {
    :string_id { value: string };
    :numeric_id { value: int };
}

struct ApiUser {
    id: FlexibleId;
    name: string;
}

match Json.decode(raw_json, ApiUser) {
    :ok{user} => // id is typed as FlexibleId, match to use it
    :error{reason} => // invalid
}
```

No untagged unions. No `string | int`. Always tagged, always matched.

### Compile-Time Generics

Type parameters resolved at compile time. The compiler stamps out a concrete version for each type used. No runtime cost, no boxing, no virtual dispatch. The verifier checks each concrete version independently.

```
struct Queue<T> {
    items: list<T>;
    head: int;
    tail: int;
}

fn enqueue<T>(queue: Queue<T>, item: T) -> void {
    // ...
}

fn dequeue<T>(queue: Queue<T>) -> T? {
    // ...
}

// compiler generates concrete Queue<Order> and Queue<User>
// each is verified separately
orders: Queue<Order> [capacity: 1000];
users: Queue<User> [capacity: 500];
```

Built-in types already use generics: `list<T>`, `map<K, V>`, `process<T>`, `Result<T>`. User-defined generics follow the same pattern.

Only compile-time. No runtime type parameters, no type erasure, no reflection.

### Function References

Named functions can be passed as parameters. The type is the function signature. No anonymous functions, no lambdas, no closures — only references to named, declared functions.

```
// function type in a parameter
fn sort_by(items: list<Account>, compare: fn(Account, Account) -> bool) -> list<Account> {
    // ...
}

// a named function that matches the signature
fn balance_compare(a: Account, b: Account) -> bool {
    return a.balance > b.balance;
}

// pass it by name
sorted = sort_by(accounts, balance_compare);
```

Every passed function is independently testable and verifiable. No hidden allocation, no captured state.

Process receive handlers cannot be passed as function references. If you need to parameterize which process call to make, wrap it in a named function that does the send explicitly:

```
fn get_checking_balance(ledger: process<Ledger>, id: AccountId) -> Money {
    match send ledger.GetCheckingBalance(id, 5000) {
        :ok{balance} => return balance;
        :error{reason} => return 0;
        :timeout => return 0;
    }
}

// pass the wrapper — send is explicit, timeout is handled
get_highest(ledger, accounts, get_checking_balance);
```

### Functions

Standalone. Always belong to a module or process. Every function declares its return type explicitly — `void` for functions that return nothing.

```
/// Calculates the total for a list of order items.
/// @example calculate_total([{price: 10, quantity: 2}, {price: 5, quantity: 1}]) == 25
/// @property fn(items) { calculate_total(items) >= 0 }
fn calculate_total(items: list<OrderItem>) -> Money {
    total = 0;
    i = 0;
    while i < items.len {
        total = total + (items[i].price * items[i].quantity);
        i = i + 1;
    }
    total;
}
```

### Guards

Boolean expressions only. When a guard evaluates to `false`, the function returns a structured error. No exceptions. No panics. No side effects inside guards — put complex logic in functions that return `bool`.

```
/// Checks if an email is available for registration.
/// @example email_available(db, "new@test.com") == true
/// @example email_available(db, "taken@test.com") == false
fn email_available(db: process<UserDb>, email: Email) -> bool {
    match send db.FindByEmail(email, 5000) {
        :ok{user} => false;
        :error{reason} => false;
        :timeout => false;
    }
}

fn create_user(db: process<UserDb>, name: Name, email: Email) -> Result<User> {
    guard name != "";
    guard email_available(db, email);

    // ...
}

receive Transfer(from: AccountId, to: AccountId, amount: Money) -> Result<void> {
    guard from != to;
    guard amount > 0;
    guard balances[from] != :out_of_bounds;
    guard balances[from] >= amount;

    transition balances[from] { balance - amount; }
    transition balances[to] { balance + amount; }
    append entries { Entry { from: from, to: to, amount: amount } };
    :ok;
}
```

### Transitions

Explicit state changes. Only allowed inside process `receive` handlers — never in module functions. Operates on state fields directly, not on returned values. Everything not mentioned stays the same. The verifier can diff before/after automatically.

```
// transition a state field by key
transition balances[account] { balance - amount; }

// transition multiple fields on a struct in state
transition accounts[id] {
    balance: balance - amount;
    active: false;
}
```

### Modules

Code organization. Groups related types and functions around a concept. Modules are context boundaries — AI builds one module at a time, only seeing imported signatures.

Modules contain no state and no transitions. They can call other module functions and `send`/`tell` to processes.

```
module Pricing {
    /// Applies a fee based on transfer amount.
    /// @example apply_fee(500.00, 0.01) == 505.00
    /// @example apply_fee(0.00, 0.01) == 0.00
    /// @property fn(amount, rate) { apply_fee(amount, rate) >= amount }
    fn apply_fee(amount: Money, rate: decimal) -> Money {
        amount + (amount * rate);
    }

    /// Gets the discounted total for a loyalty member.
    /// Falls back to full price if loyalty service is unavailable.
    /// @example get_discounted_total(loyal_user, items) == 90.00
    fn get_discounted_total(user: UserId, items: list<OrderItem>) -> Money {
        total = calculate_total(items);
        match send loyalty.GetDiscount(user, 5000) {
            :ok{discount} => total - (total * discount);
            :error{reason} => total;
            :timeout => total;
        }
    }

    /// Calculates the raw total for a list of items.
    /// @example calculate_total([{price: 10, quantity: 2}]) == 20
    /// @property fn(items) { calculate_total(items) >= 0 }
    fn calculate_total(items: list<OrderItem>) -> Money {
        total = 0;
        i = 0;
        while i < items.len {
            total = total + (items[i].price * items[i].quantity);
            i = i + 1;
        }
        total;
    }
}
```

### Imports

Modules import signatures, not implementations. You see what a function takes and returns, nothing else.

```
module Transfer {
    use Pricing { apply_fee };

    /// Executes a transfer by sending to the Ledger process.
    /// @example execute(ledger, acc_1, acc_2, 100.00) == :ok
    /// @example execute(ledger, acc_1, acc_1, 100.00) == :error{:guard_failed}
    fn execute(ledger: process<Ledger>, from: AccountId, to: AccountId, amount: Money) -> Result<void> {
        fee = apply_fee(amount, 0.001);
        match send ledger.Transfer(from, to, amount - fee, 5000) {
            :ok{} => {
                tell logger.Log("transfer complete", { from: from, to: to, amount: amount });
                :ok;
            }
            :error{reason} => :error{reason};
            :timeout => :error{:timeout};
        }
    }
}
```

### Processes

Runtime units that own state and communicate through typed messages. A process is not a module — modules are code organization, processes are runtime concepts. You can spawn many processes running the same code.

Processes own their state in memory. No built-in persistence — if a process wants durability it sends data to a database, filesystem, or another process. If a process crashes, its state is gone.

```
process Ledger {
    state {
        entries: list<Entry> [capacity: 100000];
        balances: map<AccountId, Money> [capacity: 50000];
    }

    invariant {
        all(account: AccountId, balances[account] >= 0);
    }

    /// Transfers amount between two accounts atomically.
    /// @example Transfer(acc_1, acc_2, 100.00) == :ok
    /// @example Transfer(acc_1, acc_1, 100.00) == :error{:guard_failed}
    receive Transfer(from: AccountId, to: AccountId, amount: Money) -> Result<void> {
        guard from != to;
        guard amount > 0;
        guard balances[from] >= amount;

        append entries { Entry { from: from, to: to, amount: amount } };
        transition balances[from] { balance - amount; }
        transition balances[to] { balance + amount; }
        :ok;
    }

    /// Returns the current balance for an account.
    /// @example GetBalance(acc_1) == 1000.00
    receive GetBalance(account: AccountId) -> Money {
        balances[account];
    }

    /// Logs a message. No response needed.
    /// @example Log("test", {}) == void
    receive Log(message: string, context: map<string, string>) -> void {
        // fire and forget — caller doesn't wait
    }
}
```

### Messaging

Two keywords distinguish process calls from module calls at every call site:

- **`send`** — send a message to a process, wait for typed response. Last parameter is always the timeout in milliseconds. Must be used in a `match` with `:ok`, `:error`, and `:timeout` cases.
- **`tell`** — send a message to a process, don't wait. Only valid for `receive` handlers that return `void`.

Module function calls use no keyword — they are always blocking, always local.

```
// Process call with response — must match, must have timeout
// GetBalance returns Money, send wraps it in Result<Money> | :timeout
match send ledger.GetBalance(account_id, 5000) {
    :ok{balance} => // balance is Money
    :error{reason} => // guard failed in handler
    :timeout => // ledger didn't respond in 5 seconds
}

// Process call fire-and-forget — void return, no match needed
tell logger.Log("transfer completed", context);

// Module call — no keyword, always blocking
result = Math.add(a, b);

// Module call with match — for Result types
match Account.validate(email) {
    :ok{} => // valid
    :error{reason} => // invalid
}
```

The compiler enforces:
- `send` can only be used with process `receive` handlers that have a return type
- `tell` can only be used with process `receive` handlers that return `void`
- Process handlers cannot be called without `send` or `tell` — compiler error
- Module functions cannot be called with `send` or `tell` — compiler error

### Entry Point

The entry point is `fn main(args: list<string>) -> int` inside a process. There must be exactly one across all files. The return value is the process exit code — 0 for success, positive for error. The entry point is a process so it can spawn, watch, and receive messages.

Short-lived program (CLI tool, script):

```
process App {
    fn main(args: list<string>) -> int {
        println("done");
        return 0;
    }
}
```

Long-lived service (HTTP server, worker):

```
process App {
    state {
        running: bool;
    }

    fn main(args: list<string>) -> int {
        running = true;
        ledger = spawn Ledger();
        watch ledger;

        http = spawn HttpServer(8080, ledger);
        watch http;

        while running {
            receive;  // block until a message, dispatch to handler
        }

        return 0;
    }

    receive ProcessDied(ref: process, reason: CrashReason) -> void {
        // restart children
    }

    receive Shutdown(signal: Signal) -> void {
        running = false;
    }
}
```

`receive;` is a statement that blocks until a message arrives in the process mailbox, then dispatches it to the matching receive handler. It processes exactly one message then continues. No timeout — use the Timer process for periodic work.

If the main process crashes, all child processes are killed and the program exits with a non-zero code. Crash recovery at the program level is the orchestrator's job (K8s, Docker, etc.).

### Imports

Files explicitly import other files. Declarations must be marked `export` to be visible to importers. No export = file-private.

```
// pricing.vv
export type Money = decimal;

export module Pricing {
    fn apply_fee(amount: int, rate: int) -> int {
        return amount + rate;
    }
}

// main.vv
import "./pricing.vv";

module App {
    fn main(args: list<string>) -> int {
        total = Pricing.apply_fee(100, 5);
        println(total);
        return 0;
    }
}
```

The compiler:
- Parses the entry file, finds `import` statements
- Parses imported files (which may have their own imports)
- Detects circular imports — error
- Only exported declarations are visible to importers

### Process Lifecycle

Three primitives for process management:

- **`spawn`** — start a process
- **`watch`** — runtime delivers a `ProcessDied` message when the watched process dies (handles crashes, OOM, kills — the process doesn't need to be alive to send it)
- Supervisors are just processes that `watch` other processes. Not a language feature — a pattern.

```
p = spawn Ledger();
watch p;

receive ProcessDied(ref: process, reason: CrashReason) -> void {
    // restart, log, give up — your choice
    match send db.GetState("ledger", 5000) {
        :ok{state} => {
            new_p = spawn Ledger(state);
            watch new_p;
        }
        :error{reason} => // handle
        :timeout => // handle
    }
}
```

### Process Atomicity

Every `receive` handler is atomic within its process. All state changes in a single handler either complete fully or don't happen. No cross-process transactions — if something needs to be atomic, it belongs in one process.

```
receive Transfer(from: AccountId, to: AccountId, amount: Money) -> Result<void> {
    guard balances[from] >= amount;
    append entries { Entry { from: from, to: to, amount: amount } };
    transition balances[from] { balance - amount; }
    transition balances[to] { balance + amount; }
    :ok;
}
```

### Documentation & Properties

Mandatory. Every public function and receive handler has:
- A doc comment describing what it does
- At least one `@example` — specific cases, compiled as tests
- At least one `@property` — universal truths, verified symbolically or by fuzzing

```
/// Short description of what it does.
/// @example function_call(args) == expected_result
/// @example function_call(bad_args) == :error{:reason}
/// @property fn(args) { universal_truth_about_function }
fn function_name(args) -> ReturnType {
    // ...
}
```

Examples test specific cases. Properties test all cases. Both are mandatory. Both are automated verification signals.

### Invariants

Process-level truths that the verifier checks after every receive handler.

```
process Ledger {
    invariant {
        all(account: AccountId, balances[account] >= 0);
    }
    // ...
}
```

### Match

The only branching construct. Replaces if/else, switch/case, and pattern matching. Must be exhaustive — compiler error if any case is missing. Can be nested.

```
// switch/case on enums
match account.currency {
    :USD => apply_us_rules(account);
    :EUR => apply_eu_rules(account);
    :GBP => apply_uk_rules(account);
    // compiler error if a Currency variant is missing
}

// boolean branching (replaces if/else — both branches always required)
match amount > 1000 {
    true => apply_large_fee(amount);
    false => apply_normal_fee(amount);
}

// inline value assignment
fee = match amount > 1000 {
    true => amount * 0.01;
    false => amount * 0.005;
};

// pattern matching on unions
match response {
    :success{data} => process(data);
    :error{code, message} => log_error(code, message);
}

// pattern matching on option types
match get_account(id) {
    :some{account} => use_account(account);
    :none => handle_missing();
}

// nested match
match account.currency {
    :USD => {
        match amount > 10000 {
            true => apply_us_large_transfer_rules(amount);
            false => apply_us_standard_rules(amount);
        }
    }
    :EUR => apply_eu_rules(amount);
    :GBP => apply_uk_rules(amount);
}
```

### While

The only loop construct. Can be nested. The verifier checks for termination where possible.

```
fn find_first_active(accounts: list<Account>) -> Account? {
    i = 0;
    while i < accounts.len {
        match accounts[i].active {
            true => return accounts[i];
            false => void;
        }
        i = i + 1;
    }
    :none;
}
```

### Error Handling

Two layers. No exceptions. No try/catch. No error bubbling.

**Logic errors** — handled in Verve code with guards, Result<T>, poison values, and match.

```
// guard failure returns:
:error{:guard_failed, :guard_name}

// caller handles module results:
match Transfer.execute(ledger, from, to, amount) {
    :ok{} => // success
    :error{reason} => // handle
}

// caller handles process results:
match send ledger.Transfer(from, to, amount, 5000) {
    :ok{} => // success
    :error{reason} => // guard failed in the handler
    :timeout => // process didn't respond
}
```

**System failures** — process crashes, watcher gets `ProcessDied`. Segfaults, OOM, FFI corruption, hardware faults. Verve code can't cause these if the compiler and runtime are correct.

| Layer | Mechanism | Who handles |
|---|---|---|
| Logic errors | Guards, Result<T>, poison values, match | Verve code |
| System failures | Process crash, ProcessDied message | Watcher process restarts or escalates |
| Program crash | Main dies, non-zero exit | Container orchestrator (K8s, Docker) |

### Poison Values

Operations that fail at runtime don't crash — they produce poison values that propagate through subsequent operations. Guards catch them before they cause damage.

```
a = 9223372036854775807;    // max int64
b = a + 1;                  // b is :overflow
c = b * 2;                  // c is still :overflow — propagates

result = a / 0;             // :div_zero
val = items[999];           // :out_of_bounds if items.len <= 999

f = 0.0 / 0.0;             // :nan
g = 1.0 / 0.0;             // :infinity
```

The verifier can warn if a value that may be poisoned is used without a guard check:

```
fn safe_divide(a: int, b: int) -> int {
    result = a / b;
    guard result != :div_zero;
    result;
}

fn safe_access(items: list<int>, index: int) -> int {
    guard index >= 0;
    guard index < items.len;
    items[index];
}
```

| Operation | Poison value |
|---|---|
| Integer overflow/underflow | `:overflow` |
| Division by zero (int) | `:div_zero` |
| Division by zero (float) | `:infinity` |
| Invalid float math | `:nan` |
| Index out of bounds | `:out_of_bounds` |

No crashes. No silent wrapping. No exceptions. Poison propagates until a guard catches it.

### Deterministic Ordering

Maps and sets have defined iteration order. No "undefined behavior." Same inputs always produce the same outputs. Makes verification possible.

## Memory Model

No garbage collector. No ownership system. No reference counting.

Process state is pre-allocated with declared capacity at spawn. Local variables in functions and receive handlers live on the stack — allocated when the handler runs, freed when it returns. The compiler knows exact stack size at compile time.

```
process Ledger {
    state {
        entries: list<Entry> [capacity: 10000];
        balances: map<AccountId, Money> [capacity: 5000];
    }

    receive Transfer(from: AccountId, to: AccountId, amount: Money) -> Result<void> {
        // local variables — stack allocated, freed when handler returns
        entry = Entry { from: from, to: to, amount: amount };

        guard balances[from] >= amount;
        append entries { entry; }
        transition balances[from] { balance - amount; }
        transition balances[to] { balance + amount; }
        :ok;
    }
}
```

The verifier can prove:
- Exact memory usage per process at compile time (state capacity + max stack size)
- No memory leaks — state is freed when process dies, locals freed when handler returns
- No OOM within a process — capacity is declared and checked
- No GC pauses — nothing to collect

When state hits capacity, it's not a crash — it's a guard failure. The AI writes the overflow strategy (flush to DB, spawn a new process, reject the request).

This is the model used in safety-critical systems (aerospace, medical devices) where pre-allocation is mandatory. Normally too tedious for humans. AI doesn't care about tedious.

## What the language does NOT have

- **Classes / inheritance** — structs and modules, no OOP hierarchy
- **Runtime generics** — compile-time only, compiler stamps out concrete versions per type, no boxing, no virtual dispatch
- **Exceptions / try-catch** — guards, Result<T>, and poison values only
- **Null** — option types (Account?) instead
- **Implicit conversions** — everything explicit
- **Operator overloading** — one meaning per operator
- **Macros** — no metaprogramming, what you see is what you get
- **Global state** — state lives in processes
- **If/else** — use `match` on booleans, always exhaustive
- **For loops** — use `while`, one loop construct
- **Default values** — every field, every argument, always explicit
- **Untyped variables** — all variables must declare their type: `x: int = 42;`
- **Hidden side effects** — `send` and `tell` keywords mark every process boundary
- **Arbitrary mutation** — transitions only, in process receive handlers only
- **Shared mutable state** — processes own their state, no direct access from outside
- **Cross-process transactions** — if it needs to be atomic, it belongs in one process
- **Built-in persistence** — processes manage their own durability
- **Hot code reloading** — deploy new containers instead
- **Garbage collection** — pre-allocated state, stack locals, nothing to collect
- **Dynamic allocation** — all memory is declared upfront or stack-scoped
- **Closures / anonymous functions** — pass named function references instead, no captured state
- **Passing receive handlers as function references** — wrap in a named function that does the send explicitly
- **Recursion** — no function can call itself, directly, mutually, or through function pointers. Compiler detects call graph cycles. Use while loops instead.
- **Recursive data structures** — store flat with ID references, build tree shapes from queries
- **Regex** — if you're writing a pattern, you're doing the AI's job

## Compilation Target

Native binaries for x86_64 and arm64. No VM, no runtime dependency. The binary includes a lightweight process scheduler. Deploy in a container like any other server binary.

## Verifier Signals (for AI training)

The verifier produces:
- `VALID` — all guards consistent, invariants hold, examples pass, properties hold, message types match, `send`/`tell` used correctly, poison values guarded
- `INVALID(reason)` — which invariant/example/guard/property was violated
- `INCOMPLETE` — missing examples, missing docs, missing properties, unhandled match cases
- `DIVERGENT` — function may not terminate

Each signal is a binary training data point. The AI learns to produce `VALID` implementations.

## Workflow

1. Human describes what they want (natural language, rough spec, whatever)
2. AI generates modules and processes — structs, functions, receive handlers, guards, invariants, docs, examples, properties
3. Verifier checks everything — guards consistent, invariants hold, examples pass, properties hold, message types correct, poison values guarded
4. AI iterates until VALID
5. Human tests the running product — does it do what I wanted?

No code review step. Correctness comes from the verifier. Quality comes from using the product. Humans stay at the product level, not the code level.

Each module and process is independent. AI can build 50 in parallel. Verifier checks each one.

## IO Primitives

The language provides a minimal set of built-in processes that wrap OS syscalls. Everything else — HTTP, database protocols, TLS, DNS — is libraries built on top.

| Primitive | What it does |
|---|---|
| `Tcp` | Accept, read, write, close TCP connections |
| `Udp` | Send/receive UDP datagrams |
| `File` | Open, read, write, close files |
| `Timer` | Sleep, schedule callbacks |
| `Stdio` | Console input/output |
| `Signal` | OS signals (SIGTERM, SIGINT) delivered as messages |

IO primitives are processes. They follow the same `send`/`tell` pattern. No special syntax for IO. No async/await. No callback hell.

```
// reading a file is just messaging a process
match send fs.Read("/data/accounts.dat", 8192, 5000) {
    :ok{data} => // got bytes
    :error{reason} => // read failed
    :timeout => // took too long
}

// accepting a TCP connection
match send tcp.Accept(8080, 5000) {
    :ok{conn} => // handle connection
    :error{reason} => // accept failed
    :timeout => // no connection in time
}

// setting a timer
tell timer.After(5000, self(), :tick);
```

Streaming, HTTP servers, database clients, protocol parsers — these are all libraries built from these primitives by the AI. The language doesn't need to know what a stream or an HTTP request is.

## FFI

All foreign code runs inside a process. No exceptions. If the FFI call segfaults, the process dies, the watcher restarts it. The rest of the system is unaffected.

```
process Crypto {
    ffi "libsodium" {
        fn crypto_secretbox(msg: bytes, nonce: bytes, key: bytes) -> bytes;
        fn crypto_secretbox_open(cipher: bytes, nonce: bytes, key: bytes) -> bytes;
    }

    receive Encrypt(msg: bytes, nonce: bytes, key: bytes) -> bytes {
        crypto_secretbox(msg, nonce, key);
    }

    receive Decrypt(cipher: bytes, nonce: bytes, key: bytes) -> Result<bytes> {
        crypto_secretbox_open(cipher, nonce, key);
    }
}

// calling it — just a normal process message
match send crypto.Encrypt(payload, nonce, key, 5000) {
    :ok{encrypted} => // done
    :error{reason} => // encryption failed
    :timeout => // libsodium hung or crashed
}
```

The `ffi` block declares external functions with Verve-typed signatures. The compiler can't verify foreign code but it verifies that Verve code uses the wrapper correctly.

If FFI process overhead matters for performance, the AI rewrites the library in Verve. FFI is for things you *can't* rewrite — OS APIs, hardware drivers, proprietary libraries.

Performance-critical primitives (time, math, memory operations) are built-in to the language — the compiler emits them directly. These are not FFI.

## Package Management

A package is a collection of modules and processes. No special package syntax — it's just what we already have, published somewhere.

```
package verve-http {
    module HttpParser { ... }
    module HttpRouter { ... }
    process HttpServer { ... }
}
```

### Dependencies

Declared in `verve.pkg`. Exact version pins only — no semver ranges, no "compatible with." The AI picks a version, it works, done.

```
// verve.pkg
dependencies {
    verve-http: "v1.2.0" {
        url: "https://github.com/verve-lang/http/releases/download/v1.2.0/verve-http-v1.2.0.tar.gz";
        signed: "verve-lang-team";
        hash: "sha256:a1b2c3...";
    };
    verve-crypto: "v0.5.0" {
        url: "https://github.com/verve-lang/crypto/releases/download/v0.5.0/verve-crypto-v0.5.0.tar.gz";
        signed: "verve-lang-team";
        hash: "sha256:d4e5f6...";
    };
}
```

### Multiple Versions

Different packages can depend on different versions of the same package. Both versions coexist — no conflicts. Each package is isolated through modules and processes with no shared global state. The compiler deduplicates identical code where possible.

No dependency resolution algorithm. No lockfiles. No upgrade cascades. Each package gets exactly the version it asked for.

### Signing & Security

Every published package must be signed. The compiler refuses to build with unsigned or untrusted packages. No flags to bypass this.

```
// verve.trust — project-level trust config
trusted_publishers {
    "verve-lang-team": key("ed25519:...");
    "acme-corp": key("ed25519:...");
}
```

The compiler checks on install:
- Package has a valid signature
- Signature matches a trusted publisher in `verve.trust`
- Content hash matches the declared hash in `verve.pkg`

If any check fails, the build fails. To use a new publisher, explicitly add their key to `verve.trust`.

| Stage | Signing |
|---|---|
| Dev | Local code, unsigned, verified by local compiler |
| Publish | Package signed by author's key |
| Install | Signature and hash verified against trust config |
| Deploy | Final binary can be signed, proving what code and packages went in |

### Hosting

A package is two static files — a signed tarball and its signature. Host them anywhere that serves files: GitHub releases, S3, any CDN, a simple nginx server, a local folder.

```
verve publish ./my-package
# creates:
#   my-package-v1.0.0.tar.gz       (the code)
#   my-package-v1.0.0.tar.gz.sig   (the signature)
#   my-package-v1.0.0.json          (metadata for discovery)
# upload these files anywhere
```

No special server. No registry API. The installer does an HTTP GET, verifies signature, verifies hash, done.

### Caching

A package cache protects against disappearing dependencies. Your CI pulls through a cache that keeps copies. If the origin disappears, the cache still has it. Signature and hash still verify — the cached copy is provably identical.

```
verve cache sync ./verve.pkg --output s3://acme-verve-cache/
# mirrors every dependency to storage you control
```

A cache is just a copy of static files. An S3 bucket, a local folder, any file server. No special software needed.

### Discovery

vervelang.org/packages indexes metadata across all public hosts. Search, browse, read docs. Never serves package content — just points to where files are hosted. Cheap to run because it's metadata only.

Package authors optionally submit their metadata JSON to discovery. Hosts can also send events automatically when new versions are published.

Companies keep private packages on their own host and don't send events to discovery. Same tooling, private network.

### Usage

Same as importing modules. No special package syntax at the use site.

```
use verve-http { HttpServer, HttpRouter };
use verve-crypto { Crypto };
```

## Clustering

A process reference doesn't have to be local. `connect` creates a reference to a process on another machine. Same type, same `send`/`tell`, same timeout handling.

```
// local
logger = spawn Logger();

// remote — explicit, you know it's a network hop
logger = connect Logger("10.0.1.5:4000") {
    cert: "/path/to/client.crt";
    ca: "/path/to/ca.crt";
};

// both are process<Logger> — caller code is identical after creation
tell logger.Log("something happened");
```

- **`spawn`** — local, fast, no network
- **`connect`** — remote, encrypted via TLS, mutual authentication via certificates

Both return `process<T>`. The difference is explicit at the creation site. No transparent distribution — if a call might cross a network, you know.

Roles, permissions, access control — these are application concerns, not language features. The AI builds proxy processes that expose limited interfaces when needed.

Process partitioning, routing, and cluster topology are patterns the AI writes using these primitives. Standard library can provide common patterns (routers, pools, consistent hashing).

## Standard Library

Small. Only things that need compiler support, are used in virtually every program, or are dangerous to get wrong.

### Built into the compiler (not a library — part of the language)

```
// Booleans
bool                    // true, false

// Integers
int = int64 (default), int8, int16, int32, int64
uint8, uint16, uint32, uint64
byte = uint8            // alias

// Floating point
float = float64 (default), float32

// Exact decimal
decimal                 // arbitrary precision

// Text
string                  // UTF-8

// Raw data
bytes                   // list<byte>

// Collections (with capacity)
list<T>, map<K, V>

// Well-known types
uuid, email, uri, phone, utc_datetime, duration

// Return types
Result<T>, void

// Result is a built-in generic union:
// type Result<T> = union { :ok { value: T }; :error { reason: string }; }
// send returns Result<T> | :timeout where T is the handler's return type.

// Basic math operators
+, -, *, /, %, ==, !=, <, >, <=, >=

// Poison values — propagate through operations, caught by guards
// :overflow      — integer overflow/underflow
// :div_zero      — integer division by zero
// :nan           — invalid float math (0.0/0.0)
// :infinity      — float division by zero (1.0/0.0)
// :out_of_bounds — index beyond list length
```

### Standard library modules (ship with Verve, always available)

```
module String       // split, join, trim, contains, replace, starts_with, ends_with, len
module Bytes        // slice, concat, encode, decode, len
module Math         // sin, cos, sqrt, pow, log, abs, min, max, floor, ceil, random
module Time         // now, diff, format, parse
module Uuid         // generate, parse, to_string
module Json         // encode, decode (with automatic struct mapping and type validation)
module Base64       // encode, decode
module Hex          // encode, decode
module Hash         // sha256, sha512, blake3
module Sort         // sort lists by key
module TextParser   // split by delimiter, parse fields, handle quoting/escaping, line-by-line
module BinaryParser // read bytes as int/float/string at offsets, endianness, pack/unpack
module Env          // get, set environment variables
module Args         // parse command line arguments
module System       // hostname, cpu_count, os, exit(code)
module Dns          // resolve hostname to IP
```

### IO primitives (ship with Verve, process-based)

```
process Tcp      // accept, read, write, close TCP connections
process Udp      // send/receive UDP datagrams
process File     // open, read, write, close files
process Timer    // sleep, schedule
process Stdio    // console input/output
process Signal   // OS signals (SIGTERM, SIGINT) delivered as messages
```

### Not in the standard library (packages)

Everything else is a package — HTTP, TLS, database drivers, compression, image processing, CSV, YAML, TOML, protobuf, msgpack, logging frameworks, test frameworks beyond built-in @example/@property.

The AI grabs packages for these or rewrites them in Verve from the parsing primitives.

### Json struct mapping

The compiler knows struct shapes. `Json.encode` and `Json.decode` map between JSON and structs automatically. Type constraints are validated during decode — invalid emails, bad UUIDs, out-of-range numbers are caught.

```
struct User {
    id: uuid;
    name: string;
    email: email;
    active: bool;
}

json_string = Json.encode(user);

match Json.decode(raw_json, User) {
    :ok{user} => // fully typed, all constraints validated
    :error{reason} => // tells you exactly what's wrong
}
```

No annotations. No schema definitions. No fromJson/toJson methods. The struct IS the schema.

## Parked Ideas

1. **Memory-mapped files** — doesn't fit the message model. Can be added later as an FFI wrapper process if needed for specific use cases (databases, large file processing).
2. **Streaming** — library concern, not language. Built from IO primitives by the AI.
3. **Unsafe / inline FFI** — start strict (all FFI through processes), loosen later if needed.
4. **Decimal precision/rounding** — domain concern, AI picks rounding strategy per use case.
5. **Standard library detailed APIs** — define as we build the compiler and write real Verve code.
