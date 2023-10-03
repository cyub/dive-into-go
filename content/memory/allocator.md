# 内存分配器

## 概述

Golang内存分配管理策略是**按照不同大小的对象和不同的内存层级来分配管理内存**。通过这种多层级分配策略，形成无锁化或者降低锁的粒度，以及尽量减少内存碎片，来提高内存分配效率。

Golang中内存分配管理的对象按照大小可以分为：

类别 | 大小
--- | ---
微对象 tiny object | (0, 16B)
小对象 small object | [16B, 32KB]
大对象 large object | (32KB, +∞)

Golang中内存管理的层级从最下到最上可以分为：mspan -> mcache -> mcentral -> mheap -> heapArena。golang中对象的内存分配流程如下：

1. 小于16个字节的对象使用`mcache`的微对象分配器进行分配内存
2. 大小在16个字节到32k字节之间的对象，首先计算出需要使用的`span`大小规格，然后使用`mcache`中相同大小规格的`mspan`分配
3. 如果对应的大小规格在`mcache`中没有可用的`mspan`，则向`mcentral`申请
4. 如果`mcentral`中没有可用的`mspan`，则向`mheap`申请，并根据BestFit算法找到最合适的`mspan`。如果申请到的`mspan`超出申请大小，将会根据需求进行切分，以返回用户所需的页数，剩余的页构成一个新的`mspan`放回`mheap`的空闲列表
5. 如果`mheap`中没有可用`span`，则向操作系统申请一系列新的页（最小 1MB）
6. 对于大于32K的大对象直接从`mheap`分配

## mspan

mspan是一个双向链表结构。mspan是golang中内存分配管理的基本单位。

```go
// file: mheap.go
type mspan struct {
	next *mspan     // 指向下一个mspan
	prev *mspan     // 指向上一个mspan

	startAddr uintptr // 该span在arena区域起始地址
	npages    uintptr // 该span在arena区域中占用page个数

	manualFreeList gclinkptr // 空闲对象列表
	freeindex uintptr // 下一个空闲span的索引，freeindex大小介于0到nelems，当freeindex == nelem，表明该span中没有空余对象空间了
	// freeindex之前的元素均是已经被使用的，freeindex之后的元素可能被使用，也可能没被使用
	// freeindex 和 allocCache配合使用来定位出可用span的位置

	nelems uintptr // span链表中元素个数


	allocCache uint64 // 初始值为2^64-1，位值置为1（假定该位的位置是pos）的表明该span链表中对应的freeindex+pos位置的span未使用


	allocBits  *gcBits // 标识该span中所有元素的使用分配情况，位值置为1则标识span链表中对应位置的span已被分配
	gcmarkBits *gcBits // 用来sweep过程进行标记垃圾对象的，用于后续gc。

	allocCount  uint16     // 已分配的对象个数
	spanclass   spanClass  // span类别
	state       mSpanState // mspaninuse etc
	needzero    uint8      // needs to be zeroed before allocation
	elemsize    uintptr    // 能存储的对象大小
}

// file: mheap.go
type spanClass uint8 // span规格类型
```

span大小一共有67个规格。规格列表如下， 其中class = 0 是特殊的span，用于大于32kb对象分配，是直接从mheap上分配的：

```
# file: sizeclasses.go
// class  bytes/obj  bytes/span  objects  tail waste  max waste
//     1          8        8192     1024           0     87.50%
//     2         16        8192      512           0     43.75%
//     3         32        8192      256           0     46.88%
//     4         48        8192      170          32     31.52%
//     5         64        8192      128           0     23.44%
...
//    64      27264       81920        3         128     10.00%
//    65      28672       57344        2           0      4.91%
//    66      32768       32768        1           0     12.50%
```

- class - 规格id，即spanClass
- bytes/obj - 能够存储的对象大小，对应的是mspan的elemsize字段
- bytes/span - 每个span的大小，大小等于页数*页大小，即8k * npages
- object - 每个span能够存储的objects个数，即nelems，也等于(bytes/span)/(bytes/obj)
- tail waste - 每个span产生的内存碎片，即（bytes/span）%（bytes/obj）
- max waste - 最大浪费比例，（bytes/obj-span最小使用量）*objects/(bytes/span)*100,比如class =2时，span运行的最小使用量是9bytes，则max waste=（16-9）*512/8192*100=43.75%

### mcache

mcache持有一系列不同大小的mspan。mcache属于per-P cache，由于M运行G时候，必须绑定一个P，这样当G中申请从mcache分配对象内存时候，无需加锁处理。

```go
// file: mcache.go
type mcache struct {
	next_sample uintptr // trigger heap sample after allocating this many bytes
	local_scan  uintptr // bytes of scannable heap allocated


	// 微对象分配器，对象大小需要小于16byte
	tiny             uintptr // 微对象起始地址
	tinyoffset       uintptr // 从tiny开始的偏移值
	local_tinyallocs uintptr // tiny对象的个数


	// 大小为134的指针数组，数组元素指向mspan，SpanClasses一共有67种，为了满足指针对象和非指针对象，这里为每种规格的span同时准备scan和noscan两个，分别用于存储指针对象和非指针对象
	alloc [numSpanClasses]*mspan

	stackcache [_NumStackOrders]stackfreelist // 栈缓存

	// Local allocator stats, flushed during GC.
	local_largefree  uintptr                  // 大对象释放的字节数
	local_nlargefree uintptr                  // 释放的大对象个数
	local_nsmallfree [_NumSizeClasses]uintptr // 大小为64的数组，每种规格span是否的小对象个数

	flushGen uint32 // 扫描计数
}
```

```go
// file: malloc.go
if size <= maxSmallSize {                // 如果size <= 32k
	if noscan && size < maxTinySize { // 不需要扫描，且size<16
		if size&7 == 0 {
			off = round(off, 8)
		} else if size&3 == 0 {
			off = round(off, 4)
		} else if size&1 == 0 {
			off = round(off, 2)
		}
		if off+size <= maxTinySize && c.tiny != 0 {
			// The object fits into existing tiny block.
			x = unsafe.Pointer(c.tiny + off)
			c.tinyoffset = off + size
			c.local_tinyallocs++
			mp.mallocing = 0
			releasem(mp)
			return x
		}
		// Allocate a new maxTinySize block.
		span := c.alloc[tinySpanClass]
		v := nextFreeFast(span)
		if v == 0 {
			v, _, shouldhelpgc = c.nextFree(tinySpanClass)
		}
		x = unsafe.Pointer(v)
		(*[2]uint64)(x)[0] = 0
		(*[2]uint64)(x)[1] = 0
		// See if we need to replace the existing tiny block with the new one
		// based on amount of remaining free space.
		if size < c.tinyoffset || c.tiny == 0 {
			c.tiny = uintptr(x)
			c.tinyoffset = size
		}
		size = maxTinySize
	} else { // 16b ~ 32kb
		var sizeclass uint8
		if size <= smallSizeMax-8 {
			sizeclass = size_to_class8[(size+smallSizeDiv-1)/smallSizeDiv]
		} else {
			sizeclass = size_to_class128[(size-smallSizeMax+largeSizeDiv-1)/largeSizeDiv]
		}
		size = uintptr(class_to_size[sizeclass])
		spc := makeSpanClass(sizeclass, noscan)
		span := c.alloc[spc]
		v := nextFreeFast(span)
		if v == 0 {
			v, span, shouldhelpgc = c.nextFree(spc)
		}
		x = unsafe.Pointer(v)
		if needzero && span.needzero != 0 {
			memclrNoHeapPointers(unsafe.Pointer(v), size)
		}
	}
} else {// > 32kb
	var s *mspan
	shouldhelpgc = true
	systemstack(func() {
		s = largeAlloc(size, needzero, noscan)
	})
	s.freeindex = 1
	s.allocCount = 1
	x = unsafe.Pointer(s.base())
	size = s.elemsize
}
```


## mcentral

当mcache的中没有可用的span时候，会向mcentral申请，mcetral结构如下：

```go
type mcentral struct {
	lock      mutex // 锁，由于每个p关联的mcache都可能会向mcentral申请空闲的span，所以需要加锁
	spanclass spanClass // mcentral负责的span规格
	nonempty  mSpanList // 空闲span列表
	empty     mSpanList // 已经使用的span列表

	nmalloc uint64 // mcentral已分配的span计数
}
```

**一个mecentral只负责一个规格span**，规格类型记录在mcentral的spanClass字段中。mcentral维护着两个双向链表，nonempty表示链表里还有空闲的mspan待分配。empty表示这条链表里的mspan都被分配了object。mcache从mcentrl中获取和归还span流程如下：

- 获取时候先加锁，先从nonempty中获取一个没有分配使用的span，将其从nonempty中删除，并将span加入empty链表，mcache获取之后释放锁。
- 归还时候先加锁，先将span加入nonempty链表中，并从empty链表中删除，最后释放锁。

## mheap

当mecentral没有可用的span时候，会向mheap申请。

```go
type mheap struct {
	// lock must only be acquired on the system stack, otherwise a g
	// could self-deadlock if its stack grows with the lock held.
	lock      mutex
	free      mTreap // 空闲的并且没有被os收回的二叉树堆，大对象用
	sweepgen  uint32 // 扫描计数值，每次gc后自增2
	sweepdone uint32 // all spans are swept
	sweepers  uint32 // number of active sweepone calls

	allspans []*mspan // 所有的span


	sweepSpans [2]gcSweepBuf

	_ uint32 // align uint64 fields on 32-bit for atomics


	pagesInUse         uint64  // pages of spans in stats mSpanInUse; R/W with mheap.lock
	pagesSwept         uint64  // pages swept this cycle; updated atomically
	pagesSweptBasis    uint64  // pagesSwept to use as the origin of the sweep ratio; updated atomically
	sweepHeapLiveBasis uint64  // value of heap_live to use as the origin of sweep ratio; written with lock, read without
	sweepPagesPerByte  float64 // proportional sweep ratio; written with lock, read without
	// TODO(austin): pagesInUse should be a uintptr, but the 386
	// compiler can't 8-byte align fields.

	scavengeTimeBasis     int64
	scavengeRetainedBasis uint64
	scavengeBytesPerNS    float64
	scavengeRetainedGoal  uint64
	scavengeGen           uint64 // incremented on each pacing update

	reclaimIndex uint64

	reclaimCredit uintptr

	// Malloc stats.
	largealloc  uint64                  // bytes allocated for large objects
	nlargealloc uint64                  // number of large object allocations
	largefree   uint64                  // bytes freed for large objects (>maxsmallsize)
	nlargefree  uint64                  // number of frees for large objects (>maxsmallsize)
	nsmallfree  [_NumSizeClasses]uint64 // number of frees for small objects (<=maxsmallsize)


	arenas [1 << arenaL1Bits]*[1 << arenaL2Bits]*heapArena
	heapArenaAlloc linearAlloc

	arenaHints *arenaHint
	arena linearAlloc


	allArenas []arenaIdx

	sweepArenas []arenaIdx


	curArena struct {
		base, end uintptr
	}

	_ uint32 // ensure 64-bit alignment of central

	// 各个尺寸的central
	central [numSpanClasses]struct {
		mcentral mcentral
		pad      [cpu.CacheLinePadSize - unsafe.Sizeof(mcentral{})%cpu.CacheLinePadSize]byte
	}

	spanalloc             fixalloc // allocator for span*
	cachealloc            fixalloc // allocator for mcache*
	treapalloc            fixalloc // allocator for treapNodes*
	specialfinalizeralloc fixalloc // allocator for specialfinalizer*
	specialprofilealloc   fixalloc // allocator for specialprofile*
	speciallock           mutex    // lock for special record allocators.
	arenaHintAlloc        fixalloc // allocator for arenaHints

	unused *specialfinalizer // never set, just here to force the specialfinalizer type into DWARF
}
```

## heapArena

```go
heapArenaBytes = 1 << logHeapArenaBytes

logHeapArenaBytes = (6+20)*(_64bit*(1-sys.GoosWindows)*(1-sys.GoosAix)*(1-sys.GoarchWasm)) + (2+20)*(_64bit*sys.GoosWindows) + (2+20)*(1-_64bit) + (8+20)*sys.GoosAix + (2+20)*sys.GoarchWasm

// heapArenaBitmapBytes is the size of each heap arena's bitmap.
heapArenaBitmapBytes = heapArenaBytes / (sys.PtrSize * 8 / 2)

pagesPerArena = heapArenaBytes / pageSize

type heapArena struct {
	bitmap [heapArenaBitmapBytes]byte
	spans [pagesPerArena]*mspan
	pageInUse [pagesPerArena / 8]uint8
	pageMarks [pagesPerArena / 8]uint8
}
```
heapArena中arena区域是真正的堆区，所有分配的span都是从这个地方分配。arena区域管理的单元大小是page，page页数为`pagesPerArena`。

在64位linux系统，runtime.mheap会持有 4,194,304 runtime.heapArena，每个 runtime.heapArena 都会管理 64MB 的内存，所有golang的内存上限是256TB。