---
title: "缓冲池 - sync.Pool"
---

# 缓冲池 - sync.Pool

> A Pool is a set of temporary objects that may be individually saved and retrieved.

> Any item stored in the Pool may be removed automatically at any time without notification. If the Pool holds the only reference when this happens, the item might be deallocated.

> A Pool is safe for use by multiple goroutines simultaneously.

> Pool's purpose is to cache allocated but unused items for later reuse, relieving pressure on the garbage collector. That is, it makes it easy to build efficient, thread-safe free lists. However, it is not suitable for all free lists

sync.Pool提供了临时对象缓存池，存在池子的对象可能在任何时刻被自动移除，我们对此不能做任何预期。sync.Pool**可以并发使用**，它通过**复用对象来减少对象内存分配和GC的压力**。当负载大的时候，临时对象缓存池会扩大，**缓存池中的对象会在每2个GC循环中清除**。

sync.Pool拥有两个对象存储容器：`local pool`和`victim cache`。`local pool`与`victim cache`相似，相当于`primary cache`。当获取对象时，优先从`local pool`中查找，若未找到则再从`victim cache`中查找，若也未获取到，则调用New方法创建一个对象返回。当对象放回sync.Pool时候，会放在`local pool`中。当GC开始时候，首先将`victim cache`中所有对象清除，然后将`local pool`容器中所有对象都会移动到`victim cache`中，所以说缓存池中的对象会在每2个GC循环中清除。

`victim cache`是从CPU缓存中借鉴的概念。下面是维基百科中关于`victim cache`的定义：

> 所谓受害者缓存（Victim Cache），是一个与直接匹配或低相联缓存并用的、容量很小的全相联缓存。**当一个数据块被逐出缓存时，并不直接丢弃，而是暂先进入受害者缓存**。如果受害者缓存已满，就替换掉其中一项。**当进行缓存标签匹配时，在与索引指向标签匹配的同时，并行查看受害者缓存**，如果在受害者缓存发现匹配，就将其此数据块与缓存中的不匹配数据块做交换，同时返回给处理器。

> 受害者缓存的意图是弥补因为低相联度造成的频繁替换所损失的时间局部性。

## 用法

sync.Pool提供两个接口，`Get`和`Put`分别用于从缓存池中获取临时对象，和将临时对象放回到缓存池中：

```go
func (p *Pool) Get() interface{}
func (p *Pool) Put(x interface{})
```

### 示例1

```go

type A struct {
	Name string
}

func (a *A) Reset() {
	a.Name = ""
}

var pool = sync.Pool{
	New: func() interface{} {
		return new(A)
	},
}

func main() {
	objA := pool.Get().(*A)
	objA.Reset() // 重置一下对象数据，防止脏数据
	defer pool.Put(objA)
	objA.Name = "test123"
	fmt.Println(objA)
}
```

接下来我们进行基准测试下未使用和使用sync.Pool情况：

```go
type A struct {
	Name string
}

func (a *A) Reset() {
	a.Name = ""
}

var pool = sync.Pool{
	New: func() interface{} {
		return new(A)
	},
}

func BenchmarkWithoutPool(b *testing.B) {
	var a *A
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		for j := 0; j < 10000; j++ {
			a = new(A)
			a.Name = "tink"
		}
	}
}

func BenchmarkWithPool(b *testing.B) {
	var a *A
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		for j := 0; j < 10000; j++ {
			a = pool.Get().(*A)
			a.Reset()
			a.Name = "tink"
			pool.Put(a) // 一定要记得放回操作，否则退化到每次都需要New操作
		}
	}
}
```

基准测试结果如下：

```
# go test -benchmem -run=^$ -bench  .
goos: darwin
goarch: amd64
BenchmarkWithoutPool-8              3404            314232 ns/op          160001 B/op      10000 allocs/op
BenchmarkWithPool-8                 5870            220399 ns/op               0 B/op          0 allocs/op
```
从上面基准测试中，我们可以看到使用sync.Pool之后，每次执行的耗时由314232ns降到220399ns，降低了29.8%，每次执行的内存分配降到0（注意这是平均值，并不是没进行过内存分配，只不过是绝大数操作没有进行过内存分配，最终平均下来，四舍五入之后为0）。

### 示例2

[go-redis/redis](https://github.com/go-redis/redis)项目中实现连接池时候，使用到sync.Pool来创建定时器：

```go
// 创建timer Pool
var timers = sync.Pool{
	New: func() interface{} { // 定义创建临时对象创建方法
		t := time.NewTimer(time.Hour)
		t.Stop()
		return t
	},
}

func (p *ConnPool) waitTurn(ctx context.Context) error {
	select {
	case <-ctx.Done():
		return ctx.Err()
	default:
	}
	...
	timer := timers.Get().(*time.Timer) // 从缓存池中取出对象
	timer.Reset(p.opt.PoolTimeout)

	select {
	...
	case <-timer.C:
		timers.Put(timer) // 将对象放回到缓存池中，以便下次使用
		atomic.AddUint32(&p.stats.Timeouts, 1)
		return ErrPoolTimeout
	}
```

## 数据结构

![](https://static.cyub.vip/images/202106/pool.png)

sync.Pool底层数据结构体是Pool结构体([sync/pool.go](https://github.com/golang/go/blob/go1.14.13/src/sync/pool.go#L44-L57))：

```go
type Pool struct {
	noCopy noCopy // nocopy机制，用于go vet命令检查是否复制后使用

	local     unsafe.Pointer // 指向[P]poolLocal数组，P等于runtime.GOMAXPROCS(0)
	localSize uintptr        // local数组大小，即[P]poolLocal大小

	victim     unsafe.Pointer // 指向上一个gc循环前的local
	victimSize uintptr        // victim数组大小

	New func() interface{} // 创建临时对象的方法，当从local数组和victim数组中都没有找到临时对象缓存，那么会调用此方法现场创建一个
}
```

Pool.local指向大小为`runtime.GOMAXPROCS(0)`的poolLocal数组，相当于大小为`runtime.GOMAXPROCS(0)`的缓存槽(solt)。每一个P都会通过其ID关联一个槽位上的poolLocal，比如对于ID=1的P关联的poolLocal就是[1]poolLocal，这个poolLocal属于per-P级别的poolLocal，与P关联的M和G可以无锁的操作此poolLocal。

poolLocal结构如下：

```go
type poolLocal struct {
	poolLocalInternal // 内嵌poolLocalInternal结构体
	// 进行一些padding，阻止false share
	pad [128 - unsafe.Sizeof(poolLocalInternal{})%128]byte
}

type poolLocalInternal struct {
	private interface{} // 私有属性，快速存取临时对象
	shared  poolChain   // shared是一个双端链表
}
```

为啥不直接把所有poolLocalInternal字段都写到poolLocal里面，而是采用内嵌形式？这是为了好计算出poolLocal的padding大小。

poolChain结构如下：

```go
type poolChain struct {
	// 指向双向链表头
	head *poolChainElt

	// 指向双向链表尾
	tail *poolChainElt
}

type poolChainElt struct {
	poolDequeue
	next, prev *poolChainElt
}

type poolDequeue struct {
	// headTail高32位是环形队列的head
	// headTail低32位是环形队列的tail
	// [tail, head)范围是队列所有元素
	headTail uint64

	vals []eface // 用于存放临时对象，大小是2的倍数，最小尺寸是8，最大尺寸是dequeueLimit
}

type eface struct {
	typ, val unsafe.Pointer
}
```

`poolLocalInternal`的shared字段指向是一个双向链表(doubly-linked list)，链表每一个元素都是poolChainElt类型，poolChainElt是一个双端队列（Double-ended Queue，简写deque），并且链表中每一个元素的队列大小是2的倍数，且是前一个元素队列大小的2倍。poolChainElt是基于环形队列(Circular Queue)实现的双端队列。

若poolLocal属于当前P，那么可以对shared进行pushHead和popHead操作，而其他P只能进行popTail操作。当前其他P进行popTail操作时候，会检查链表中节点的poolChainElt是否为空，若是空，则会drop掉该节点，这样当popHead操作时候避免去查一个空的poolChainElt。

`poolDequeue`中的headTail字段的高32位记录的是环形队列的head，其低32位是环形队列的tail。vals是环形队列的底层数组。

## Get操作

我们来看下如何从sync.Pool中取出临时对象。下面代码已去掉竞态检测相关代码。

```go
func (p *Pool) Get() interface{} {
	l, pid := p.pin() // 返回当前per-P级poolLocal和P的id
	x := l.private
	l.private = nil
	if x == nil {
		x, _ = l.shared.popHead()
		if x == nil {
			x = p.getSlow(pid)
		}
	}
	runtime_procUnpin()
	if x == nil && p.New != nil {
		x = p.New()
	}
	return x
}
```

上面代码执行流程如下：

1. 首先通过调用pin方法，获取当前G关联的P对应的poolLocal和该P的id
2. 接着查看poolLocal的private字段是否存放了对象，如果有的话，那么该字段存放的对象可直接返回，这属于最快路径。
3. 若poolLocal的private字段未存放对象，那么就尝试从poolLocal的双端队列中取出对象，这个操作是lock-free的。
4. 若G关联的per-P级poolLocal的双端队列中没有取出来对象，那么就尝试从其他P关联的poolLocal中偷一个。若从其他P关联的poolLocal没有偷到一个，那么就尝试从victim cache中取。
5. 若步骤4中也没没有取到缓存对象，那么只能调用pool.New方法新创建一个对象。

我们来看下pin方法：

```go
func (p *Pool) pin() (*poolLocal, int) {
	pid := runtime_procPin() // 禁止M被抢占
	s := atomic.LoadUintptr(&p.localSize) // 原子性加载local pool的大小
	l := p.local
	if uintptr(pid) < s {
		// 如果local pool大小大于P的id，那么从local pool取出来P关联的poolLocal
		return indexLocal(l, pid), pid
	}

	/*
	 * 当p.local指向[P]poolLocal数组还没有创建
	 * 或者通过runtime.GOMAXPROCS()调大P数量时候都可能会走到此处逻辑
	 */
	return p.pinSlow()
}

func (p *Pool) pinSlow() (*poolLocal, int) {
	runtime_procUnpin()
	allPoolsMu.Lock() // 加锁
	defer allPoolsMu.Unlock()
	pid := runtime_procPin()

	s := p.localSize
	l := p.local
	if uintptr(pid) < s { // 加锁后再次判断一下P关联的poolLocal是否存在
		return indexLocal(l, pid), pid
	}
	if p.local == nil { // 将p记录到全局变量allPools中，执行GC钩子时候，会使用到
		allPools = append(allPools, p)
	}

	size := runtime.GOMAXPROCS(0) // 根据P数量创建p.local
	local := make([]poolLocal, size)
	atomic.StorePointer(&p.local, unsafe.Pointer(&local[0]))
	atomic.StoreUintptr(&p.localSize, uintptr(size))
	return &local[pid], pid
}

func indexLocal(l unsafe.Pointer, i int) *poolLocal {
	// 通过uintptr和unsafe.Pointer取出[P]poolLocal数组中，索引i对应的poolLocal
	lp := unsafe.Pointer(uintptr(l) + uintptr(i)*unsafe.Sizeof(poolLocal{}))
	return (*poolLocal)(lp)
}
```

pin方法中会首先调用`runtime_procPin`来设置M禁止被抢占。GMP调度模型中，M必须绑定到P之后才能执行G，禁止M被抢占就是禁止M绑定的P被剥夺走，相当于`pin processor`。

pin方法中为啥要首先禁止M被抢占？这是因为我们需要找到per-P级的poolLocal，如果在此过程中发生M绑定的P被剥夺，那么我们找到的就可能是其他M的per-P级poolLocal，没有局部性可言了。

`runtime_procPin`方法是通过给M加锁实现禁止被抢占的，即`m.locks++`。当`m.locks==0`时候m是可以被抢占的:

```go
//go:linkname sync_runtime_procPin sync.runtime_procPin
//go:nosplit
func sync_runtime_procPin() int {
	return procPin()
}

//go:linkname sync_runtime_procUnpin sync.runtime_procUnpin
//go:nosplit
func sync_runtime_procUnpin() {
	procUnpin()
}

//go:nosplit
func procPin() int {
	_g_ := getg()
	mp := _g_.m

	mp.locks++ // 给m加锁
	return int(mp.p.ptr().id)
}

//go:nosplit
func procUnpin() {
	_g_ := getg()
	_g_.m.locks--
}
```

`go:linkname`是编译指令用于将私有函数或者变量在编译阶段链接到指定位置。从上面代码中我们可以看到`sync.runtime_procPin`和`sync.runtime_procUnpin`最终实现方法是`sync_runtime_procPin`和`sync_runtime_procUnpin`。

pinSlow方法用到的`allPoolsMu`和`allPools`是全局变量：

```go
var (
	allPoolsMu Mutex

	// allPools is the set of pools that have non-empty primary
	// caches. Protected by either 1) allPoolsMu and pinning or 2)
	// STW.
	allPools []*Pool

	// oldPools is the set of pools that may have non-empty victim
	// caches. Protected by STW.
	oldPools []*Pool
)
```

接下我们来看Get流程中步骤3的实现：

```go
func (c *poolChain) popHead() (interface{}, bool) {
	d := c.head // 从双向链表的头部开始
	for d != nil {
		if val, ok := d.popHead(); ok { // 从双端队列头部取对象缓存，若取到则返回
			return val, ok
		}
		// 若未取到，则尝试从上一个节点开始取
		d = loadPoolChainElt(&d.prev) 
	}
	return nil, false
}

func loadPoolChainElt(pp **poolChainElt) *poolChainElt {
	return (*poolChainElt)(atomic.LoadPointer((*unsafe.Pointer)(unsafe.Pointer(pp))))
}
```

最后我们看下Get流程中步骤4的实现：

```go
func (p *Pool) getSlow(pid int) interface{} {
	size := atomic.LoadUintptr(&p.localSize)
	locals := p.local
	for i := 0; i < int(size); i++ {
		// 尝试从其他P关联的poolLocal取一个，
		// 类似GMP调度模型从其他P的runable G队列中偷一个

		// 偷的时候是双向链表尾部开始偷，这个和从本地P的poolLocal取恰好是反向的
		l := indexLocal(locals, (pid+i+1)%int(size))
		if x, _ := l.shared.popTail(); x != nil {
			return x
		}
	}

	// 若从其他P的poolLocal没有偷到，则尝试从victim cache取
	size = atomic.LoadUintptr(&p.victimSize)
	if uintptr(pid) >= size {
		return nil
	}
	locals = p.victim
	l := indexLocal(locals, pid)
	if x := l.private; x != nil {
		l.private = nil
		return x
	}
	for i := 0; i < int(size); i++ {
		l := indexLocal(locals, (pid+i)%int(size))
		if x, _ := l.shared.popTail(); x != nil {
			return x
		}
	}

	atomic.StoreUintptr(&p.victimSize, 0)

	return nil
}

func (c *poolChain) popTail() (interface{}, bool) {
	d := loadPoolChainElt(&c.tail)
	if d == nil {
		return nil, false
	}

	for {
		d2 := loadPoolChainElt(&d.next)

		if val, ok := d.popTail(); ok { // 从双端队列的尾部出队
			return val, ok
		}

		if d2 == nil { // 若下一个节点为空，则返回。说明链表已经遍历完了
			return nil, false
		}

		// 下面代码会将当前节点从链表中删除掉。
		// 为什么要删掉它，因为该节点的队列里面有没有对象缓存了，
		// 删掉之后，下次本地P取的时候，不必遍历此空节点了
		if atomic.CompareAndSwapPointer((*unsafe.Pointer)(unsafe.Pointer(&c.tail)), unsafe.Pointer(d), unsafe.Pointer(d2)) {
			storePoolChainElt(&d2.prev, nil)
		}
		d = d2
	}
}

func storePoolChainElt(pp **poolChainElt, v *poolChainElt) {
	atomic.StorePointer((*unsafe.Pointer)(unsafe.Pointer(pp)), unsafe.Pointer(v))
}
```

我们画出Get流程中步骤3和4的中从`local pool`取对象示意图：

![](https://static.cyub.vip/images/202106/pool_queue_pop.png)

总结下从`local pool`流程是：
1. 首先从当前P的localPool的私有属性private上取
2. 若未取到，则从localPool中由队列组成的双向链表上取，**方向是从头部节点队列开始，依次往上查找**
3. 如果当前P的localPool中没有取到，则尝试从其他P的localPool偷一个，**方向是从尾部节点队列开始，依次向下查找**，若当前节点为空，会把当前节点从链表中删掉。

## Put操作

接下来我们还看下对象归还操作：

```go
func (p *Pool) Put(x interface{}) {
	if x == nil {
		return
	}
	l, _ := p.pin() // 返回当前P的localPool
	if l.private == nil { // 若localPool的private没有存放对象，那就存放在private上，这是最快路径。取的时候优先从private上面取
		l.private = x
		x = nil
	}
	if x != nil { // 入队
		l.shared.pushHead(x)
	}
	runtime_procUnpin()
}
```

流程步骤如下：

1. 调用pin方法，返回当前P的localPool
2. 若当前P的localPool的private属性没有存放对象，那就存放其上面，这是最快路径，取的时候优先从private上面取
3. 若当前P的localPool的private属性已经存放了归还的对象，那么就将对象入队存储。

我们接着看步骤3中代码：

```go

func (c *poolChain) pushHead(val interface{}) {
	d := c.head
	if d == nil {
		// 双向链表头部节点为空，则创建
		// 头部节点的队列长度为8
		const initSize = 8
		d = new(poolChainElt)
		d.vals = make([]eface, initSize)
		c.head = d
		storePoolChainElt(&c.tail, d)
	}

	// 将归还对象入队
	if d.pushHead(val) {
		return
	}

	// 若归还对象入队失败，说明当前头部节点的队列已满，会走后面的逻辑：
	// 创建新的队列节点，新的队列长度是当前节点队列的2倍，最大不超过dequeueLimit，
	// 然后将新的队列节点设置为双向链表的头部
	newSize := len(d.vals) * 2
	if newSize >= dequeueLimit {
		newSize = dequeueLimit
	}

	d2 := &poolChainElt{prev: d} // 新节点的prev指针指向旧的头部节点
	d2.vals = make([]eface, newSize)
	c.head = d2 // 新节点成为双向链表的头部节点
	storePoolChainElt(&d.next, d2) // 旧的头部节点next指针指向新节点
	d2.pushHead(val) // 归还的临时对象入队新节点的队列中
}
```

从上面代码可以看到，创建的双向链表第一个节点队列的大小为8，第二个节点队列大小为16，第三个节点队列大小为32，依次类推，最大为dequeueLimit。每个节点队列的大小都是2的n次幂，这是因为队列使用环形队列结构实现的，底层是数组，同前面介绍的映射一样，定位位置时候取余运算可以改成与运算，更高效。

我们画出双向链表中头部节点队列未满和已满两种情况下示意图：

![](https://static.cyub.vip/images/202106/pool_queue_push.png)

## 双端队列 - poolDequeue

从上面Get操作和Put操作中，我们可以看到都是对poolChain操作，poolChain操作最终都是对双端队列poolDequeue的操作，Get操作对应poolDequeue的popHead和popTail, Put操作对应poolDequeue的pushHead。

再看一下poolDequeue结构体定义：

```go
type poolDequeue struct {
	headTail uint64
	vals []eface
}

type eface struct {
	typ, val unsafe.Pointer
}

type dequeueNil *struct{}
```

`poolDequeue`是一个无锁的（lock-free)、固定大小的（fixed-size) 单一生产者(single-producer),多消费者（multi-consumer）队列。单一生产者可以从队列头部push和pop元素，消费者可以从队列尾部pop元素。`poolDequeue`是基于环形队列实现的双端队列。所谓**双端队列（double-ended queue，双端队列，简写deque）是一种具有队列和栈的性质的数据结构。双端队列中的元素可以从两端弹出，其限定插入和删除操作在表的两端进行**。`poolDequeue`支持在两端删除操作，只支持在head端插入。

`poolDequeue`的headTail字段是由环形队列的head索引（即rear索引）和tail索引（即front索引）打包而来，headTail是64位无符号整形，其高32位是head索引，低32位是tail索引：

![环形队列head和tail索引](https://static.cyub.vip/images/202106/pool_queue_head_tail.png)

```go
const dequeueBits = 32

func (d *poolDequeue) unpack(ptrs uint64) (head, tail uint32) {
	const mask = 1<<dequeueBits - 1
	head = uint32((ptrs >> dequeueBits) & mask)
	tail = uint32(ptrs & mask)
	return
}

func (d *poolDequeue) pack(head, tail uint32) uint64 {
	const mask = 1<<dequeueBits - 1
	return (uint64(head) << dequeueBits) |
		uint64(tail&mask)
}
```

head索引指向的是环形队列中下一个需要填充的槽位，即新入队元素将会写入的位置，tail索引指向的是环形队列中最早入队元素位置。环形队列中元素位置范围是[tail, head)。

我们知道环形队列中，为了解决`head == tail`即可能是队列为空，也可能是队列空间全部占满的二义性，有两种解决办法：1. 空余单元法， 2. 记录队列元素个数法。

采用空余单元法时，队列中永远有一个元素空间不使用，即队列中元素个数最多有QueueSize -1个。此时队列为空和占满的判断条件如下：

```
head == tail // 队列为空
(head + 1)%QueueSize == tail // 队列已满
```
![循环队列之空余单元法](https://static.cyub.vip/images/202106/circular_queue.png)


而`poolDequeue`采用的是记录队列中元素个数法，相比空余单元法好处就是不会浪费一个队列元素空间。后面章节讲到的有缓存通道使用到的环形队列也是采用的这种方案。这种方案队列为空和占满的判断条件如下：

```
head == tail // 队列为空
tail +  nums_of_elment_in_queue == head
```
![循环队列之记录元素个数法](https://static.cyub.vip/images/202106/circular_queue2.png)

### 删除操作

删除操作即出队操作。

```go
func (d *poolDequeue) popHead() (interface{}, bool) {
	var slot *eface
	for {
		ptrs := atomic.LoadUint64(&d.headTail)
		head, tail := d.unpack(ptrs)
		if tail == head { // 队列为空情况
			return nil, false
		}

		head--
		ptrs2 := d.pack(head, tail)

		// 先原子性更新head索引信息，更新成功，则取出队列最新的元素所在槽位地址
		if atomic.CompareAndSwapUint64(&d.headTail, ptrs, ptrs2) {
			slot = &d.vals[head&uint32(len(d.vals)-1)]
			break
		}
	}

	val := *(*interface{})(unsafe.Pointer(slot)) // 取出槽位对应存储的值
	if val == dequeueNil(nil) {
		val = nil
	}

	// 不同与popTail，popHead是没有竞态问题，所以可以直接将其复制为eface{}
	*slot = eface{}
	return val, true
}

func (d *poolDequeue) popTail() (interface{}, bool) {
	var slot *eface
	for {
		ptrs := atomic.LoadUint64(&d.headTail)
		head, tail := d.unpack(ptrs)
		if tail == head { // 队列为空情况
			return nil, false
		}

		ptrs2 := d.pack(head, tail+1)
		// 先原子性更新tail索引信息，更新成功，则取出队列最后一个元素所在槽位地址
		if atomic.CompareAndSwapUint64(&d.headTail, ptrs, ptrs2) {
			slot = &d.vals[tail&uint32(len(d.vals)-1)]
			break
		}
	}

	val := *(*interface{})(unsafe.Pointer(slot))
	if val == dequeueNil(nil) {
		val = nil
	}

	/**
		理解后面代码，我们需意识到*slot = eface{}或slot = *eface(nil)不是一个原子操作。
		这是因为每个槽位存放2个8字节的unsafe.Pointer。而Go atomic包是不支持16字节原子操作，只能原子性操作solt中的其中一个字段。

		后面代码中先将solt.val置为nil，然后原子操作solt.typ，那么pushHead操作时候，只需要判断solt.typ是否nil，既可以判断这个槽位完全被清空了（当solt.typ==nil时候，solt.val一定是nil）。
	 */
	slot.val = nil
	atomic.StorePointer(&slot.typ, nil)

	return val, true
}
```

### 插入操作

插入操作即入队操作。

```go
func (d *poolDequeue) pushHead(val interface{}) bool {
	ptrs := atomic.LoadUint64(&d.headTail)
	head, tail := d.unpack(ptrs)
	if (tail+uint32(len(d.vals)))&(1<<dequeueBits-1) == head { // 队列已写满情况
		return false
	}
	slot := &d.vals[head&uint32(len(d.vals)-1)]

	typ := atomic.LoadPointer(&slot.typ)
	if typ != nil { // 说明有其他Goroutine正在pop此槽位，当pop完成之后会drop掉此槽位，队列还是保持写满状态
		return false
	}

	if val == nil {
		val = dequeueNil(nil)
	}
	*(*interface{})(unsafe.Pointer(slot)) = val

	atomic.AddUint64(&d.headTail, 1<<dequeueBits)
	return true
}
```

## pool回收

文章开头介绍sync.Pool时候，我们提到缓存池中的对象会在每2个GC循环中清除。我们现在看看这块逻辑：

```go
func poolCleanup() {

	for _, p := range oldPools { // 清空victim cache
		p.victim = nil
		p.victimSize = 0
	}

	// 将primary cache(local pool)移动到victim cache
	for _, p := range allPools {
		p.victim = p.local
		p.victimSize = p.localSize
		p.local = nil
		p.localSize = 0
	}

	oldPools, allPools = allPools, nil
}

func init() {
	runtime_registerPoolCleanup(poolCleanup)
}
```

sync.Pool通过在包初始化时候使用`runtime_registerPoolCleanup`注册GC的钩子poolCleanup来进行pool回收处理。`runtime_registerPoolCleanup`函数通过编译指令`go:linkname`链接到 [runtime/mgc.go](https://github.com/golang/go/blob/go1.14.13/src/runtime/mgc.go) 文件中 [sync_runtime_registerPoolCleanup](https://github.com/golang/go/blob/go1.14.13/src/runtime/mgc.go#L2214-L2217) 函数: 

```go
var poolcleanup func()

//go:linkname sync_runtime_registerPoolCleanup sync.runtime_registerPoolCleanup
func sync_runtime_registerPoolCleanup(f func()) {
	poolcleanup = f
}

func clearpools() {
	// clear sync.Pools
	if poolcleanup != nil {
		poolcleanup()
	}
	...
}

// gc入口
func gcStart(trigger gcTrigger) {
	...
	clearpools()
	...
}
```

poolCleanup函数会在一次GC时候，会将`local pool`中缓存对象移动到`victim cache`中，然后在下一次GC时候，清空`victim cache`对象。

## 进一步阅读

- [Go: Understand the Design of Sync.Pool](https://medium.com/a-journey-with-go/go-understand-the-design-of-sync-pool-2dde3024e277)
- [CPU缓存-受害者缓存](https://zh.wikipedia.org/wiki/CPU%E7%BC%93%E5%AD%98#%E5%8F%97%E5%AE%B3%E8%80%85%E7%BC%93%E5%AD%98)