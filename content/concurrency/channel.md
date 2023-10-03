---
title: "通道 - channel"
---

# 通道 - channel

Golang中Channel是goroutine间重要通信的方式，是并发安全的，通道内的数据First In First Out，我们可以把通道想象成队列。

## channel数据结构

Channel底层数据结构是一个结构体。

```go
type hchan struct {
	qcount   uint // 队列中元素个数
	dataqsiz uint // 循环队列的大小
	buf      unsafe.Pointer // 指向循环队列
	elemsize uint16 // 通道里面的元素大小
	closed   uint32 // 通道关闭的标志
	elemtype *_type // 通道元素的类型
	sendx    uint   // 待发送的索引，即循环队列中的队尾指针rear
	recvx    uint   // 待读取的索引，即循环队列中的队头指针front
	recvq    waitq  // 接收等待队列
	sendq    waitq  // 发送等待队列
	lock mutex // 互斥锁
}
```

<!--more-->

hchan结构体中的buf指向一个数组，用来实现循环队列，sendx是循环队列的队尾指针，recvx是循环队列的队头指针。dataqsize是缓存型通道的大小，qcount记录着通道内数据个数。

循环队列一般使用空余单元法来解决队空和队满时候都存在font=rear带来的二义性问题，但这样会浪费一个单元。golang的channel中是通过增加qcount字段记录队列长度来解决二义性，一方面不会浪费一个存储单元，另一方面当使用len函数查看通道长度时候，可以直接返回qcount字段，一举两得。

hchan结构体中另一重要部分是recvq,sendq，分别存储了等待从通道中接收数据的goroutine，和等待发送数据到通道的goroutine。两者都是waitq类型。

waitq是一个结构体类型，waitq和sudog构成双向链表，其中sudog是链表元素的类型，waitq中first和last字段分别指向链表头部的sudog，链表尾部的sudog。

```go
type waitq struct {
	first *sudog
	last  *sudog
}

type sudog struct {
	...
	g *g // 当前阻塞的G
	...
	next     *sudog
	prev     *sudog
	elem     unsafe.Pointer
	...
}
```

hchan结构图如下：

![](https://static.cyub.vip/images/202011/channel_struct.jpg)

## channel的创建

在分析channel的创建代码之前，我们看下源码文件中最开始定义的两个常量；

```go
const (
	maxAlign  = 8
	hchanSize = unsafe.Sizeof(hchan{}) + uintptr(-int(unsafe.Sizeof(hchan{}))&(maxAlign-1))
	...
)
```

- maxAlgin用来设置内存最大对齐值，对应就是64位系统下cache line的大小。当结构体是8字节对齐时候，能够避免false share，提高读写速度
- hchanSize用来设置chan大小，unsafe.Sizeof(hchan{}) + uintptr(-int(unsafe.Sizeof(hchan{}))&(maxAlign-1))，这个复杂公式用来计算离unsafe.Sizeof(hchan{})最近的8的倍数。假设hchan{}大小是13，hchanSize是16。

假设n代表unsafe.Sizeof(hchan{})，a代表maxAlign，c代表hchanSize，则上面hchanSize的计算公式可以抽象为：

> c = n + ((-n) & (a - 1))

计算离8最近的倍数，只需将n补足与到8倍数的差值就可，c也可以用下面公式计算

> c = n + (a - n%a)

感兴趣的可以证明在a为2的n的次幂时候，上面两个公式是相等的。


```go
func makechan(t *chantype, size int) *hchan {
	elem := t.elem
	// 通道元素的大小不能超过64K
	if elem.size >= 1<<16 {
		throw("makechan: invalid channel element type")
	}

	// hchanSize大小不是maxAlign倍数，或者通道数据元素的对齐保证大于maxAlign
	if hchanSize%maxAlign != 0 || elem.align > maxAlign {
		throw("makechan: bad alignment")
	}
	// 判断通道数据是否超过内存限制
	mem, overflow := math.MulUintptr(elem.size, uintptr(size))
	if overflow || mem > maxAlloc-hchanSize || size < 0 {
		panic(plainError("makechan: size out of range"))
	}

	var c *hchan
	switch {
	case mem == 0: // 无缓冲通道
		c = (*hchan)(mallocgc(hchanSize, nil, true))
		c.buf = c.raceaddr()
	case elem.ptrdata == 0: 
		// 当通道数据元素不含指针，hchan和buf内存空间调用mallocgc一次性分配完成
		c = (*hchan)(mallocgc(hchanSize+mem, nil, true))
		// hchan和buf内存上布局是紧挨着的
		c.buf = add(unsafe.Pointer(c), hchanSize)
	default:
		// 当通道数据元素含指针时候，先创建hchan，然后给buf分配内存空间
		c = new(hchan)
		c.buf = mallocgc(mem, elem, true)
	}

	c.elemsize = uint16(elem.size)
	c.elemtype = elem
	c.dataqsiz = uint(size)
	...
	return c
}
```

## 发送数据到channel

```go
func chansend(c *hchan, ep unsafe.Pointer, block bool, callerpc uintptr) bool {
	// 当通道为nil时候
	if c == nil {
		// 非阻塞模式下，直接返回false
		if !block {
			return false
		}
		// 调用gopark将当前Goroutine休眠，调用gopark时候，将传入unlockf设置为nil，当前Goroutine会一直休眠
		gopark(nil, nil, waitReasonChanSendNilChan, traceEvGoStop, 2)
		throw("unreachable")
	}

	// 调试，不必关注
	if debugChan {
		print("chansend: chan=", c, "\n")
	}
	// 竞态检测，不必关注
	if raceenabled {
		racereadpc(c.raceaddr(), callerpc, funcPC(chansend))
	}

	// 非阻塞模式下，不使用锁快速检查send操作
	if !block && c.closed == 0 && ((c.dataqsiz == 0 && c.recvq.first == nil) ||
		(c.dataqsiz > 0 && c.qcount == c.dataqsiz)) {
		return false
	}

	var t0 int64
	if blockprofilerate > 0 {
		t0 = cputicks()
	}
	// 加锁
	lock(&c.lock)

	// 如果通道已关闭，再发送数据，发生恐慌
	if c.closed != 0 {
		unlock(&c.lock)
		panic(plainError("send on closed channel"))
	}
	
	// 从接收者队列recvq中取出一个接收者，接收者不为空情况下，直接将数据传递给该接收者
	if sg := c.recvq.dequeue(); sg != nil {
		send(c, sg, ep, func() { unlock(&c.lock) }, 3)
		return true
	}

	// 缓冲队列中的元素个数小于队列的大小
	// 说明缓冲队列还有空间
	if c.qcount < c.dataqsiz {
		qp := chanbuf(c, c.sendx) // qp指向循环数组中未使用的位置
		if raceenabled {
			raceacquire(qp)
			racerelease(qp)
		}
		// 将发送的数据写入到qp指向的循环数组中的位置
		typedmemmove(c.elemtype, qp, ep)
		c.sendx++ // 将send加一，相当于循环队列的front指针向前进1
		if c.sendx == c.dataqsiz { //当循环队列最后一个元素已使用，此时循环队列将再次从0开始
			c.sendx = 0
		}
		c.qcount++ // 队列中元素计数加1
		unlock(&c.lock) // 释放锁
		return true
	}

	if !block {
		unlock(&c.lock)
		return false
	}

	gp := getg() // 获取当前的G
	mysg := acquireSudog() // 返回一个sudog
	mysg.releasetime = 0
	if t0 != 0 {
		mysg.releasetime = -1
	}
	mysg.elem = ep // 发送的数据
	mysg.waitlink = nil
	mysg.g = gp // 当前G，即发送者
	mysg.isSelect = false
	mysg.c = c
	gp.waiting = mysg
	gp.param = nil
	c.sendq.enqueue(mysg) // 将当前发送者入队sendq中
	goparkunlock(&c.lock, waitReasonChanSend, traceEvGoBlockSend, 3) // 将当前goroutine放入waiting状态，并释放c.lock锁

	// Ensure the value being sent is kept alive until the
	// receiver copies it out. The sudog has a pointer to the
	// stack object, but sudogs aren't considered as roots of the
	// stack tracer
	KeepAlive(ep)

	// someone woke us up.
	if mysg != gp.waiting {
		throw("G waiting list is corrupted")
	}
	gp.waiting = nil
	if gp.param == nil {
		if c.closed == 0 {
			throw("chansend: spurious wakeup")
		}
		panic(plainError("send on closed channel"))
	}
	gp.param = nil
	if mysg.releasetime > 0 {
		blockevent(mysg.releasetime-t0, 2)
	}
	mysg.c = nil
	releaseSudog(mysg)
	return true
}

func send(c *hchan, sg *sudog, ep unsafe.Pointer, unlockf func(), skip int) {
	if raceenabled {
		if c.dataqsiz == 0 {
			// 无缓冲通道
			racesync(c, sg)
		} else {
			qp := chanbuf(c, c.recvx)
			raceacquire(qp)
			racerelease(qp)
			raceacquireg(sg.g, qp)
			racereleaseg(sg.g, qp)
			c.recvx++ // 相当于循环队列的rear指针向前进1
			if c.recvx == c.dataqsiz { // 队列数组中最后一个元素已读取，则再次从头开始读取
				c.recvx = 0
			}
			c.sendx = c.recvx
		}
	}
	if sg.elem != nil { // 复制数据到sg中
		sendDirect(c.elemtype, sg, ep)
		sg.elem = nil
	}
	gp := sg.g
	unlockf()
	gp.param = unsafe.Pointer(sg)
	if sg.releasetime != 0 {
		sg.releasetime = cputicks()
	}
	goready(gp, skip+1) // 使goroutine变成runnable状态，唤醒goroutine
}

func sendDirect(t *_type, sg *sudog, src unsafe.Pointer) {
	dst := sg.elem
	typeBitsBulkBarrier(t, uintptr(dst), uintptr(src), t.size)
	memmove(dst, src, t.size)
}

// 返回缓存槽i位置的对应的指针
func chanbuf(c *hchan, i uint) unsafe.Pointer {
	return add(c.buf, uintptr(i)*uintptr(c.elemsize))
}

// 将src值复制到dst
// 源码https://github.com/golang/go/blob/2bc8d90fa21e9547aeb0f0ae775107dc8e05dc0a/src/runtime/mbarrier.go#L156
func typedmemmove(typ *_type, dst, src unsafe.Pointer) {
	if dst == src {
		return
	}
	...
	memmove(dst, src, typ.size)
	...
}
```

## 从channel中读取数据

```go
func chanrecv(c *hchan, ep unsafe.Pointer, block bool) (selected, received bool) {
	// 当通道为nil时候
	if c == nil {
		if !block { // 当非阻塞模式直接返回
			return
		}
		// 一直阻塞
		gopark(nil, nil, waitReasonChanReceiveNilChan, traceEvGoStop, 2)
		throw("unreachable")
	}
	...
	// 加锁锁
	lock(&c.lock)
	// 当通道已关闭，且通道缓冲没有元素时候，直接返回
	if c.closed != 0 && c.qcount == 0 {
		if raceenabled {
			raceacquire(c.raceaddr())
		}
		unlock(&c.lock) // 释放锁
		if ep != nil {
			typedmemclr(c.elemtype, ep) // 清空ep指向的内存
		}
		return true, false
	}
	// 从发送者队列中取出一个发送者，发送者不为空时候，将发送者数据传递给接收者
	if sg := c.sendq.dequeue(); sg != nil {
		recv(c, sg, ep, func() { unlock(&c.lock) }, 3)
		return true, true
	}

	// 缓冲队列中有数据情况下，从缓存队列取出数据，传递给接收者
	if c.qcount > 0 {
		// qp指向循环队列数组中元素
		qp := chanbuf(c, c.recvx)
		if raceenabled {
			raceacquire(qp)
			racerelease(qp)
		}
		if ep != nil {
			// 直接qp指向的数据复制到ep指向的地址
			typedmemmove(c.elemtype, ep, qp)
		}
		// 清空qp指向内存的数据
		typedmemclr(c.elemtype, qp)
		c.recvx++ // 相当于循环队列中的rear加1
		if c.recvx == c.dataqsiz { // 队列最后一个元素已读取出来，recvx指向0
			c.recvx = 0
		}
		c.qcount-- // 队列中元素个数减1
		unlock(&c.lock) // 释放锁
		return true, true
	}

	if !block {
		unlock(&c.lock)
		return false, false
	}

	gp := getg()
	mysg := acquireSudog()
	mysg.releasetime = 0
	if t0 != 0 {
		mysg.releasetime = -1
	}

	mysg.elem = ep
	mysg.waitlink = nil
	gp.waiting = mysg
	mysg.g = gp
	mysg.isSelect = false
	mysg.c = c
	gp.param = nil
	c.recvq.enqueue(mysg)
	goparkunlock(&c.lock, waitReasonChanReceive, traceEvGoBlockRecv, 3)

	if mysg != gp.waiting {
		throw("G waiting list is corrupted")
	}
	gp.waiting = nil
	if mysg.releasetime > 0 {
		blockevent(mysg.releasetime-t0, 2)
	}
	closed := gp.param == nil
	gp.param = nil
	mysg.c = nil
	releaseSudog(mysg)
	return true, !closed
}

func recv(c *hchan, sg *sudog, ep unsafe.Pointer, unlockf func(), skip int) {
	if c.dataqsiz == 0 {
		if raceenabled {
			racesync(c, sg)
		}
		if ep != nil {
			recvDirect(c.elemtype, sg, ep)
		}
	} else {
		qp := chanbuf(c, c.recvx)
		if raceenabled {
			raceacquire(qp)
			racerelease(qp)
			raceacquireg(sg.g, qp)
			racereleaseg(sg.g, qp)
		}
		// 复制队列中数据到接收者
		if ep != nil {
			typedmemmove(c.elemtype, ep, qp)
		}
		typedmemmove(c.elemtype, qp, sg.elem)
		c.recvx++
		if c.recvx == c.dataqsiz {
			c.recvx = 0
		}
		c.sendx = c.recvx
	}
	sg.elem = nil
	gp := sg.g
	unlockf()
	gp.param = unsafe.Pointer(sg)
	if sg.releasetime != 0 {
		sg.releasetime = cputicks()
	}
	goready(gp, skip+1) // 唤醒G
}
```

## 关闭channel

```go
func closechan(c *hchan) {
	// 当关闭的通道是nil时候，直接恐慌
	if c == nil {
		panic(plainError("close of nil channel"))
	}
	// 加锁
	lock(&c.lock)
	// 通道已关闭，再次关闭直接恐慌
	if c.closed != 0 {
		unlock(&c.lock)
		panic(plainError("close of closed channel"))
	}
	...
	c.closed = 1 // 关闭标志closed置为1
	var glist gList
	// 将接收者添加到glist中
	for {
		sg := c.recvq.dequeue()
		if sg == nil {
			break
		}
		if sg.elem != nil {
			typedmemclr(c.elemtype, sg.elem)
			sg.elem = nil
		}
		if sg.releasetime != 0 {
			sg.releasetime = cputicks()
		}
		gp := sg.g
		gp.param = nil
		if raceenabled {
			raceacquireg(gp, c.raceaddr())
		}
		glist.push(gp)
	}
	// 将发送者添加到glist中
	for {
		sg := c.sendq.dequeue()
		if sg == nil {
			break
		}
		sg.elem = nil
		if sg.releasetime != 0 {
			sg.releasetime = cputicks()
		}
		gp := sg.g
		gp.param = nil
		if raceenabled {
			raceacquireg(gp, c.raceaddr())
		}
		glist.push(gp) // 
	}
	unlock(&c.lock)

	// 循环glist，调用goready唤醒所有接收者和发送者
	for !glist.empty() {
		gp := glist.pop()
		gp.schedlink = 0
		goready(gp, 3)
	}
}
```

## 总结

1. channel规则：

|  操作  | 空Channel | 已关闭Channel | 活跃Channel |
|  ----  | ----  | --- | --- |
| close(ch)  | panic | panic | 成功关闭 |
| ch <-v  | 永远阻塞 | panic | 成功发送或阻塞 |
| v,ok = <-ch | 永远阻塞 | 不阻塞 | 成功接收或阻塞 |

**注意：** 从空通道中写入或读取数据会永远阻塞，这会造成goroutine泄漏。


2. 发送、接收数据以及关闭通道流程图：

![golang通道发送、接收数据以及关闭通道流程图](https://static.cyub.vip/images/202011/channel_flow.jpg)