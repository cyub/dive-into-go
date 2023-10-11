---
title: "Delve is a debugger for the Go programming language"
---

# Delve

**Delve**[^1] 是使用Go语言实现的，专门用来调试Go程序的工具。它跟 **[GDB]({{< relref "analysis-tools/gdb" >}})** 工具类似，相比 **[GDB]({{< relref "analysis-tools/gdb" >}})**，它简单易用，能更好的理解Go语言数据结构和语言特性。它支持打印 `goroutine` 以及 `defer` 函数等Go特有语法特性。**Delve** 简称 `dlv`，后文将以 `dlv` 代称 **Delve**.

## 安装

```bash
go get -u github.com/go-delve/delve/cmd/dlv
```

## 使用

### 开始调试

`dlv` 使用 `debug` 命令进入调试界面：

```bash
dlv debug main.go
```

如果当前目录是 `main` 包所在目录时候，可以不用指定 `main.go` 文件这个参数的。假定项目结构如下：

```bash
.
├── github.com/me/foo
├── cmd
│   └── foo
│       └── main.go
├── pkg
│   └── baz
│       ├── bar.go
│       └── bar_test.go
```

如果当前已在 `cmd/foo` 目录下，我们可以直接执行 `dlv debug` 命令开始调试。在任何目录下我们可以使用 `dlv debug github.com/me/foo/cmd/foo` 开始调试。

如果已构建成二进制可执行文件，我们可以使用 `dlv exec` 命令开始调试：

```bash
dlv exec /youpath/go_binary_file
```

**对于需要命令行参数才能启动的程序，我们可以通过`--`来传递命令行参数**，比如如下:

```bash
dlv debug github.com/me/foo/cmd/foo -- -arg1 value
dlv exec /mypath/binary -- --config=config.toml
```

对于已经运行的程序，可以使用 `attach` 命令，进行跟踪调试指定 `pid` 的Go应用：

```bash
dlv attach pid
```

除了上面调试 `main` 包外，`dlv` 通过 `test` 子命令还支持调试 `test` 文件：

```bash
dlv test github.com/me/foo/pkg/baz
```

接下来我们可以使用 `help` 命令查看 `dlv` 支持的命令有哪些：

```bash
(dlv) help
The following commands are available:

Running the program:
    call ------------------------ Resumes process, injecting a function call (EXPERIMENTAL!!!)
    continue (alias: c) --------- Run until breakpoint or program termination.
    next (alias: n) ------------- Step over to next source line.
    rebuild --------------------- Rebuild the target executable and restarts it. It does not work if the executable was not built by delve.
    restart (alias: r) ---------- Restart process.
    step (alias: s) ------------- Single step through program.
    step-instruction (alias: si)  Single step a single cpu instruction.
    stepout (alias: so) --------- Step out of the current function.

Manipulating breakpoints:
    break (alias: b) ------- Sets a breakpoint.
    breakpoints (alias: bp)  Print out info for active breakpoints.
    clear ------------------ Deletes breakpoint.
    clearall --------------- Deletes multiple breakpoints.
    condition (alias: cond)  Set breakpoint condition.
    on --------------------- Executes a command when a breakpoint is hit.
    trace (alias: t) ------- Set tracepoint.

Viewing program variables and memory:
    args ----------------- Print function arguments.
    display -------------- Print value of an expression every time the program stops.
    examinemem (alias: x)  Examine memory:
    locals --------------- Print local variables.
    print (alias: p) ----- Evaluate an expression.
    regs ----------------- Print contents of CPU registers.
    set ------------------ Changes the value of a variable.
    vars ----------------- Print package variables.
    whatis --------------- Prints type of an expression.

Listing and switching between threads and goroutines:
    goroutine (alias: gr) -- Shows or changes current goroutine
    goroutines (alias: grs)  List program goroutines.
    thread (alias: tr) ----- Switch to the specified thread.
    threads ---------------- Print out info for every traced thread.

Viewing the call stack and selecting frames:
    deferred --------- Executes command in the context of a deferred call.
    down ------------- Move the current frame down.
    frame ------------ Set the current frame, or execute command on a different frame.
    stack (alias: bt)  Print stack trace.
    up --------------- Move the current frame up.

Other commands:
    config --------------------- Changes configuration parameters.
    disassemble (alias: disass)  Disassembler.
    edit (alias: ed) ----------- Open where you are in $DELVE_EDITOR or $EDITOR
    exit (alias: quit | q) ----- Exit the debugger.
    funcs ---------------------- Print list of functions.
    help (alias: h) ------------ Prints the help message.
    libraries ------------------ List loaded dynamic libraries
    list (alias: ls | l) ------- Show source code.
    source --------------------- Executes a file containing a list of delve commands
    sources -------------------- Print list of source files.
    types ---------------------- Print list of types

Type help followed by a command for full documentation.
```

接下来我们将以下面代码作为示例演示如何dlv进行调试。

```go
package main

import "fmt"

func main() {
	fmt.Println("go")
}
```

### 设置断点

当我们使用 `dlv debug main.go` 命令进行 `dlv` 调试之后，我们可以设置断点。

```bash
(dlv) b main.main # 在main函数处设置断点
Breakpoint 1 set at 0x4adf8f for main.main() ./main.go:5
```

### 继续执行

设置断点之后，我们可以通过 `continue` 命令，可以简写成 `c` ，继续执行到我们设置的断点处。

```bash
(dlv) c
> main.main() ./main.go:5 (hits goroutine(1):1 total:1) (PC: 0x4adf8f)
     1:	package main
     2:
     3:	import "fmt"
     4:
=>   5:	func main() {
     6:		fmt.Println("go")
     7:	}
```

注意不同于 **[GDB]({{< relref "analysis-tools/gdb" >}})** 需要执行 `run` 命令启动应用之后，才能执行 `continue` 命令。而 `dlv` 在进入调试界面之后，已经指向程序的入口地址处，可以直接执行 `continue` 命令

### 执行下一条指令

我们可以通过next命令，可以简写成`n`，来执行下一行源码。同 **[GDB]({{< relref "analysis-tools/gdb" >}})** 一样，`next` 命令是 `Step over` 操作，遇到函数时不会进入函数内部一行行代码执行，而是直接执行函数，然后跳过到函数下面的一行代码。

```bash
(dlv) n
go
> main.main() ./main.go:7 (PC: 0x4adfff)
     2:
     3:	import "fmt"
     4:
     5:	func main() {
     6:		fmt.Println("go")
=>   7:	}
```

### 打印栈信息

通过 `stack` 命令，我们可以查看函数栈信息：

```bash
(dlv) stack
0  0x00000000004adfff in main.main
   at ./main.go:7
1  0x0000000000436be8 in runtime.main
   at /usr/lib/go/src/runtime/proc.go:203
2  0x0000000000464621 in runtime.goexit
   at /usr/lib/go/src/runtime/asm_amd64.s:1373
```

### 打印gorountine信息

通过`goroutines`命令，可以简写成`grs`，我们可以查看所有 `goroutine`：

```bash
(dlv) goroutines
* Goroutine 1 - User: ./main.go:7 main.main (0x4adfff) (thread 14358)
  Goroutine 2 - User: /usr/lib/go/src/runtime/proc.go:305 runtime.gopark (0x436f9b)
  Goroutine 3 - User: /usr/lib/go/src/runtime/proc.go:305 runtime.gopark (0x436f9b)
  Goroutine 4 - User: /usr/lib/go/src/runtime/proc.go:305 runtime.gopark (0x436f9b)
  Goroutine 5 - User: /usr/lib/go/src/runtime/mfinal.go:161 runtime.runfinq (0x418f80)
[5 goroutines]
```

`goroutine` 命令，可以简写成 `gr`，用来显示当前 `goroutine` 信息：

```bash
(dlv) goroutine
Thread 14358 at ./main.go:7
Goroutine 1:
	Runtime: ./main.go:7 main.main (0x4adfff)
	User: ./main.go:7 main.main (0x4adfff)
	Go: /usr/lib/go/src/runtime/asm_amd64.s:220 runtime.rt0_go (0x462594)
	Start: /usr/lib/go/src/runtime/proc.go:113 runtime.main (0x436a20)
```

### 查看汇编代码

通过 `disassemble` 命令，可以简写成 `disass` ，我们可以查看汇编代码：

```bash
(dlv) disass
TEXT main.main(SB) /tmp/dlv/main.go
	main.go:5		0x4adf80	64488b0c25f8ffffff	mov rcx, qword ptr fs:[0xfffffff8]
	main.go:5		0x4adf89	483b6110		cmp rsp, qword ptr [rcx+0x10]
	main.go:5		0x4adf8d	767a			jbe 0x4ae009
	main.go:5		0x4adf8f*	4883ec68		sub rsp, 0x68
	main.go:5		0x4adf93	48896c2460		mov qword ptr [rsp+0x60], rbp
	main.go:5		0x4adf98	488d6c2460		lea rbp, ptr [rsp+0x60]
	main.go:6		0x4adf9d	0f57c0			xorps xmm0, xmm0
	main.go:6		0x4adfa0	0f11442438		movups xmmword ptr [rsp+0x38], xmm0
	main.go:6		0x4adfa5	488d442438		lea rax, ptr [rsp+0x38]
	main.go:6		0x4adfaa	4889442430		mov qword ptr [rsp+0x30], rax
	main.go:6		0x4adfaf	8400			test byte ptr [rax], al
	main.go:6		0x4adfb1	488d0d28ed0000		lea rcx, ptr [rip+0xed28]
	main.go:6		0x4adfb8	48894c2438		mov qword ptr [rsp+0x38], rcx
	main.go:6		0x4adfbd	488d0dcce10300		lea rcx, ptr [rip+0x3e1cc]
	main.go:6		0x4adfc4	48894c2440		mov qword ptr [rsp+0x40], rcx
	main.go:6		0x4adfc9	8400			test byte ptr [rax], al
	main.go:6		0x4adfcb	eb00			jmp 0x4adfcd
	main.go:6		0x4adfcd	4889442448		mov qword ptr [rsp+0x48], rax
	main.go:6		0x4adfd2	48c744245001000000	mov qword ptr [rsp+0x50], 0x1
	main.go:6		0x4adfdb	48c744245801000000	mov qword ptr [rsp+0x58], 0x1
	main.go:6		0x4adfe4	48890424		mov qword ptr [rsp], rax
	main.go:6		0x4adfe8	48c744240801000000	mov qword ptr [rsp+0x8], 0x1
	main.go:6		0x4adff1	48c744241001000000	mov qword ptr [rsp+0x10], 0x1
	main.go:6		0x4adffa	e811a1ffff		call $fmt.Println
=>	main.go:7		0x4adfff	488b6c2460		mov rbp, qword ptr [rsp+0x60]
	main.go:7		0x4ae004	4883c468		add rsp, 0x68
	main.go:7		0x4ae008	c3			ret
	main.go:5		0x4ae009	e8e247fbff		call $runtime.morestack_noctxt
	<autogenerated>:1	0x4ae00e	e96dffffff		jmp $main.main
```

`dlv` 默认显示的是 `intel` 风格汇编代码，我们可以通过 `config` 命令设置 `gnu` 或者 `go` 风格代码：

```bash
(dlv) config disassemble-flavor go
```

这种方式更改的配置只会对此次调试有效，若保证下次调试一样有效，我们需要将其配置到配置文件中。`dlv` 默认配置文件是 `HOME/.config/dlv/config.yml`。我们只需要在配置文件加入以下内容：

```yaml
disassemble-flavor: go
```

[^1]: https://github.com/go-delve/delve
