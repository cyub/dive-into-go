---
title: "Go汇编语法"
---

# Go汇编

本节将介绍Go语言所使用到的汇编知识。在介绍Go汇编之前，我们先了解一些汇编语言，寄存器， AT&T 汇编语法，内存布局等前置知识点。这些知识点与Go汇编或多或少有关系，了解这些才能更好的帮助我们去看懂Go汇编代码。

## 前置知识

### 机器语言

机器语言是机器指令的集合。计算机的机器指令是一系列二进制数字。计算机将之转换为一系列高低电平脉冲信号来驱动硬件工作的。

### 汇编语言

机器指令是由0和1组成的二进制指令，难以编写与记忆。汇编语言是二进制指令的文本形式，与机器指令一一对应，相当于机器指令的助记码。比如，加法的机器指令是`00000011`写成汇编语言就是`ADD`。**汇编的指令格式由操作码和操作数组成**。

将助记码标准化后称为`assembly language`，缩写为`asm`，中文译为汇编语言。

汇编语言大致可以分为两类：

1. 基于x86架构处理器的汇编语言

    - Intel 汇编
        - DOS(8086处理器), Windows
        - Windows 派系 -> VC 编译器
    - AT&T 汇编
        - Linux, Unix, Mac OS, iOS(模拟器)
        - Unix派系 -> GCC编译器
2. 基于ARM 架构处理器的汇编语言

    - ARM 汇编

#### 数据单元大小

汇编中数据单元大小可分为：

- 位 bit
- 半字节 Nibble
- 字节 Byte
- 字 Word 相当于两个字节
- 双字 Double Word 相当于2个字，4个字节
- 四字 Quadword 相当于4个字，8个字节

### 寄存器

寄存器是CPU中存储数据的器件，起到数据缓存作用。内存按照内存层级(memory hierarchy)依次分为寄存器，L1 Cache, L2 Cache, L3 Cache，其读写延迟依次增加，实现成本依次降低。

{{< figure src="https://static.cyub.vip/images/202104/mem_arch.jpg" width="500px" class="text-center" title="内存层级结构">}}

#### 寄存器分类

一个CPU中有多个寄存器。每一个寄存器都有自己的名称。寄存器按照种类分为通用寄存器和控制寄存器。其中通用寄存器有可细分为数据寄存器，指针寄存器，以及变址寄存器。

![](https://static.cyub.vip/images/202007/register.jpg)

1979年因特尔推出8086架构的CPU，开始支持16位。为了兼容之前8008架构的8位CPU，8086架构中AX寄存器高8位称为AH，低8位称为AL，用来对应8008架构的8位的A寄存器。后来随着x86，以及x86-64
架构的CPU推出，开始支持32位以及64位，为了兼容并保留了旧名称，16位处理器的AX寄存器拓展成EAX(E代表拓展Extended的意思)。对于64位处理器的寄存器相应的RAX(R代表寄存器Register的意思)。其他指令也类似。

![](https://static.cyub.vip/images/202102/rax.jpg)

各个寄存器功能介绍：

寄存器 | 功能
---|---
**AX**| A代表累加器Accumulator，X是八位寄存器AH和AL的中H和L的占位符，表示AX由AH和AL组成。AX一般用于算术与逻辑运算，以及作为函数返回值
**BX** | B代表Base，BX一般用于保存中间地址(hold indirect addresses)
**CX** | C代表Count，CX一般用于计数，比如使用它来计算循环中的迭代次数或指定字符串中的字符数
**DX** | D代表Data，DX一般用于保存某些算术运算的溢出，并且在访问80x86 I/O总线上的数据时保存I/O地址
**DI** | DI代表Destination Index，DI一般用于指针
**SI** | SI代表Source Index，SI用途同DI一样
**SP** | SP代表Stack Pointer，是栈指针寄存器，存放着执行函数对应栈帧的栈顶地址，且始终指向栈顶
**BP** | BP代表Base Pointer，是栈帧基址指针寄存器，存放这执行函数对应栈帧的栈底地址，一般用于访问栈中的局部变量和参数
**IP** | IP代表Instruction Pointer，是指令寄存器，指向处理器下条等待执行的指令地址(代码段内的偏移量)，每次执行完相应汇编指令IP值就会增加；IP是个特殊寄存器，不能像访问通用寄存器那样访问它。IP可被jmp、call和ret等指令隐含地改变


### 进程在虚拟内存中布局

32位系统下，虚拟内存空间大小为4G，每一个进程独立的运行在该虚拟内存空间上。从0x00000000开始的3G空间属于用户空间，剩下1G空间属于内核空间。

用户空间还可以进一步细分，每一部分叫做段(section)，大致可以分为以下几段：
- Stack 栈空间：用于函数调用中存储局部变量、返回地址、返回值等，向下增长，变量存储和使用过程叫做入栈和出栈过程
- Heap 堆空间：用于动态申请的内存，比如c语言通过malloc函数调用分配内存，其向上增长。指针型变量指向的一般就是这里面的空间。存储此空间的数据需要GC的。栈上变量scope是函数级的，而堆上变量属于进程级的
- Bss段：未初始化数据区，存储未初始化的全局变量或静态变量
- Data段：初始化数据区，存储已经初始化的全局变量或静态变量
- Text段：代码区，存储的是源码编译后二进制指令

![内存布局](https://static.cyub.vip/images/202102/process_mem_layout.jpeg)

在32位系统中进程空间(即用户空间）范围为`0x00000000 ~ 0xbfffffff`，内核空间范围为`0xc0000000 ~ 0xffffffff`, 实际上分配的进程空间并不是从0x00000000开始的，而是从0x08048000开始，到0xbfffffff结束。另外进程实际的esp指向的地址并不是从0xbfffffff开始的，因为linux系统会在程序初始化前，将一些命令行参数及环境变量以及ELF辅助向量（`ELF Auxiliary Vectors`)等信息放到栈上。进程启动时，其空间布局如下所示（注意图示中地址是从低地址到高地址的）：

```
stack pointer ->    [ argc = number of args ]     4
                    [ argv[0] (pointer) ]         4   (program name)
                    [ argv[1] (pointer) ]         4
                    [ argv[..] (pointer) ]        4 * x
                    [ argv[n - 1] (pointer) ]     4
                    [ argv[n] (pointer) ]         4   (= NULL)

                    [ envp[0] (pointer) ]         4
                    [ envp[1] (pointer) ]         4
                    [ envp[..] (pointer) ]        4
                    [ envp[term] (pointer) ]      4   (= NULL)

                    [ auxv[0] (Elf32_auxv_t) ]    8
                    [ auxv[1] (Elf32_auxv_t) ]    8
                    [ auxv[..] (Elf32_auxv_t) ]   8
                    [ auxv[term] (Elf32_auxv_t) ] 8   (= AT_NULL vector)

                    [ padding ]                   0 - 16

                    [ argument ASCIIZ strings ]   >= 0
                    [ environment ASCIIZ strings ]   >= 0
                    [ program name ASCIIZ strings ]   >= 0

  (0xbffffffc)      [ end marker ]                4   (= NULL)

  (0xc0000000)      < bottom of stack >           0   (virtual)
```

进程空间起始位置处存放命令行参数个数与参数信息，我们将在后面章节有讨论到。

### caller 与 callee

如果一个函数调用另外一个函数，那么该函数被称为调用者函数，也叫做caller，而被调用的函数称为被调用者函数，也叫做callee。比如函数main中调用sum函数，那么main就是caller，而sum函数就是callee。

### 栈帧

栈帧即stack frame，即未完成函数所持有的，独立连续的栈区域，用来保存其局部变量，返回地址等信息。

### 函数栈

当前函数作为caller，其本身拥有的栈帧以及其所有callee的栈帧，可以称为该函数的函数栈。一般情况下函数栈大小是固定的，如果超出栈空间，就会栈溢出异常。比如递归求斐波拉契，这时候可以使用尾调用来优化。用火焰图分析性能时候，火焰越高，说明栈越深。


### AT&T 汇编语法

AT＆T汇编语法是类Unix的系统上的标准汇编语法，比如gcc、gdb中默认都是使用AT&T汇编语法。AT&T汇编的指令格式如下：

```bash
instruction src dst
```
其中`instruction`是指令助记符，也叫操作码，比如`mov`就是一个指令助记符，`src`是源操作数，`dst`是目的操作。

当引用寄存器时候，应在寄存器名称加前缀`%`，对于常数，则应加前缀 **$**。

#### 指令分类

##### 数据传输指令

汇编指令 | 逻辑表达式 | 含义
--- | ---|---
mov $0x05, %ax | R[ax] = 0x05 | 将数值5存储到寄存器ax中
mov %ax, -4(%bp)  | mem[R[bp] -4] = R[ax] | 将ax寄存器中存储的数据存储到<br/>**bp寄存器存的地址减去4之后的内存地址**中，
mov -4(%bp), %ax | R[ax] = mem[R[bp] -4] | bp寄存器存储的地址减去4值，<br/>然后改地址对应的内存存储的信息存储到ax寄存器中
mov $0x10, (%sp) | mem[R[sp]] = 0x10 | 将16存储到sp寄存器存储的地址对应的内存
push $0x03 | mem[R[sp]] = 0x03<br/> R[sp] = R[sp] - 4 | 将数值03入栈，然后sp寄存器存储的地址减去4
pop | R[sp] = R[sp] + 4 | 将当前sp寄存器指向的地址的变量出栈，<br/>并将sp寄存器存储的地址加4
call func1 | --- | 调用函数func1
ret | --- | 函数返回，将返回值存储到寄存器中或caller栈中，<br/>并将return address弹出到ip寄存器中

当使用`mov`指令传递数据时，数据的大小由mov指令的后缀决定。

```as
movb $123, %eax // 1 byte
movw $123, %eax // 2 byte
movl $123, %eax // 4 byte
movq $123, %eax // 8 byte
```

##### 算术运算指令

指令 | 含义
--- | ---
subl $0x05, %eax | R[eax] = R[eax] - 0x05
subl %eax, -4(%ebp) | mem[R[ebp] -4] = mem[R[ebp] -4] - R[eax]
subl -4(%ebp), %eax | R[eax] = R[eax] - mem[R[ebp] -4]

##### 跳转指令

指令 | 含义
--- | --- 
cmpl %eax %ebx | 计算 R[eax] - R[ebx], 然后设置flags寄存器
jmp location| 无条件跳转到location
je location | 如果flags寄存器设置了相等标志，则跳转到location
jg, jge, jl, gle, jnz, ... location | 如果flags寄存器设置了>, >=, <, <=, != 0等标志，则跳转到location

##### 栈与地址管理指令

指令 | 含义 | 等同操作
--- | --- | ---
pushl %eax | 将R[eax]入栈 | subl $4, %esp; <br/>movl %eax, (%esp)
popl %eax | 将栈顶数据弹出，然后存储到R[eax] | movl (%esp), %eax <br/> addl $4, %esp
leave | Restore the callers stack pointer | movl %ebp, %esp <br/>pop %ebp
lea	8(%esp), %esi | 将R[esp]存放的地址加8，然后存储到R[esi] | R[esi] = R[esp] + 8

**lea** 是`load effective address`的缩写，用于将一个内存地址直接赋给目的操作数。

##### 函数调用指令

指令 | 含义
--- | ---
call label | 调用函数，并将返回地址入栈
ret | 从栈中弹出返回地址，并跳转至该返回地址
leave | 恢复调用者者栈指针

{{< hint info >}}
**注意：**

以上指令分类并不规范和完整，比如 `call` , `ret` 都可以算作无条件跳转指令，这里面是按照功能放在函数调用这一分类了。
{{< /hint >}}

## Go 汇编

Go语言汇编器采用Plan9 汇编语法，该汇编语言是由贝尔实验推出来的。下面说的Go汇编也就是Plan9 汇编。
不同于C语言汇编中汇编指令的寄存器都是代表硬件寄存器，Go汇编中的寄存器使用的是伪寄存器，可以把Go汇编考虑成是底层硬件汇编之上的抽象。

### 伪寄存器

Go汇编一共有4个伪寄存器：

- **FP**: Frame pointer: arguments and locals.

  - 使用形如 symbol+offset(FP) 的方式，引用函数的输入参数。例如 arg0+0(FP)，arg1+8(FP)
  - offset是正值

- **PC**: Program counter: jumps and branches.

  - PC寄存器，在 x86 平台下对应 ip 寄存器，amd64 上则是 rip

- **SB**: Static base pointer: global symbols.

  - 全局静态基指针，一般用来声明函数或全局变量

- **SP**: Stack pointer: top of stack.

  - SP寄存器指向当前栈帧的局部变量的开始位置，使用形如 symbol+offset(SP) 的方式，引用函数的局部变量。
  - offset是负值，offset 的合法取值是 [-framesize, 0)。
  - 手写汇编代码时，如果是 symbol+offset(SP) 形式，则表示伪寄存器 SP。如果是 offset(SP) 则表示硬件寄存器 SP。**对于编译输出(go tool compile -S / go tool objdump)的代码来讲，所有的 SP 都是硬件寄存器 SP，无论是否带 symbol**。

### 函数声明

```bash
                              参数大小+返回值大小
                                  | 
 TEXT pkgname·add(SB),NOSPLIT,$32-16
       |        |               |
      包名     函数名         栈帧大小
```

- `TEXT`指令声明了`pagname.add`是在`.text`段
- `pkgname·add`中的`·`，是一个 `unicode` 的中点。在程序被链接之后，所有的中点`·`都会被替换为点号`.`，所以通过 **[GDB]({{< relref "analysis-tools/gdb" >}})** 调试打断点时候，应该是 `b pagname.add`
- `(SB)`: `SB` 是一个虚拟寄存器，保存了静态基地址(static-base) 指针，即我们程序地址空间的开始地址。 `"".add(SB)` 表明我们的符号add位于某个固定的相对地址空间起始处的偏移位置
    ```shell
    objdump -j .text -t test | grep 'main.add' # 可获得main.add的绝对地址
   ```

- `NOSPLIT`: 表明该函数内部不进行栈分裂逻辑处理，可以避免CPU资源浪费。关于栈分裂会在调度器章节介绍
- `$32-16`: `$32`代表即将分配的栈帧大小；而`$16`指定了传入的参数与返回值的大小

#### 函数调用栈

Go汇编中函数调用的参数以及返回值都是由栈传递和保存的，这部分空间由`caller`在其栈帧(stack frame)上提供。Go汇编中没有使用PUSH/POP指令进行栈的伸缩处理，所有栈的增长和收缩是通过在栈指针寄存器`SP`上分别执行加减指令来实现的。

```bash
                                                                                             
                                       caller                                                
                                 +------------------+                                        
                                 |                  |                                        
       +---------------------->  |------------------|                                        
       |                         | caller parent BP |                                        
       |                         |------------------|  <--------- BP(pseudo SP)              
       |                         |   local Var0     |                                        
       |                         |------------------|                                        
       |                         |   .........      |                                        
       |                         |------------------|                                        
       |                         |   local VarN     |                                        
       |                         |------------------|                                        
       |                         |   temporarily    |                                        
                                 |   unused space   |                                        
caller stack frame               |------------------|                                        
                                 |   callee retN    |                                        
       |                         |------------------|                                        
       |                         |   .........      |                                        
       |                         |------------------|                                        
       |                         |   callee ret0    |                                        
       |                         |------------------|                                        
       |                         |   callee argN    |                                        
       |                         |------------------|                                        
       |                         |   .........      |                                        
       |                         |------------------|                                        
       |                         |   callee arg0    |                                        
       |                         |------------------|  <--------- FP(virtual register)       
       |                         |   return addr    |                                        
       +---------------------->  |------------------|  <----------------------+              
                                 |   caller BP      |                         |              
          BP(pseudo SP) ------>  |------------------|                         |              
                                 |   local Var0     |                         |              
                                 |------------------|                         |              
                                 |   local Var1     |                                        
                                 |------------------|                   callee stack frame   
                                 |   .........      |                                        
                                 |------------------|                         |              
                                 |   local VarN     |                         |              
      SP(Real Register) ------>  |------------------|                         |              
                                 |                  |                         |              
                                 |                  |                         |              
                                 +------------------+  <----------------------+              
                                                                                             
                                      callee                                                 
```

关于Go汇编进一步知识，我们将在 《**[基础篇-函数-函数调用栈]({{< relref "function/call-stack/" >}})** 》 章节详细探讨说明，此处我们只需要大致了解下函数声明、调用栈概念即可。

### 获取Go汇编代码

go代码示例：

```go
package main

import "fmt"

//go:noinline
func add(a, b int)  int {
    return a + b
}

func main() {
    c := add(3, 5)
    fmt.Println(c)
}
```

#### go tool compile

```bash
go tool compile -N -l -S main.go
GOOS=linux GOARCH=amd64 go tool compile -N -l -S main.go # 指定系统和架构
```

- -N选项指示禁止优化
- -l选项指示禁止内联
- -S选项指示打印出汇编代码

若要禁止指定函数内联优化，也可以在函数定义处加上`noinline`编译指示：

```go
//go:noinline
func add(a, b int)  int {
    return a + b
}
```

#### go tool objdump

方法1： 根据目标文件反编译出汇编代码

```bash
go tool compile -N -l main.go # 生成main.o
go tool objdump main.o
go tool objdump -s "main.(main|add)" ./test # objdump支持搜索特定字符串
```

方法2： 根据可执行文件反编译出汇编代码

```bash
go build -gcflags="-N -l" main.go -o test
go tool objdump main.o
```

#### go build -gcflags -S

```bash
go build -gcflags="-N -l -S"  main.go
```

#### 其他方法

- [objdump命令](https://en.wikipedia.org/wiki/Objdump)
- [go编译器：gccgo](https://github.com/golang/gofrontend)
- [在线转换汇编代码：godbolt](https://go.godbolt.org/)

## 进一步阅读

- [Go官方：A Quick Guide to Go's Assembler](https://golang.org/doc/asm)
- [plan9 assembly 完全解析](https://github.com/cch123/golang-notes/blob/master/assembly.md)
- [x86 Assembly book](https://en.wikibooks.org/wiki/X86_Assembly#Table_of_Contents)
- [What is an ABI?](https://www.section.io/engineering-education/what-is-an-abi/)