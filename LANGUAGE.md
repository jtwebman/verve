# Verve Language Reference

Verve is a process-oriented language with no exceptions, no recursion, and no implicit nulls. Written in Zig with a native compiler via Zig backend. Designed for building reliable concurrent systems.

## Types

### Primitives
`int`, `float`, `string`, `bool`, `void`

### Collections
- `list<T>` — mutable ordered list. Create with `list()`.
- `map<K, V>` — mutable key-value map. Create with `map()`.
- `set<T>` — mutable deduplicated set. Create with `set()`.

### Stack
- `stack<T>` — mutable LIFO stack. Create with `stack()` or `stack(1, 2, 3)`.

### Queue
- `queue<T>` — mutable FIFO queue. Create with `queue()` or `queue(1, 2, 3)`.

### Other
- `stream` — opaque IO handle (stdout, stderr, stdin, file)
- Tags: `:ok`, `:error`, `:eof` — lightweight labels
- Tagged values: `:ok{42}`, `:error{"reason"}` — tags carrying data
- `Result<T>` = `:ok{value}` or `:error{reason}`
- Optional: `T?` — value or `none` (`none` is a value keyword, not a type)
- Structs, enums, tagged unions, function types

### Poison values
Instead of exceptions: `:overflow`, `:div_zero`, `:out_of_bounds`, `:nan`, `:infinity`. These propagate through all operations.

## Syntax

### Variables (explicit types required)
```
x: int = 42;
name: string = "hello";
items: list<int> = list();
```

### Functions
```
fn add(a: int, b: int) -> int {
    return a + b;
}
```

### Guards (preconditions)
```
fn deposit(amount: int) -> int {
    guard amount > 0;
    return balance + amount;
}
```

### While loops (with break/continue)
```
while condition {
    match done {
        true => break;
        false => continue;
    }
}
```

### Match
```
match value {
    :ok{result} => println(result);
    :error{reason} => println("failed: ", reason);
    _ => println("unknown");
}
```

### If/else
```
if x > 0 {
    println("positive");
} else if x == 0 {
    println("zero");
} else {
    println("negative");
}
```

### String interpolation
```
name: string = "world";
msg: string = "hello ${name}, 1 + 1 = ${1 + 1}";
// Plain braces are just characters: "{}" is the string {}
// Escape with \${ to get literal ${
```

### Structs
All fields require default values — no implicit initialization.
```
struct Point {
    x: int = 0;
    y: int = 0;
}
p: Point = Point { x: 10, y: 20 };
println(p.x);

// Omitted fields use defaults
origin: Point = Point{};  // x=0, y=0
```

### Modules
```
/// Math utilities for integer operations.
export module Math {
    /// Add two integers.
    fn add(a: int, b: int) -> int {
        return a + b;
    }
}
```

### Processes (actor model)
Process state is an explicit struct with a type parameter. Handlers receive state as their first parameter and mutate it via field assignment.
```
struct CounterState {
    count: int = 0;
}

/// A counter that tracks a running total.
export process Counter<CounterState> {
    /// Increment the counter by the given amount.
    receive Increment(state: CounterState, amount: int) -> int {
        guard amount > 0;
        state.count = state.count + amount;
        return state.count;
    }
}
```

### Process communication
```
counter: int = spawn Counter();
match counter.Increment(5) {
    :ok{val} => println("Count: ", val);
    :error{reason} => println("Error: ", reason);
}
tell counter.Increment(1);   // fire-and-forget
watch counter;               // get ProcessDied notification
```

### Imports
```
import "./math.vv";
// then use: Math.add(1, 2)
```

### Append to list
```
items: list<int> = list();
append items { 42; }
```

### Doc comments (required on exported declarations)
```
/// Brief description of what this does.
/// Can span multiple lines.
/// @example add(1, 2) == 3
/// @property add(a, b) == add(b, a)
```

## Built-in Modules

### String
| Function | Signature | Description |
|----------|-----------|-------------|
| `String.len(s)` | `string -> int` | Byte length |
| `String.contains(s, sub)` | `string, string -> bool` | Substring check |
| `String.starts_with(s, pre)` | `string, string -> bool` | Prefix check |
| `String.ends_with(s, suf)` | `string, string -> bool` | Suffix check |
| `String.trim(s)` | `string -> string` | Strip whitespace |
| `String.replace(s, old, new)` | `string, string, string -> string` | Replace all occurrences |
| `String.split(s, delim)` | `string, string -> list<string>` | Split into parts |
| `String.slice(s, start, end)` | `string, int, int -> string` | Substring by byte range |
| `String.byte_at(s, i)` | `string, int -> int` | Raw byte value at index |
| `String.char_at(s, i)` | `string, int -> string` | UTF-8 code point at index |
| `String.char_len(s)` | `string -> int` | Number of UTF-8 code points |
| `String.chars(s)` | `string -> list<string>` | List of code points |
| `String.is_alpha(s)` | `string -> bool` | First byte is a-z/A-Z |
| `String.is_digit(s)` | `string -> bool` | First byte is 0-9 |
| `String.is_whitespace(s)` | `string -> bool` | First byte is space/tab/newline |
| `String.is_alnum(s)` | `string -> bool` | First byte is alphanumeric |

String indexing: `s[i]` returns single-byte string. `.len` returns byte length.

### Map
| Function | Signature | Description |
|----------|-----------|-------------|
| `Map.put(m, key, val)` | `map, K, V -> void` | Insert or update |
| `Map.get(m, key)` | `map, K -> V or none` | Lookup |
| `Map.has(m, key)` | `map, K -> bool` | Key exists |
| `Map.keys(m)` | `map -> list<K>` | All keys as list |

Map indexing: `m["key"]` returns value or `none`. `.len` returns entry count.

### Set
| Function | Signature | Description |
|----------|-----------|-------------|
| `Set.add(s, val)` | `set, T -> void` | Add (deduplicates) |
| `Set.has(s, val)` | `set, T -> bool` | Membership check |
| `Set.remove(s, val)` | `set, T -> void` | Remove if present |
| `Set.values(s)` | `set -> list<T>` | All values as list |

`.len` returns element count.

### Stack
| Function | Signature | Description |
|----------|-----------|-------------|
| `Stack.push(s, val)` | `stack, T -> void` | Push onto top |
| `Stack.pop(s)` | `stack -> T or none` | Pop from top (LIFO) |
| `Stack.peek(s)` | `stack -> T or none` | Read top without removing |

`.len` returns depth.

### Queue
| Function | Signature | Description |
|----------|-----------|-------------|
| `Queue.push(q, val)` | `queue, T -> void` | Push to back |
| `Queue.pop(q)` | `queue -> T or none` | Pop from front (FIFO) |
| `Queue.peek(q)` | `queue -> T or none` | Read front without removing |

`.len` returns depth.

### Stdio
| Function | Signature | Description |
|----------|-----------|-------------|
| `Stdio.out()` | `-> stream` | stdout write stream |
| `Stdio.err()` | `-> stream` | stderr write stream |
| `Stdio.in()` | `-> stream` | stdin read stream |

### File
| Function | Signature | Description |
|----------|-----------|-------------|
| `File.open(path, mode)` | `string, string -> Result<stream>` | Open file. mode: `"r"` or `"w"` |

### Stream
| Function | Signature | Description |
|----------|-----------|-------------|
| `Stream.write(s, data)` | `stream, any -> void` | Write to stream |
| `Stream.write_line(s, data)` | `stream, any -> void` | Write + newline |
| `Stream.read_line(s)` | `stream -> string or :eof` | Read one line |
| `Stream.read_all(s)` | `stream -> string or :eof` | Read remaining content |
| `Stream.close(s)` | `stream -> void` | Close (flushes file writes) |

### Tcp
| Function | Signature | Description |
|----------|-----------|-------------|
| `Tcp.open(host, port)` | `string, int -> Result<stream>` | Connect to remote host |
| `Tcp.listen(host, port)` | `string, int -> Result<stream>` | Bind and listen on port |
| `Tcp.accept(listener)` | `stream -> Result<stream>` | Accept connection |
| `Tcp.port(listener)` | `stream -> int` | Get assigned port number |

### Math
| Function | Signature | Description |
|----------|-----------|-------------|
| `Math.abs(x)` | `int -> int` | Absolute value |
| `Math.min(a, b)` | `int, int -> int` | Minimum of two values |
| `Math.max(a, b)` | `int, int -> int` | Maximum of two values |
| `Math.clamp(x, lo, hi)` | `int, int, int -> int` | Clamp to range |
| `Math.pow(base, exp)` | `int, int -> int` | Integer exponentiation |
| `Math.sqrt(x)` | `int -> int` | Integer square root |
| `Math.log2(x)` | `int -> int` | Floor of log base 2 |

### Env
| Function | Signature | Description |
|----------|-----------|-------------|
| `Env.get(name)` | `string -> string` | Get environment variable (empty if not set) |

### System
| Function | Signature | Description |
|----------|-----------|-------------|
| `System.exit(code)` | `int -> void` | Exit process with code |
| `System.time_ms()` | `-> int` | Current time in milliseconds |

### Convert
| Function | Signature | Description |
|----------|-----------|-------------|
| `Convert.to_string(n)` | `int -> string` | Integer to string |
| `Convert.to_int(s)` | `string -> int` | String to integer (0 on failure) |

### Global functions
| Function | Description |
|----------|-------------|
| `println(...)` | Print values to stderr + newline |
| `print(...)` | Print values to stderr |
| `list()` | Create empty list |
| `map()` | Create empty map |
| `set()` | Create empty set |
| `spawn ProcessName()` | Spawn a process, returns process id |

## Operators
`+`, `-`, `*`, `/`, `%` — arithmetic (overflow-safe)
`==`, `!=`, `<`, `>`, `<=`, `>=` — comparison
`&&`, `||` — logical (short-circuit), `!` — logical not
Precedence: `||` < `&&` < comparison < `+`/`-` < `*`/`/`/`%` < unary
`+` on strings — concatenation

## Key constraints
- **No recursion** — use while loops with explicit stacks
- **No exceptions** — use Result<T> and poison values
- **No implicit null** — optional types (`T?`) are explicit. `none` is a value, not a type. A non-optional value is never absent.
- **Explicit types** — all variable declarations must have type annotations
- **Doc comments required** — on all exported modules, processes, and functions

## CLI
```
verve run file.vv        # Run a program
verve check file.vv      # Type check
verve test file.vv       # Run @example/@property tests
verve fmt file.vv        # Format in place
verve fmt --check file.vv  # Check formatting (CI)
```
