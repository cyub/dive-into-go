---
title: "Go函数调用栈"
---

# 调用栈

这一章节延续前面《[准备篇-Go汇编](../go-assembly)》那一章节。这一章节将从一个实例出发详细分析Go 语言中函数调用栈。这一章节会涉及caller，callee，寄存器相关概念，如果还不太了解可以去《[准备篇-Go汇编](../go-assembly)》查看了解。


在详细分析函数栈之前，我们先复习以下几个概念。

## caller 与 callee

如果一个函数调用另外一个函数，那么该函数被称为调用者函数，也叫做caller，而被调用的函数称为被调用者函数，也叫做callee。比如函数main中调用sum函数，那么main就是caller，而sum函数就是callee。

## 栈帧

栈帧（stack frame）指的是未完成函数所持有的，独立连续的栈区域，用来保存其局部变量，返回地址等信息。

## 函数调用约定

函数调用约定(Calling Conventions)是[ABI](https://en.wikipedia.org/wiki/Application_binary_interface)(Application Binary Interface)的组成部分，它描述了：

- 如何将执行控制权交给callee，以及返还给caller
- 如何保存和恢复caller的状态
- 如何将参数传递个callee
- 如何从callee获取返回值


简而言之，一句话就是**函数调用约定**指的是约定了函数调用时候，函数参数如何传递，函数栈由谁完成平衡，以及函数返回值如何返回的。

在Go语言中，**函数的参数和返回值的存储空间是由其caller的栈帧提供**。这也为Go语言为啥支持多返回值以及总是值传递的原因。从Go汇编层面看，在callee中访问其参数和返回值，是通过FP寄存器来操作的（在实现层面是通过SP寄存器访问的）。**Go语言中函数参数入栈顺序是从右到左入栈的**。

函数调用时候，会为其分配栈空间用来存放临时变量，返回值等信息，当完成调用后，这些栈空间应该进行回收，以恢复调用以前的状态。这个过程就是**栈平衡**。栈平衡工作可以由被调用者本身(callee)完成，也可以由其调用者(caller)完成。**在Go语言中是由callee来完成栈平衡的**。

## 函数栈

当前函数作为caller，其本身拥有的栈帧以及其所有callee的栈帧，可以称为该函数的函数栈，也称函数调用栈。C语言中函数栈大小是固定的，如果超出栈空间，就会栈溢出异常。比如递归求斐波拉契，这时候可以使用尾调用来优化。由于Go 语言栈可以自动进行分裂扩容，栈空间不够时候，可以自动进行扩容。当用火焰图分析性能时候，火焰越高，说明栈越深。

Go 语言中函数栈全景图如下：

```eval_rst
.. image:: https://static.cyub.vip/images/202105/go-func-stack.png
    :alt: Go语言函数调用栈
    :width: 400px
    :align: center
```

接下来的函数调用栈分析，都是基于函数栈的全景图出发。知道该全景图每一部分含义也就了解函数调用栈。

## 实例分析

我们将分析如下代码。

```go
package main

func sum(a, b int) int {
	sum := 0
	sum = a + b
	return sum
}

func main() {
	a := 3
	b := 5
	print(sum(a, b))
}
```

参照前面的函数栈全景图，我们画出main函数调用sum函数时的函数调用栈图：

```eval_rst
.. image:: https://static.cyub.vip/images/202105/go-stack-sum.png
    :alt: main函数调用栈
    :width: 400px
    :align: center
```

从栈底往栈顶，我们依次可以看到：

- main函数的caller的基址（Base Pointer)。这部分是黄色区域。
- main函数局部变量a,b。我们看到a,b变量按照他们出现的顺序依次入栈，在实际指令中可能出现指令重排，a,b变量入栈顺序可能相反，但这个不影响最终结果。这部分是蓝色区域。
- 接下来是绿色区域，这部分是用来存放sum函数返回值的。这部分空间是提前分配好了。由于sum函数返回值只有一个，且是int类型，那么绿色区域大小是8字节（64位系统下int占用8字节）。在sum函数内部是通过FP寄存器访问这个栈空间的。
- 在下来就是浅黄色区域，这个是存放sum函数实参的。从上面介绍中我们知道Go语言中函数参数是从右到左入栈的，sum函数的签名是`func sum(a, b int) int`，那么b=5会先入栈，a=3接着入栈。
- 接下来是粉红色区域，这部分存放的是return address。main函数调用sum函数时候，会将sum函数后面的一条指令入栈。从main函数caller的基址空间到此处都属于main的函数栈帧。
- 接下来就是sum函数栈帧空间部分。首先同main函数栈帧空间一样，其存放的sum函数caller的基址，由于sum函数的caller就是main函数，所以这个地方存放就是main栈帧的栈底地址。
....

### 从汇编的角度观察

接下来我们从Go 汇编角度查看main函数调用sum函数时的函数调用栈。

Go语言中函数的栈帧空间是提前分配好的，分配的空间用来存放函数局部变量，被调用函数参数，被调用函数返回值，返回地址等信息。我们来看下main函数和sum函数的汇编定义：

```as
TEXT	"".main(SB), ABIInternal, $56-0 // main函数定义
TEXT	"".sum(SB), NOSPLIT|ABIInternal, $16-24 // sum函数定义
```

从上面函数定义可以看出来给main函数分配的栈帧空间大小是56字节大小（这里面的56字节大小，是不包括返回地址空间的，实际上main函数的栈帧大小是56+8(返回地址占用8字节空间大小) = 64字节大小），由于main函数没有参数和返回值，所以参数和返回值这部分大小是0。给sum函数分配的栈帧空间大小是16字节大小，sum函数参数有2个，且都是int类型，返回值是int类型，所以参数和返回值大小是24字节。

关于函数声明时每个字段的含义可以去《[准备篇-Go汇编-函数声明](../go-assembly.html#id18)》

需要注意的有两点：
1. 函数分配的栈空间足以放下所有被调用者信息，如果一个函数会调用很多其他函数，那么它的栈空间是按照其调用函数中最大空间要求来分配的。
2. 函数栈空间是可以split。当栈空间不足时候，会进行split，重新找一块2倍当前栈空间的内存空间，将当前栈帧信息拷贝过去，这个叫栈分裂。Go语言在栈分裂基础上实现了抢占式调度，这个我们会在后续篇章详细探讨。我们可以使用`//go:nosplit`这个编译指示，强制函数不进行栈分裂。从sum函数定义可以看出来，其没有进行栈分裂处理。

接下来我们分析main函数的汇编代码：

```bash
0x0000 00000 (main.go:9)	TEXT	"".main(SB), ABIInternal, $56-0 # main函数定义
0x0000 00000 (main.go:9)	MOVQ	(TLS), CX # 将本地线程存储信息保存到CX寄存器中
0x0009 00009 (main.go:9)	CMPQ	SP, 16(CX) # 比较当前栈顶地址(SP寄存器存放的)与本地线程存储的栈顶地址
0x000d 00013 (main.go:9)	PCDATA	$0, $-2 # PCDATA，FUNCDATA用于Go汇编额外信息，不必关注
0x000d 00013 (main.go:9)	JLS	114 # 如果当前栈顶地址(SP寄存器存放的)小于本地线程存储的栈顶地址，则跳到114处代码处进行栈分裂扩容操作
0x000f 00015 (main.go:9)	PCDATA	$0, $-1
0x000f 00015 (main.go:9)	SUBQ	$56, SP # 提前分配好56字节空间，作为main函数的栈帧，注意此时的SP寄存器指向，会往下移动了56个字节
0x0013 00019 (main.go:9)	MOVQ	BP, 48(SP) # BP寄存器存放的是main函数caller的基址，movq这条指令是将main函数caller的基址入栈。对应就是上图中我们看到的main函数栈帧的黄色区域。
0x0018 00024 (main.go:9)	LEAQ	48(SP), BP # 将main函数的基址存放到到BP寄存器
0x001d 00029 (main.go:9)	PCDATA	$0, $-2
0x001d 00029 (main.go:9)	PCDATA	$1, $-2
0x001d 00029 (main.go:9)	FUNCDATA	$0, gclocals·33cdeccccebe80329f1fdbee7f5874cb(SB)
0x001d 00029 (main.go:9)	FUNCDATA	$1, gclocals·33cdeccccebe80329f1fdbee7f5874cb(SB)
0x001d 00029 (main.go:9)	FUNCDATA	$2, gclocals·33cdeccccebe80329f1fdbee7f5874cb(SB)
0x001d 00029 (main.go:10)	PCDATA	$0, $0
0x001d 00029 (main.go:10)	PCDATA	$1, $0
0x001d 00029 (main.go:10)	MOVQ	$3, "".a+32(SP) # main函数局部变量a入栈
0x0026 00038 (main.go:11)	MOVQ	$5, "".b+24(SP) # main函数局部变量b入栈
0x002f 00047 (main.go:12)	MOVQ	"".a+32(SP), AX # 将局部变量a保存到AX寄存中
0x0034 00052 (main.go:12)	MOVQ	AX, (SP) # sum函数第二个参数
0x0038 00056 (main.go:12)	MOVQ	$5, 8(SP) # sum函数第一个参数
0x0041 00065 (main.go:12)	CALL	"".sum(SB) # 通过call指令调用sum函数。此时会隐式进行两个操作：1. 将当前指令的下一条指令的地址入栈。当前指令下一条指令就是MOVQ 16(SP), AX，其相对地址是0x0046。2. IP指令寄存器指向了sum函数指令入库地址。
0x0046 00070 (main.go:12)	MOVQ	16(SP), AX #将sum函数值保存AX寄存中。16(SP) 存放的是sum函数的返回值
0x004b 00075 (main.go:12)	MOVQ	AX, ""..autotmp_2+40(SP)
0x0050 00080 (main.go:12)	CALL	runtime.printlock(SB)
0x0055 00085 (main.go:12)	MOVQ	""..autotmp_2+40(SP), AX
0x005a 00090 (main.go:12)	MOVQ	AX, (SP)
0x005e 00094 (main.go:12)	CALL	runtime.printint(SB)
0x0063 00099 (main.go:12)	CALL	runtime.printunlock(SB)
0x0068 00104 (main.go:13)	MOVQ	48(SP), BP
0x006d 00109 (main.go:13)	ADDQ	$56, SP
0x0071 00113 (main.go:13)	RET
0x0072 00114 (main.go:13)	NOP
0x0072 00114 (main.go:9)	PCDATA	$1, $-1
0x0072 00114 (main.go:9)	PCDATA	$0, $-2
0x0072 00114 (main.go:9)	CALL	runtime.morestack_noctxt(SB) # 调用栈分裂处理函数
0x0077 00119 (main.go:9)	PCDATA	$0, $-1
0x0077 00119 (main.go:9)	JMP	0
```

结合汇编，我们最终画出main函数调用栈图：

```eval_rst
.. image:: https://static.cyub.vip/images/202105/go-stack-sum2.png
    :alt: main函数调用栈
    :width: 450px
    :align: center
```