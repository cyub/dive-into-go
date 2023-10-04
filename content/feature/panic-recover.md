---
title: "panic与recover机制"
---

# 恐慌与恢复 - panic/recover

我们知道Go语言中许多错误会在编译时暴露出来，直接编译不通过，但对于空指针访问元素，切片/数组越界访问之类的运行时错误，只会在运行时引发 `panic` 异常暴露出来。这种由Go语言自动的触发的 `panic` 异常属于**运行时panic(Run-time panics)**[^1]。当发生 `panic` 时候，Go会运行所有已经注册的延迟函数，若延迟函数中未进行panic异常捕获处理，那么最终Go进程会终止，并打印堆栈信息。此外Go中还内置了 `panic` 函数，可以用于用户手动触发`panic`。

Go语言中内置的 `recover` 函数可以用来捕获 `panic`异常，但 `recover` 函数只能放在延迟函数调用中，才能起作用。我们从之前的章节《**[基础篇-语言特性-defer函数]({{< relref "feature/defer" >}})** 》了解到，多个延迟函数，会组成一个链表。Go在发生panic过程中，会依次遍历该链表，并检查链表中的延迟函数是否调用了 `recover` 函数调用，若调用了则 `panic` 异常会被捕获而不会继续向上抛出，否则会继续向上抛出异常和执行延迟函数，直到该 `panic` 没有被捕获，进程异常终止，这个过程叫做**panicking**。我们需要知道的是**即使panic被延迟函数链表中某个延迟函数捕获处理了，但其他的延迟函数还是会继续执行的，只是panic异常不在继续抛出**。

接下来我们来将深入了解下panic和recover底层的实现机制。在开始之前，我们来看下下面的测试题。

## 测试题：下面哪些panic异常将会捕获？

**case 1:**
```go
func main() {
    recover()
    panic("it is panic") // not recover
}
```

**case 2:**
```go
func main() {
    defer func() {
        recover()
    }()

    panic("it is panic") // recover
}
```

**case 3:**
```go
func main() {
	defer recover()
	panic("it is panic") // not recover
}
```

**case 4:**
```go
func main() {
    defer func() {
        defer recover()
    }()

    panic("it is panic") // recover
}
```

**case 5:**
```go
func main() {
	defer func() {
		defer func() {
			recover()
		}()
	}()

	panic("it is panic") // not recover
}
```

**case 6:**
```go
func main() {
	defer doRecover()
	panic("it is panic") // recover
}

func doRecover() {
	recover()
	fmt.Println("hello")
}
```

**case 7:**
```go
func main() {
	defer doRecover()
	panic("it is panic") // recover
}

func doRecover() {
	defer recover()
}
```

简单说明下上面几个案例运行结果：

- `case 1`中recover函数调用不是在defer延迟函数里面，肯定不会捕获panic异常。
- `case 2`中是panic异常捕获的标准操作，是可以捕获panic异常的，`case 6`跟`case 2`是一样的，只不过一个是匿名延迟函数，一个是具名延迟函数，同样可以捕获panic异常。
- `case 3`中recover函数作为延迟函数，没有在其他延迟函数中调用，它也是不起作用的。
- `case 4`中recover函数被一个延迟函数调用，且recover函数本身作为一个延迟函数，这个情况下也是可以正常捕获panic异常的，`case 7`跟`case 4`是一样的，只不过一个是匿名延迟函数，一个是具名延迟函数，同样可以捕获panic异常。
- `case 5`中尽管recover函数被延迟函数调用，但它却无法捕获panic异常。

从上面案例中可以看出来，使用recover函数进行panic异常捕获，也要使用正确才能起作用。下面会分析源码，探讨panic-recover实现机制，也能更好帮助你理解为什么`case 2`,`case 4`可以起作用，而`case 3`和`case 5`为啥没有起作用。

## 源码分析

我们先分析`case 2`案例，我们可以通过`go tool compile -N -l -S case2.go`获取[汇编代码](https://go.godbolt.org/z/713T1TvoG)，来查看panic和recover在底层真正的实现：

{{< highlight shell "linenos=table,hl_lines=23 44" >}}
main_pc0:
	TEXT    "".main(SB), ABIInternal, $104-0
	MOVQ    (TLS), CX
	CMPQ    SP, 16(CX)
	JLS     main_pc113
	SUBQ    $104, SP
	MOVQ    BP, 96(SP)
	LEAQ    96(SP), BP
	MOVL    $0, ""..autotmp_1+16(SP)
	LEAQ    "".main.func1·f(SB), AX
	MOVQ    AX, ""..autotmp_1+40(SP)
	LEAQ    ""..autotmp_1+16(SP), AX
	MOVQ    AX, (SP)
	CALL    runtime.deferprocStack(SB)
	TESTL   AX, AX
	JNE     main_pc97
	JMP     main_pc69
main_pc69:
	LEAQ    type.string(SB), AX
	MOVQ    AX, (SP)
	LEAQ    ""..stmp_0(SB), AX
	MOVQ    AX, 8(SP)
	CALL    runtime.gopanic(SB)
main_pc97:
	XCHGL   AX, AX
	CALL    runtime.deferreturn(SB)
	MOVQ    96(SP), BP
	ADDQ    $104, SP
	RET
main_pc113:
	NOP
	CALL    runtime.morestack_noctxt(SB)
	JMP     main_pc0
main_func1_pc0:
	TEXT    "".main.func1(SB), ABIInternal, $32-0
	MOVQ    (TLS), CX
	CMPQ    SP, 16(CX)
	JLS     main_func1_pc53
	SUBQ    $32, SP
	MOVQ    BP, 24(SP)
	LEAQ    24(SP), BP
	LEAQ    ""..fp+40(SP), AX
	MOVQ    AX, (SP)
	CALL    runtime.gorecover(SB)
	MOVQ    24(SP), BP
	ADDQ    $32, SP
	RET
main_func1_pc53:
	NOP
	CALL    runtime.morestack_noctxt(SB)
	JMP     main_func1_pc0
{{< / highlight >}}


从上面汇编代码中，可以看出 `panic` 函数底层实现 `runtime.gopanic`，`recover` 函数底层实现是 `runtime.gorecover`。

panic函数底层实现的 `runtime.gopanic` 源码如下：

```go
func gopanic(e interface{}) {
	gp := getg()
	
	... // 一些判断当前g是否允许在用户栈，是否正在内存分配的代码，略
	
	var p _panic // panic底层数据结构是_panic
	p.arg = e // e是panic函数的参数，对应case2中的: it is panic
	p.link = gp._panic
	gp._panic = (*_panic)(noescape(unsafe.Pointer(&p))) // 将当前panic挂到g上面

	atomic.Xadd(&runningPanicDefers, 1) // 记录正在执行panic的goroutine数量，防止main groutine返回时候，
	// 其他goroutine的panic栈信息未打印出来。@see https://github.com/golang/go/blob/go1.14.13/src/runtime/proc.go#L208-L220

	
	// 对于open-coded defer实现的延迟函数，需要扫描FUNCDATA_OpenCodedDeferInfo信息，
	// 获取延迟函数的sp/pc信息，并创建_defer结构，将其插入gp._defer链表中
	// 这是也是在defer函数章节中，提到的为啥open-coded defer提升了延迟函数的性能，而panic性能却降低的原因
	addOneOpenDeferFrame(gp, getcallerpc(), unsafe.Pointer(getcallersp()))

	for { // 开始遍历defer链表
		d := gp._defer
		if d == nil {
			break
		}

	
		// 当延迟函数里面再次抛出panic或者调用runtime.Goexit时候，
		// 会再次进入同一个延迟函数，此时d.started已经设置为true状态
		if d.started {
			if d._panic != nil { // 标记上一个_panic状态为aborted
				d._panic.aborted = true
			}
			d._panic = nil
			if !d.openDefer {
				// 对于非open-coded defer函数，我们需要将_defer从gp._defer链表中溢出去，防止继续重复执行
				d.fn = nil
				gp._defer = d.link
				freedefer(d)
				continue
			}
		}

	
		// 标记当前defer开始执行，这样当g栈增长时候或者垃圾回收时候，可以更新defer的参数栈帧
		d.started = true

		// 记录当前的_panic信息到_defer结构中，这样当该defer函数再次发生panic时候，可以标记d._panic为aborted状态
		d._panic = (*_panic)(noescape(unsafe.Pointer(&p)))

		done := true
		if d.openDefer { // 如果该延迟函数是open-coded defer函数
			done = runOpenDeferFrame(gp, d) // 运行open-coded defer函数，如果当前栈下面没有其他延迟函数，则返回true
			if done && !d._panic.recovered { // 如果当前栈下面没有其他open-coded defer函数了，且panic也未recover，
			// 那么继续当前的open-coded defer函数的sp作为基址，继续扫描funcdata，获取open-coded defer函数。
			// 之所以这么做是因为open-coded defer里面也存在defer函数的情况，例如case4
				addOneOpenDeferFrame(gp, 0, nil)
			}
		} else {// 非open-coded defer实现的defer函数

			// getargp返回其caller的保存callee参数的地址。
			// 之前介绍过了Go语言中函数调用约定，callee的参数存储，是由caller的栈空间提供。
			p.argp = unsafe.Pointer(getargp(0)) // 这里面p.argp保存的gopanic函数作为caller时候，保存callee参数的地址。
			// 之所以要_panic.argp保存gopanic的callee参数地址，
			// 这是因为调用gorecover会通过此检查其caller的caller是不是gopanic。
			// 这也是case5等不能捕获panic异常的原因。

			// 调用defer函数
			reflectcall(nil, unsafe.Pointer(d.fn), deferArgs(d), uint32(d.siz), uint32(d.siz))
		}
		p.argp = nil

		// reflectcall did not panic. Remove d.
		if gp._defer != d {
			throw("bad defer entry in panic")
		}
		d._panic = nil

		pc := d.pc
		sp := unsafe.Pointer(d.sp)
		if done { // 从gp._defer链表清除掉当前defer函数
			d.fn = nil
			gp._defer = d.link
			freedefer(d)
		}
		if p.recovered {
			gp._panic = p.link
			if gp._panic != nil && gp._panic.goexit && gp._panic.aborted {
				// A normal recover would bypass/abort the Goexit.  Instead,
				// we return to the processing loop of the Goexit.
				gp.sigcode0 = uintptr(gp._panic.sp)
				gp.sigcode1 = uintptr(gp._panic.pc)
				mcall(recovery)
				throw("bypassed recovery failed") // mcall should not return
			}
			atomic.Xadd(&runningPanicDefers, -1)

			if done { // panic已经被recover处理掉了，那么移除掉上面通过addOneOpenDeferFrame添加到gp._defer中的open-coded defer函数。
			// 因为这些open-coded defer是通过inline方式执行的，从gp._defer链表中移除掉，不影响它们继续的执行
				d := gp._defer
				var prev *_defer
				for d != nil {
					if d.openDefer {
						if d.started {
							break
						}
						if prev == nil {
							gp._defer = d.link
						} else {
							prev.link = d.link
						}
						newd := d.link
						freedefer(d)
						d = newd
					} else {
						prev = d
						d = d.link
					}
				}
			}

			gp._panic = p.link // 无用代码，上面已经操作过了
			// Aborted panics are marked but remain on the g.panic list.
			// Remove them from the list.
			for gp._panic != nil && gp._panic.aborted {
				gp._panic = gp._panic.link
			}
			if gp._panic == nil { // must be done with signal
				gp.sig = 0
			}
			// Pass information about recovering frame to recovery.
			gp.sigcode0 = uintptr(sp)
			gp.sigcode1 = pc
			mcall(recovery)
			throw("recovery failed") // mcall should not return
		}
	}

	preprintpanics(gp._panic)

	fatalpanic(gp._panic) // should not return
	*(*int)(nil) = 0      // not reached
}
```

对于基于open-coded defer方式实现的延迟函数中处理panic recover逻辑，比如addOneOpenDeferFrame，runOpenDeferFrame等函数，这里不再深究。这里主要分析通过链表实现的延迟函数中处理panic recover逻辑。


接下来我们看下recover函数底层实现`runtime.gorecover`源码

```go
func gorecover(argp uintptr) interface{} {
	gp := getg()
	p := gp._panic
	if p != nil && !p.goexit && !p.recovered && argp == uintptr(p.argp) {
		p.recovered = true
		return p.arg
	}
	return nil
}
```

[^1]:[Go官方语法指南：运行时恐慌](https://go.dev/ref/spec#Run_time_panics)