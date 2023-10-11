---
title: "GDB"
---

# GDB

**GDB**（GNU symbolic Debugger）是Linux系统下的强大的调试工具，可以用来调试ada, c, c++, asm, minimal, d, fortran, objective-c, go, java,pascal 等多种语言。

我们以调试 `go` 代码为示例来介绍GDB的使用。源码内容如下：

```go
package main

import "fmt"

func add(a, b int) int {
	sum := 0
	sum = a + b
	return sum
}
func main() {
	sum := add(10, 20)
	fmt.Println(sum)
}
```

构建二进制应用：

```bash
go build -gcflags="-N -l" -o test main.go
```

## 启动调试

```bash
gdb ./test # 启动调试
gdb --args ./test arg1 arg2 # 指定参数启动调试
```
进入gdb调试界面之后，执行 `run` 命令运行程序。若程序已经运行，我们可以 `attach` 该程序的进程id进行调试:

```bash
$ gdb
(gdb) attach 1785
```

当执行 `attach` 命令的时候，GDB首先会在当前工作目录下查找进程的可执行程序，如果没有找到，接着会用源代码文件搜索路径。我们也可以用file命令来加载可执行文件。

或者通过命令设置进程id:

```bash
gdb test 1785 
gdb test --pid 1785
```

若已运行的进程不含调试信息，我们可以使用同样代码编译出一个带调试信息的版本，然后使用 `file` 和 `attach` 命令进行运行调试。

```bash
$ gdb
(gdb) file test
Reading symbols from test...done.
(gdb) attach 1785
```

### 可视化窗口

GDB也支持多窗口图形启动运行，一个窗口显示源码信息，一个窗口显示调试信息：

```bash
gdb test -tui
```

GDB支持在运行过程中使用 `Crtl+X+A` 组合键进入多窗口图形界面， GDB支持的快捷操作有：

```bash
Crtl+X+A // 多窗口与单窗口界面切换
Ctrl + X + 2 // 显示两个窗口
Ctrl + X + 1 // 显示一个窗口
```

## 运行程序

通过 `run` 命令运行程序：

```bash
(gdb) run
```

指定命令行参数运行：

```bash
(gdb) run arg1 arg2
```

或者通过 `set` 命令设置命令行参数：

```bash
(gdb) set args arg1 arg2
(gdb) run
```

除了 `run` 命令外，我们也可以使用 `start` 命令运行程序。`start` 命令会在在main函数的第一条语句前面停下来。

```bash
(gdb) start
```

## 断点的设置、查看、删除、禁用

### 设置断点

GDB中是通过 `break` 命令来设置断点(BreakPoint)，`break` 可以简写成 `b`。

- break function

    在指定函数出设置断点，设置断点后程序会在进入指定函数时停住

- **break linenum**

    在指定行号处设置断点

- break +offset/-offset

    在当前行号的前面或后面的offset行处设置断点。offset为自然数

- break filename:linenum

    在源文件filename的linenum行处设置断点

- break filename:function

    在源文件filename的function函数的入口处设置断点

- **break \*address**

    在程序运行的内存地址处设置断点

- break

    break命令没有参数时，表示在下一条指令处停住。

- break ... if <condition>

    ...可以是上述的参数，condition表示条件，在条件成立时停住。比如在循环境体中，可以设置break if i=100，表示当i为100时停住程序

### 查看断点

我们可以通过 `info` 命令查看断点：

```bash
(gdb) info breakpoint # 查看所有断点
(gdb) info breakpoint 3 # 查看3号断点
```

### 删除断点

删除断点是通过 `delete` 命令删除的，`delete` 命令可以简写成 `d`：

```bash
(gdb) delete 3 # 删除3号断点
```

### 断点启用与禁用

```bash
(gdb) disable 3 # 禁用3号断点
(gdb) enable 3 # 启用3号断点
```

## 调试

### 单步执行

`next` 用于单步执行，会一行行执行代码，运到函数时候，不会进入到函数内部，跳过该函数，但会执行该函数，即 `step over`。可以简写成 `n`。

```bash
(gdb) next
```

### 单步进入

`step` 用于单步进入执行，跟 `next` 命令类似，但是遇到函数时候，会进入到函数内部一步步执行，即 `step into`。可以简写成 `s`。

```bash
(gdb) step
```

与 `step` 相关的命令 `stepi`，用于每次执行每次执行一条机器指令。可以简写成 `si`。

### 继续执行到下一个断点

`continue` 命令会继续执行程序，直到再次遇到断点处。可以简写成 `c`:

```bash
(gdb) continue
(gdb) continue 3 # 跳过3个断点
```

### 继续运行到指定位置

`until` 命令可以帮助我们实现运行到某一行停住，可以简写成 `u`：

```bash
(gdb) until 5
```

### 跳过执行

`skip` 命令可以在step时跳过一些不想关注的函数或者某个文件的代码:

```bash
(gdb) skip function add   # step时跳过add函数
(gdb) info skip   # 查看skip列表
```

其他相关的命令：

- skip delete [num] 删除skip
- skip enable [num] 启动skip
- skip disable [num] 关闭skip

**注意：** 当不带skip号时候，是针对所有skip进行设置。

### 执行完成当前函数

`finish` 命令用来将当前函数执行完成，并打印函数返回时的堆栈地址、返回值、参数值等信息，即`step out` 。

```bash
(gdb) finish
```

## 查看源码

GDB中的 `list` 命令用来显示源码信息。`list` 命令可以简写成 `l`。

- **list**

    从第一行开始显示源码，继续输入list，可列出后面的源码

- **list linenum**

    列出linenum行附近的源码

- **list function**

    列出函数function的代码

- list filename:linenum

    列出文件filename文件中，linenum行出的代码

- list filename:function

    列出文件filename中，函数function的代码

- list +offset/-offset

    列出在当前行号的前面或后面的offset行附近的代码。offset为自然数。

- list +/-

    列出当前行后面或者前面的代码

- list linenum1, linenum2

    列出行linenum1和linenum2之间的代码

## 查看信息

`info` 命令用来显示信息，可以简写成 `i`。

- **info files**

    显示当前的调试的文件，包含程序入口地址，内存分段布局位置信息等

- info breakpoints

    显示当前设置的断点列表

- info registers

    显示当前寄存器的值，可以简写成 `i r`。指定寄存器名称，可以查看具体寄存器信息：`i r rsp`

- info all-registers

    显示所有寄存器的值。GDB提供四个标准寄存器：`pc` 是程序计数器寄存器，`sp` 是堆栈指针。`fp` 用于记录当前堆栈帧的指针，`ps` 用于记录处理器状态的寄存器。GDB会处理好不同架构系统寄存器不一致问题，比如对于 `amd64` 架构，`pc` 对应就是 `rip` 寄存器。

    引用寄存器内容是将寄存器名前置 `$` 符作为变量来用。比如 `$pc` 就是程序计数器寄存器值。

- info args

    显示当前函数参数

- info locals

    显示当前局部变量

- **info frame**

    查看当前栈帧的详细信息，包括 `rip` 信息，正在运行的指令所在文件位置

- info variables

    查看程序中的变量符号

- info functions

    查看程序中的函数符号

- info functions regexp

    通过正则匹配来查看程序中的函数符号

- info goroutines

    显示当前执行的 `goroutine` 列表，带 `*` 的表示当前执行的。注意需要加载 `go runtime` 支持。

- info stack

    查看栈信息

- info proc mappings

    可以简写成 `i proc m`。用来查看应用内存映射

- info proc [procid]

    显示进程信息

- info proc status

    显示进程相关信息：包括user id和group id；进程内有多少线程；虚拟内存的使用情况；挂起的信号，阻塞的信号，忽略的信号；TTY；消耗的系统和用户时间；堆栈大小；nice值

- info display

- info watchpoints

    列出当前所设置了的所有观察点

- info line [linenum]

    查看第 `linenum` 的代码指令地址信息，不带 `linenum` 时，显示的是当前位置的指令地址信息

- info source

    显示此源代码的源代码语言

- info sources

    显示程序中所有有调试信息的源文件名，一共显示两个列表：一个是其符号信息已经读过的，一个是还未读取过的

- info types

    显示程序中所有类型符号

- info types regexp

    通过正则匹配来查看程序中的类型符号

其他类似命令有：

- show args

    查看命令行参数

- show environment [envname]

    查看环境变量信息

- show paths

    查看程序的运行路径

- whatis var1

    显示变量var1类型

- ptype var1

    显示变量 `var1` 类型，若是 `var1` 结构体类型，会显示该结构体定义信息。

## 查看调用栈

通过 `where` 可以查看调用栈信息：

```bash
(gdb) where
#0  _rt0_amd64 ()
    at /usr/lib/go/src/runtime/asm_amd64.s:15
#1  0x0000000000000001 in ?? ()
#2  0x00007fffffffdd2c in ?? ()
#3  0x0000000000000000 in ?? ()
```

## 设置观察点

通过 `watch` 命令，可以设置观察点。当观察点的变量发生变化时，程序会停下来。可以简写成 `wa`

```bash
(gdb) watch sum
```

## 查看汇编代码

我们可以通过开启 `disassemble-next-line` 自动显示汇编代码。

```bash
(gdb) set disassemble-next-line on
```

当面我们可以查看指定函数的汇编代码：

```bash
(gdb) disassemble main.main
```

`disassemble` 可以简写成 `disas`。我们也可以将源代码和汇编代码一一映射起来后进行查看

```bash
(gdb) disas /m main.main
```

GDB默认显示汇编指令格式是 `AT&T` 格式，我们可以改成 `intel` 格式：

```bash
(gdb) set disassembly-flavor intel
```

## 自动显示变量值

`display` 命令支持自动显示变量值功能。当进行 `next` 或者 `step` 等调试操作时候，GDB会自动显示 `display` 所设置的变量或者地址的值信息。

`display` 命令格式：

```bash
display <expr>
display /<fmt> <expr>
display /<fmt> <addr>
```
- expr是一个表达式
- fmt表示显示的格式
- addr表示内存地址

其他相关命令：

- undisplay [num]: 不显示
- delete display [num]: 删除
- disable display [num]: 关闭自动显示
- enable display [num]： 开启自动显示
- info display: 查看display信息

**注意：** 当不带display号时候，是针对所有display进行设置。

## 显示将要执行的汇编指令

我们可以通过 `display` 命令可以实现当程序停止时，查看将要执行的汇编指令：

```bash
(gdb) display /i $pc
(gdb) display /3i $pc # 一次性显示3条指令
```
取消显示可以用 `undisplay` 命令进行操作。

## 查看backtrace信息

`backtrace` 命令用来查看栈帧信息。可以简写成 `bt`。

```bash
(gdb) backtrace # 显示当前函数的栈帧以及局部变量信息
(gdb) backtrace full # 显示各个函数的栈帧以及局部变量值
(gdb) backtrace full n # 从内向外显示n个栈桢，及其局部变量
(gdb) backtrace full -n # 从外向内显示n个栈桢，及其局部变量
```

## 切换栈帧信息

`frame` 命令可以切换栈帧信息：

```bash
(gdb) frame n # 其中n是层数，最内层的函数帧为第0帧
```

其他相关命令：

- info frame: 查看栈帧列表

## 调试多线程

GDB中有一组命令能够辅助多线程的调试：

- info threads

    显示当前可调式的所有线程，线程 ID 前有 “*” 表示当前被调试的线程。

- thread threadid

    切换线程到线程threadid

- set scheduler-locking [on|off|step]

    多线程环境下，会存在多个线程运行，这会影响调试某个线程的结果，这个命令可以设置调试的时候多个线程的运行情况，`on` 表示只有当前调试的线程会继续执行，`off` 表示不屏蔽任何线程，所有线程都可以执行，`step` 表示在单步执行时，只有当前线程会执行。

- thread apply [threadid] [all] args

    对线程列表执行命令。比如通过 `thread apply all bt full` 可以查看所有线程的局部变量信息。


## 查看运行时变量

`print` 命令可以用来查看变量的值。`print` 命令可以简写成 `p`。`print` 命令格式如下：

```bash
print [</format>] <expr>
```

`format` 用来设置显示变量的格式，是可选的选项。其可用值如下所示：

- x 按十六进制格式显示变量
- d 按十进制格式显示变量
- u 按十六进制格式显示无符号整型
- o 按八进制格式显示变量
- t 按二进制格式显示变量
- a 按十六进制格式显示变量
- c 按字符格式显示变量
- f 按浮点数格式显示变量
- z 按十六进制格式显示变量，左侧填充零

`expr` 可以是一个变量，也可以是表达式，也可以是寄存器：

```bash
(gdb) p var1 # 打印变量var1
(gdb) p &var1 # 打印变量var1地址
(gdb) p $rsp # 打印rsp寄存器地址
(gdb) p $rsp + 8 # 打印rsp加8后的地址信息
(gdb) p 0xc000068fd0 # 打印0xc000068fd0转换成10进制格式
(gdb) p /x 824634150864 # 打印824634150864转换成16进制格式
```

`print` 也支持查看连续内存，`@` 操作符用于查看连续内存，`@` 的左边是第一个内存的地址的值，`@` 的右边则想查看内存的长度。

例如对于如下代码：`int arr[] = {2, 4, 6, 8, 10};`，可以通过如下命令查看 `arr` 前三个单元的数据：

```bash
(gdb) p *arr@3
$2 = {2, 4, 6}
```

## 查看内存中的值

`examine` 命令用来查看内存地址中的值，可以简写成 `x`。`examine` 命令的语法如下所示：

```bash
examine /<n/f/u> <addr>
```

- n 表示显示字段的长度，也就是说从当前地址向后显示几个地址的内容。

- f 表示显示的格式
    - d 数字 decimal
    - u 无符号数字 unsigned decimal
    - s 字符串 string
    - c 字符 char
    - u 无符号整数 unsigned integer
    - t 二进制 binary
    - o 八进制格式 octal
    - x 十六进制格式 hex
    - f 浮点数格式 float
    - i 指令 instruction
    - a 地址 address
    - z 十六进制格式，左侧填充零 hex, zero padded on the left

- u 表示从当前地址往后请求的字节数，默认是4个bytes
    - b 一个字节 byte
    - h 两个字节 halfword
    - w 四个字节 word
    - g 八个字节 giantword

示例：

```bash
(gdb) x/10c 0x4005d4 # 打印前10个字符
(gdb) x/16xb a # 以16进制格式打印数组前a16个byte的值
(gdb) x/16ub a # 以无符号10进制格式打印数组a前16个byte的值
(gdb) x/16tb a # 以2进制格式打印数组前16个abyte的值
(gdb) x/16xw a # 以16进制格式打印数组a前16个word（4个byte）的值
(gdb) x $rsp # 打印rsp寄存器执行的地址的值
(gdb) x $rsp + 8 # 打印rsp加8后的地址指向的值
(gdb) x 0xc000068fd0 # 打印内存0xc000068fd0指向的值
(gdb) x/5i schedule # 打印函数schedule前5条指令
```

## 修改变量或寄存器值

`set` 命令支持修改变量以及寄存器的值：

```bash
(gdb) set var var1=123 # 设置变量var1值为123
(gdb) set var $rax=123 # 设置寄存器值为123
(gdb) set environment envname1=123 # 设置环境变量envname1值为123
```

## 查看命令帮助信息

`help` 命令支持查看GDB命令帮助信息。

```bash
(gdb) help status # 查看所有命令使用示例
(gdb) help x # 查看x命令使用帮助
```

## 搜索源文件

`search` 命令支持在当前文件中使用正则表达式搜索内容。`search` 等效于 `forward-search` 命令，是从当前位置向前搜索，可以简写成 `fo`。`reverse-search` 命令功能跟 `forward-search` 恰好相反，其可以简写成 `rev`。

```bash
(gdb) search func add # 从当前位置向前搜索add方法
(gdb) rev func add # 从当前为向后搜索add方法
```

## 执行shell命令

我们可以通过 `shell` 指令来执行shell命令。

```bash
(gdb) shell cat /proc/27889/maps # 查看进程27889的内存映射。若想查看当前进程id，可以使用info proc命令获取
(gdb) shell ls -alh
```

## GDB对go runtime支持

- runtime.Breakpoint()：触发调试器断点。
- runtime/debug.PrintStack()：显示调试堆栈。
- log：适合替代 print显示调试信息

## 为系统调用设置捕获点

gdb支持为系统调用设置捕获点(catchpoint)，我们可以通过 `catch` 指令，后面加上 **系统调用号(syscall numbers)**[^1] 或者**系统调用助记符(syscall mnemonic names，也称为系统调用名称)** 来设置捕获点。如果不指定系统调用的话，默认是捕获所有系统调用。

```shell
(gdb) catch syscall 231
Catchpoint 1 (syscall 'exit_group' [231])
(gdb) catch syscall exit_group
Catchpoint 2 (syscall 'exit_group' [231])
(gdb) catch syscall
Catchpoint 3 (any syscall)
```

## 设置源文件查找路径

在程序调试过程中，构建程序的源文件位置更改之后，gdb不能找到源文件位置，我们可以使用 `directory`命令设置查找源文件的路径。

```bash
directory ~/www/go/src/github.com/go-delve/
```

`directory` 命令只使用相对路径下的源文件，若绝对路径下源文件找不到，我们可以使用 `set substitute-path` 设置路径替换。

```bash
set substitute-path ~/www/go/src/github.com/go-delve/ ~/www/go/src/github.com/go-delve2/
```

## 批量执行命令

gdb支持以脚本形式运行命令，我们可以使用下面的选项：

- `-ex`选项可以用来指定执行命令
- `-iex`选来用来指定加载应用程序之前需执行的命令
- `-x` 选项用来从指定文件中加载命令
- `-batch`类似`-q`，支持安静模式，会指示GDB在所有命令执行完成之后，退出

```bash
# 1. 打印提示语 2. 在main.main出设置断点 3. 运行程序 4. 执行完成程序退出gdb
gdb -iex 'echo 开始执行:\n' -ex "b main.main" -ex "run" -batch ./main

# 设置exit/exit_group系统调用追踪点，然后运行程序，最后打印backtrace信息
gdb -ex "catch syscall exit exit_group" -ex "run" -ex "bt" -batch ./main

# 从文件中加载命令
gdb -batch -x /tmp/cmds --args executablename arg1 arg2 arg3
```

## GDB增强插件

- [gdbinit](https://github.com/gdbinit/gdbinit)
- [gdb-dashboard](https://github.com/cyrus-and/gdb-dashboard)
- [pwndbg](https://github.com/pwndbg/pwndbg)
- [peda](https://github.com/longld/peda)

## 进一步阅读

- [Beej's Quick Guide to GDB](http://beej.us/guide/bggdb/)
- [100个gdb小技巧](https://wizardforcel.gitbooks.io/100-gdb-tips/content/index.html)

[^1]:https://x64.syscall.sh/