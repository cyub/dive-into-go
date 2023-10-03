---
title: "映射类型"
---

# 映射

映射也被称为哈希表(hash table)、字典。它是一种由key-value组成的抽象数据结构。大多数情况下，它都能在O(1)的时间复杂度下实现增删改查功能。若在极端情况下出现所有key都发生哈希碰撞时则退回成链表形式，此时复杂度为O(N)。

映射底层一般都是由数组组成，该数组每个元素称为桶，它使用hash函数将key分配到不同桶中，若出现碰撞冲突时候，则采用链地址法（也称为拉链法）或者开放寻址法解决冲突。下图就是一个由姓名-号码构成的哈希表的结构图：

![](https://static.cyub.vip/images/202106/hash_table.svg)

Go语言中映射中key若出现冲突碰撞时候，则采用链地址法解决，Go语言中映射具有以下特点：

- 引用类型变量
- 读写并发不安全
- 遍历结果是随机的

## 数据结构

```eval_rst
.. image:: https://static.cyub.vip/images/202106/map_struct.png
    :alt: 映射底层结构
    :width: 80%
    :align: center
```

Go语言中映射的数据结构是`runtime.hmap`([runtime/map.go](https://github.com/golang/go/blob/go1.14.13/src/runtime/map.go#L115-L129)):

```go
// A header for a Go map.
type hmap struct {
	count     int //  元素个数，用于len函数返回map元素数量
	flags     uint8 // 标志位，标志当前map正在写等状态
	B         uint8  // buckets个数的对数，即桶数量 = 2 ^ B
	noverflow uint16 // overflow桶数量的近似值，overflow桶即溢出桶，即链表法中存在链表上的桶的个数
	hash0     uint32 // 随机数种子，用于计算key的哈希值

	buckets    unsafe.Pointer // 指向buckets数组，如果元素个数为0时，该值为nil
	oldbuckets unsafe.Pointer // 扩容时指向旧的buckets
	nevacuate  uintptr        // 用于指示迁移进度，小于此值的桶已经迁移完成
	
	extra *mapextra // 额外记录overflow桶信息
}
```

映射中每一个桶的结构是`runtime.bmap`([runtime/map.go](https://github.com/golang/go/blob/go1.14.13/src/runtime/map.go#L149-L159))：

```go
// A bucket for a Go map.
type bmap struct {
	tophash [bucketCnt]uint8
}
```

上面bmap结构是静态结构，在编译过程中`runtime.bmap`会拓展成以下结构体：

```go
type bmap struct{
	tophash [8]uint8
	keys [8]keytype // keytype 由编译器编译时候确定
	values [8]elemtype // elemtype 由编译器编译时候确定
	overflow uintptr // overflow指向下一个bmap，overflow是uintptr而不是*bmap类型，是为了减少gc
}
```

bmap结构示意图：

```eval_rst
.. image:: https://static.cyub.vip/images/202106/map_bmap.png
    :alt: bmap底层结构
    :width: 70%
    :align: center
```

每个桶bmap中可以装载8个key-value键值对。当一个key确定存储在哪个桶之后，还需要确定具体存储在桶的哪个位置（这个位置也称为桶单元，一个bmap装载8个key-value键值对，那么一个bmap共8个桶单元），bmap中tophash就是用于实现快速定位key的位置。在实现过程中会使用key的hash值的高八位作为tophash值，存放在bmap的tophash字段中。tophash计算公式如下：

```go
func tophash(hash uintptr) uint8 {
	top := uint8(hash >> (sys.PtrSize*8 - 8))
	if top < minTopHash {
		top += minTopHash
	}
	return top
}
```

上面函数中hash是64位的，sys.PtrSize值是8，所以`top := uint8(hash >> (sys.PtrSize*8 - 8))`等效`top = uint8(hash >> 56)`，最后top取出来的值就是hash的最高8位值。bmap的tophash字段不光存储key哈希值的高八位，还会存储一些状态值，用来表明当前桶单元状态，这些状态值都是小于minTopHash的。

为了避免key哈希值的高八位值出现这些状态值相等产生混淆情况，所以当key哈希值高八位若小于minTopHash时候，自动将其值加上minTopHash作为该key的tophash。桶单元的状态值如下：

```go
emptyRest      = 0 // 表明此桶单元为空，且更高索引的单元也是空
emptyOne       = 1 // 表明此桶单元为空
evacuatedX     = 2 // 用于表示扩容迁移到新桶前半段区间
evacuatedY     = 3 // 用于表示扩容迁移到新桶后半段区间
evacuatedEmpty = 4 // 用于表示此单元已迁移
minTopHash     = 5 // key的tophash值与桶状态值分割线值，小于此值的一定代表着桶单元的状态，大于此值的一定是key对应的tophash值
```

emptyRest和emptyOne状态都表示此桶单元为空，都可以用来插入数据。但是emptyRest还代表着更高单元也为空，那么遍历寻找key的时候，当遇到当前单元值为emptyRest时候，那么更高单元无需继续遍历。

下图中桶单元1的tophash值是emptyOne，桶单元3的tophash值是emptyRest，那么我们一定可以推断出桶单元3以上都是emptyRest状态。

```eval_rst
.. image:: https://static.cyub.vip/images/202106/map_tophash.png
    :alt: bmap的tophash底层结构
    :width: 40%
    :align: center
```

bmap中可以装载8个key-value，这8个key-value并不是按照key1/value1/key2/value2/key3/value3...这样形式存储，而采用key1/key2../key8/value1/../value8形式存储，因为第二种形式可以减少padding，源码中以map[int64]int8举例说明。

hmap中extra字段是`runtime.mapextra`类型，用来记录额外信息：

```go
// mapextra holds fields that are not present on all maps.
type mapextra struct {
	overflow    *[]*bmap // 指向overflow桶指针组成的切片，防止这些溢出桶被gc了
	oldoverflow *[]*bmap // 扩容时候，指向旧的溢出桶组成的切片，防止这些溢出桶被gc了

	//指向下一个可用的overflow 桶
	nextOverflow *bmap
}
```

当映射的key和value都不是指针类型时候，bmap将完全不包含指针，那么gc时候就不用扫描bmap。bmap指向溢出桶的字段overflow是uintptr类型，为了防止这些overflow桶被gc掉，所以需要mapextra.overflow将它保存起来。如果bmap的overflow是*bmap类型，那么gc扫描的是一个个拉链表，效率明显不如直接扫描一段内存(hmap.mapextra.overflow)


## 映射的创建

当使用make函数创建映射时候，若不指定map元素数量时候，底层将使用是`make_small`函数创建hmap结构，此时只产生哈希种子，不初始化桶：

```go
func makemap_small() *hmap {
	h := new(hmap)
	h.hash0 = fastrand()
	return h
}
```

若指定map元素数量时候，底层会使用`makemap`函数创建hmap结构：

```go
func makemap(t *maptype, hint int, h *hmap) *hmap {
	mem, overflow := math.MulUintptr(uintptr(hint), t.bucket.size)
	if overflow || mem > maxAlloc { // 检查所有桶占用的内存是否大于内存限制
		hint = 0
	}

	// h不nil，说明map结构已经创建在栈上了，这个操作由编译器处理的
	if h == nil { // h为nil，则需要创建一个hmap类型
		h = new(hmap)
	}
	h.hash0 = fastrand() // 设置map的随机数种子

	B := uint8(0)
	for overLoadFactor(hint, B) { // 设置合适B的值
		B++
	}
	h.B = B

	// 如果B == 0，那么map的buckets，将会惰性分配（allocated lazily），使用时候再分配
	// 如果B != 0时，初始化桶
	if h.B != 0 {
		var nextOverflow *bmap
		h.buckets, nextOverflow = makeBucketArray(t, h.B, nil)
		if nextOverflow != nil {
			h.extra = new(mapextra)
			h.extra.nextOverflow = nextOverflow // extra.nextOverflow指向下一个可用溢出桶位置
		}
	}

	return h
}
```

makemap函数的第一个参数是maptype类指针，它描述了创建的map中key和value元素的类型信息以及其他map信息，第二个参数hint，对应是`make([Type]Type, len)`中len参数，第三个参数h，如果不为nil，说明当前map的结构已经有编译器在栈上创建了，makemap只需要完成设置随机数种子等操作。

`overLoadFactor`函数用来判断当前映射的加载因子是否超过加载因子阈值。`makemap`使用`overLoadFactor`函数来调整B值。

**加载因子**描述了哈希表中元素填满程度，加载因子越大，表明哈希表中元素越多，空间利用率高，但是这也意味着冲突的机会就会加大。当哈希表中所有桶已写满情况下，加载因子就是1，此时再写入新key一定会产生冲突碰撞。为了提高哈希表写入效率就必须在加载因子超过一定值时（这个值称为加载因子阈值），进行rehash操作，将桶容量进行扩容，来尽量避免出现冲突情况。

Java中hashmap的默认加载因子阈值是0.75，Go语言中映射的加载因子阈值是6.5。为什么Go映射的加载因子阈值不是0.75，而且超过了1？这是因为Java中哈希表的桶存放的是一个key-value，其满载因子是1，Go映射中每个桶可以存8个key-value，满载因子是8，当加载因子阈值为6.5时候空间利用率和写入性能达到最佳平衡。

```go
func overLoadFactor(count int, B uint8) bool {
	// count > bucketCnt，bucketCnt值是8，每一个桶可以存放8个key-value，如果map中元素个数count小于8那么一定不会超过加载因子

	// loadFactorNum和loadFactorDen的值分别是13和2，bucketShift(B)等效于1<<B
	// 所以 uintptr(count) > loadFactorNum*(bucketShift(B)/loadFactorDen) 等于  uintptr(count) > 6.5 * 2^ B
	return count > bucketCnt && uintptr(count) > loadFactorNum*(bucketShift(B)/loadFactorDen)
}

// bucketShift returns 1<<b, optimized for code generation.
func bucketShift(b uint8) uintptr {
	return uintptr(1) << (b & (sys.PtrSize*8 - 1))
}
```

`makeBucketArray`函数是用来创建bmap array，来用作为map的buckets。对于创建时指定元素大小超过(2^4) * 8时候，除了创建map的buckets，也会提前分配好一些桶作为溢出桶。buckets和溢出桶，在内存上是连续的。为啥提前分配好溢出桶，而不是在溢出时候，再分配，这是因为现在分配是直接申请一大片内存，效率更高。

hamp.extra.nextOverflow指向该溢出桶，溢出桶的除了最后一个桶的overflow指向map的buckets，其他桶的overflow指向nil，这是用来判断溢出桶最后边界，后面代码有涉及此处逻辑。

```go
func makeBucketArray(t *maptype, b uint8, dirtyalloc unsafe.Pointer) (buckets unsafe.Pointer, nextOverflow *bmap) {
	base := bucketShift(b) // 等效于 base := 1 << b
	nbuckets := base

	if b >= 4 { // 对于小b，不太可能出现溢出桶，所以B超过4时候，才考虑提前分配写溢出桶
		nbuckets += bucketShift(b - 4)
		sz := t.bucket.size * nbuckets
		up := roundupsize(sz)
		if up != sz {
			nbuckets = up / t.bucket.size
		}
	}

	if dirtyalloc == nil {
		buckets = newarray(t.bucket, int(nbuckets))
	} else {
		// 若dirtyalloc不为nil时，
		// dirtyalloc指向的之前已经使用完的map的buckets，之前已使用完的map和当前map具有相同类型的t和b，这样它buckets可以拿来复用
		// 此时只需对dirtyalloc进行清除操作就可以作为当前map的buckets
		buckets = dirtyalloc
		size := t.bucket.size * nbuckets
		// 下面是清空dirtyalloc操作
		if t.bucket.ptrdata != 0 { // map中key或value是指针类型
			memclrHasPointers(buckets, size)
		} else {
			memclrNoHeapPointers(buckets, size)
		}
	}

	if base != nbuckets { // 多创建一些溢出桶
		nextOverflow = (*bmap)(add(buckets, base*uintptr(t.bucketsize)))
		// 溢出桶的最后一个的overflow字段指向buckets
		last := (*bmap)(add(buckets, (nbuckets-1)*uintptr(t.bucketsize)))
		last.setoverflow(t, (*bmap)(buckets))
	}
	return buckets, nextOverflow
}
```

我们画出桶初始化时候的分配示意图：

```eval_rst
.. image:: https://static.cyub.vip/images/202106/map_overflow_bucket.png
    :alt: 映射的buckets分配
    :width: 60%
    :align: center
```


通过上面分析整个映射创建过程，可以看到使用make创建map时候，返回都是hmap类型指针，这也就说明**Go语言中映射时引用类型的**。

## 访问映射操作

访问映射涉及到key定位的问题，首先需要确定从哪个桶找，确定桶之后，还需要确定key-value具体存放在哪个单元里面（每个桶里面有8个坑位）。key定位详细流程如下：

1. 首先需根据hash函数计算出key的hash值
2. 该key的hash值的低`hmap.B`位的值是该key所在的桶
3. 该key的hash值的高8位，用来快速定位其在桶具体位置。一个桶中存放8个key，遍历所有key，找到等于该key的位置，此位置对应的就是值所在位置
4. 根据步骤3取到的值，计算该值的hash，再次比较，若相等则定位成功。否则重复步骤3去`bmap.overflow`中继续查找。
5. 若`bmap.overflow`链表都找个遍都没有找到，则返回nil。

```eval_rst
.. image:: https://static.cyub.vip/images/202106/map_access.png
    :alt: 映射中桶定位
    :width: 80%
    :align: center
```

当m为2的x幂时候，n对m取余数存在以下等式：

```
n % m = n & (m -1)
```

举个例子比如：n为15，m为8，n%m等7, n&(m-1)也等于7，取余应尽量使用第二种方式，因为效率更高。

那么对于映射中key定位计算就是：

```
key对应value所在桶位置 = hash(key)%(hmap.B << 1) = hash(key) & (hmap.B <<1 - 1)
```
那么为什么上面key定位流程步骤2中说的却是根据该key的hash值的低`hmap.B`位的值是该key所在的桶。两者是没有区别的，只是一种意思不同说法。

### 直接访问与逗号ok模式访问

访问映射操作方式有两种：

第一种直接访问，若key不存在，则返回value类型的零值，其底层实现`mapaccess1`函数：

```go
v := a["x"]
```
第二种是逗号ok模式，如果key不存在，除了返回value类型的零值，ok变量也会设置为false，其底层实现`mapaccess2`：

```go
v, ok := a["x"]
```

为了优化性能，Go编译器会根据key类型采用不同底层函数，比如对于key类型是int的，底层实现是mapaccess1_fast64。具体文件可以查看runtime/map_fastxxx.go。优化版本函数有：

key 类型 | 方法
---- | ----
uint64 | func mapaccess1_fast64(t *maptype, h *hmap, key uint64) unsafe.Pointer
uint64 | func mapaccess2_fast64(t *maptype, h *hmap, key uint64) (unsafe.Pointer, bool)
uint32 | func mapaccess1_fast32(t *maptype, h *hmap, key uint32) unsafe.Pointer
uint32 | func mapaccess2_fast32(t *maptype, h *hmap, key uint32) (unsafe.Pointer, bool)
string | func mapaccess1_faststr(t *maptype, h *hmap, ky string) unsafe.Pointer
string | func mapaccess2_faststr(t *maptype, h *hmap, ky string) (unsafe.Pointer, bool)

这里面我们这分析通用的mapaccess1函数。

```go
func mapaccess1(t *maptype, h *hmap, key unsafe.Pointer) unsafe.Pointer {
	if h == nil || h.count == 0 { // map为nil或者map中元素个数为0，则直接返回零值
		if t.hashMightPanic() {
			t.hasher(key, 0) // see issue 23734
		}
		return unsafe.Pointer(&zeroVal[0])
	}
	if h.flags&hashWriting != 0 { // 有其他Goroutine正在写map，则直接panic
		throw("concurrent map read and map write")
	}
	hash := t.hasher(key, uintptr(h.hash0)) // 计算出key的hash值
	m := bucketMask(h.B) // m = 2^h.B - 1
	b := (*bmap)(add(h.buckets, (hash&m)*uintptr(t.bucketsize))) // 根据上面介绍的取余操作转换成位与操作来获取key所在的桶
	if c := h.oldbuckets; c != nil { // 如果oldbuckets不为0，说明该map正在处于扩容过程中
		if !h.sameSizeGrow() { // 如果不是等容量扩容，此时buckets大小是oldbuckets的两倍，那么m需减半，然后用来定位key在旧桶中位置
			m >>= 1
		}
		oldb := (*bmap)(add(c, (hash&m)*uintptr(t.bucketsize))) // 获取key在旧桶的桶
		if !evacuated(oldb) { // 如果旧桶数据没有迁移新桶里面，那就在旧桶里面找
			b = oldb
		}
	}
	top := tophash(hash) // 计算出key的tophash
bucketloop:
	for ; b != nil; b = b.overflow(t) { // for循环实现功能是先从当前桶找，若未找到则当前桶的溢出桶b.overfolw(t)查找，直到溢出桶为nil
		for i := uintptr(0); i < bucketCnt; i++ { // 每个桶有8个单元，循环这8个单元，一个个找
			if b.tophash[i] != top { // 如果当前单元的tophash与key的tophash不一致，
				if b.tophash[i] == emptyRest { // 若单元tophash值是emptyRest，则直接跳出整个大循环，emptyRest表明当前单元和更高单元存储都为空，所以无需在继续查找下去了
					break bucketloop
				}
				continue // 继续查找桶其他的单元
			}

			// 此时已找到tophash等于key的tophash的桶单元，此时i记录这桶单元编号
			k := add(unsafe.Pointer(b), dataOffset+i*uintptr(t.keysize)) // dataOffset是bmap.keys相对于bmap的偏移，k记录key存在bmap的位置
			if t.indirectkey() { // 若key是指针类型
				k = *((*unsafe.Pointer)(k))
			}
			if t.key.equal(key, k) {// 如果key和存放bmap里面的key相等则获取对应value值返回
				// value在bmap中的位置 = bmap.keys相对于bmap的偏移 + 8个key占用的空间(8 * keysize) + 该value在bmap.values中偏移(i * t.elemsize)
				e := add(unsafe.Pointer(b), dataOffset+bucketCnt*uintptr(t.keysize)+i*uintptr(t.elemsize))
				if t.indirectelem() {
					e = *((*unsafe.Pointer)(e))
				}
				return e
			}
		}
	}
	return unsafe.Pointer(&zeroVal[0])
}
```

## 赋值映射操作

在map中增加和更新key-value时候，都会调用`runtime.mapassign`方法，同访问操作一样，Go编译器针对不同类型的key，会采用优化版本函数：

key 类型 | 方法
---- | ----
uint64 | func mapassign_fast64(t *maptype, h *hmap, key uint64) unsafe.Pointer
unsafe.Pointer | func mapassign_fast64ptr(t *maptype, h *hmap, key unsafe.Pointer) unsafe.Pointer
uint32 | func mapassign_fast32(t *maptype, h *hmap, key uint32) unsafe.Pointer
unsafe.Pointer | func mapassign_fast32ptr(t *maptype, h *hmap, key unsafe.Pointer) unsafe.Pointer
string | func mapassign_faststr(t *maptype, h *hmap, s string) unsafe.Pointer


这里面我们只分析通用的方法mapassign：

```go
func mapassign(t *maptype, h *hmap, key unsafe.Pointer) unsafe.Pointer {
	if h == nil { // 对于nil map赋值操作直接panic。需要注意的是访问nil map返回的是value类型的零值
		panic(plainError("assignment to entry in nil map"))
	}
	if h.flags&hashWriting != 0 { // 有其他Goroutine正在写操作，则直接panic
		throw("concurrent map writes")
	}
	hash := t.hasher(key, uintptr(h.hash0)) // 计算出key的hash值
	h.flags ^= hashWriting // 将写标志位置为1

	if h.buckets == nil { // 惰性创建buckets，make创建map时候，并未初始buckets，等到mapassign时候在创建初始化
		h.buckets = newobject(t.bucket) // newarray(t.bucket, 1)
	}

again:
	bucket := hash & bucketMask(h.B) // bucket := hash & (2^h.B - 1)
	if h.growing() { // 如果当前map处于扩容过程中，则先进行扩容，将key所对应的旧桶先迁移过来
		growWork(t, h, bucket)
	}
	b := (*bmap)(unsafe.Pointer(uintptr(h.buckets) + bucket*uintptr(t.bucketsize))) // 获取key所在的桶
	top := tophash(hash) // 计算出key的tophash

	var inserti *uint8 // 指向key的tophash应该存放的位置，即bmap.tophash这个数组中某个位置
	var insertk unsafe.Pointer // 指向key应该存放的位置，即bmap.keys这个数组中某个位置
	var elem unsafe.Pointer // 指向value应该存放的位置，即bmap.values这个数组中某个位置
bucketloop:
	for {
		for i := uintptr(0); i < bucketCnt; i++ {
			if b.tophash[i] != top {
				if isEmpty(b.tophash[i]) && inserti == nil { // 当i单元的tophash值为空，那么说明该单元可以用来存放key-value。
					// 再加上inserti == nil条件就是inserti只找到第一个空闲的单元即可
					inserti = &b.tophash[i]
					insertk = add(unsafe.Pointer(b), dataOffset+i*uintptr(t.keysize))
					elem = add(unsafe.Pointer(b), dataOffset+bucketCnt*uintptr(t.keysize)+i*uintptr(t.elemsize))
				}
				if b.tophash[i] == emptyRest { // 如果i单元的tophash值为emptyRest，那么剩下单元也不用继续找了，剩下单元一定都是空的
					break bucketloop
				}
				continue
			}

			// 上面代码是先找到第一个为空的桶单元，然后把该桶单元相关的tophash、key、value等位置信息记录在inserti，insertk，elem临时变量上。
			// 这样当key没有在map中情况下，可以拿inserti，insertk，elem这变量，将该key的信息写入到桶单元中，这种情况下key是一个新key，这种赋值操作属于新增操作。

			// 下面代码部分就是处理中map已存在key的情况，这时候，我们只需要找到key所在桶单元中value的位置，然后把value新值写入即可。
			// 这种情况下key是一个旧key，这种赋值操作属于更新操作。
			k := add(unsafe.Pointer(b), dataOffset+i*uintptr(t.keysize))
			if t.indirectkey() {
				k = *((*unsafe.Pointer)(k))
			}
			if !t.key.equal(key, k) {
				continue
			}
			
			if t.needkeyupdate() {
				typedmemmove(t.key, k, key)
			}
			elem = add(unsafe.Pointer(b), dataOffset+bucketCnt*uintptr(t.keysize)+i*uintptr(t.elemsize))
			goto done
		}
		ovf := b.overflow(t) // 当前桶没有找到，继续在其溢出桶里面找，
		if ovf == nil { // 直到都没有找到，那么跳出循环，不在找了。
			break
		}
		b = ovf
	}

	// 当map未扩容中，那么就判断当前map是否需要扩容，扩容条件是以下两个条件符合任意之一即可：
	// 1. 是否达到负载因子的阈值6.5
	// 2. 溢出桶是否过多
	if !h.growing() && (overLoadFactor(h.count+1, h.B) || tooManyOverflowBuckets(h.noverflow, h.B)) {
		hashGrow(t, h)
		goto again // 跳到again标签处，再来一遍
	}

	// 如果上面两层for循环都没有找到空的桶单元，那说明所有桶单元都写满了，那么就得创建一个溢出桶了。
	// 然后将数据存放到该溢出桶的第一个单元上
	if inserti == nil {
		newb := h.newoverflow(t, b) // 创建一个溢出桶
		inserti = &newb.tophash[0]
		insertk = add(unsafe.Pointer(newb), dataOffset)
		elem = add(insertk, bucketCnt*uintptr(t.keysize))
	}

	// store new key/elem at insert position
	if t.indirectkey() {
		kmem := newobject(t.key)
		*(*unsafe.Pointer)(insertk) = kmem
		insertk = kmem
	}
	if t.indirectelem() {
		vmem := newobject(t.elem)
		*(*unsafe.Pointer)(elem) = vmem
	}
	typedmemmove(t.key, insertk, key)
	*inserti = top // 写入key的tophash值
	h.count++ // 更新map的元素计数

done:
	if h.flags&hashWriting == 0 {
		throw("concurrent map writes")
	}
	h.flags &^= hashWriting // 将map的写标志置为0，那么其他Gorountine可以进行写入操作了
	if t.indirectelem() {
		elem = *((*unsafe.Pointer)(elem))
	}
	return elem
}
```

我们梳理总结下mapassign函数执行流程：

1. 首先进行写标志检查和桶初始化检查。如果当前map写标志位已经置为1，那么肯定有它Gorountine正在进行写操作，那么直接panic。桶初始化检查是当map的桶未创建情况下，则在桶初始化检查阶段创建一个桶。

2. 接下来判断桶是否处在扩容过程中，如果处在扩容过程中，那么先将当前key所在旧桶全部迁移到新桶中，然后再接着迁移一个旧桶，也就是说每次mapasssign最多只迁移两个旧桶。为什么一定要先迁移key所在的旧桶数据呢？如果key是新key，那么旧桶中一定没有这个key信息，这种情况迁不迁移旧桶无关紧要，但若key之前在旧桶已存在，那么一定要先迁移，如果不这样的话，当key的新value写入新桶中之后再迁移，那么旧桶中的旧数据就会覆盖掉新桶中key的value值，为了应对这种情况，所以一定要先迁移key所在旧桶数据。

3. 接下就是两层for循环。第一层for循环就是遍历当前key所在桶，以及桶的溢出桶，直到桶的所有溢出桶都遍历一遍后，终止该层循环。第二层for循环遍历的是第一层for循环每次得到的桶中的8个桶单元。两层for循环是为了在map中找到key，如果找到key，那只需更新key对应value值就可。在循环过程中，会记录下第一个为空的桶单元，这样在未找到key的情况时候，就把key-value信息写入这个桶单元中。如果map中未找到key，且也未找到空的桶单元，那么没有办法了，只能创建一个溢出桶来存放该key-value。

4. 接下里判断当前map是否需要扩容，如果需要扩容，则调用hashGrow函数，将旧的buckets挂到hmap.oldbuckets字段上，再接着通过goto语法跳转标签形式跳到流程2继续执行下去

5. 最后就是将key的tophash，key值写入到找到的桶单元中，并返回桶单元的value地址。value的写入是拿到mapassign返回的地址，再写入的。

接下来我们看下溢出桶创建操作：

1. 首先会从预分配的溢出桶列表中取，如果未取到，则会现场创建一个溢出桶
2. 若map的key和value都不是指针类型，那么会将溢出桶记录到hmap.extra.overflow中

```go
func (h *hmap) newoverflow(t *maptype, b *bmap) *bmap {
	var ovf *bmap
	if h.extra != nil && h.extra.nextOverflow != nil {
		ovf = h.extra.nextOverflow // 从上面分析映射的创建过程代码中，我们知道创建map的buckets时候，有时候会顺便创建一些溢出桶，
		// h.extra.nextOverflow就是指向这些溢出桶
		if ovf.overflow(t) == nil { // ovf不是最后一个溢出桶
			h.extra.nextOverflow = (*bmap)(add(unsafe.Pointer(ovf), uintptr(t.bucketsize))) // extra.nextOverflow指向下一个溢出桶
		} else { // ovf是最后一个溢出桶
			ovf.setoverflow(t, nil) // 将ovf.overflow设置nil
			h.extra.nextOverflow = nil
		}
	} else {
		// 没有可用的预分配的溢出桶，则创建一个溢出桶
		ovf = (*bmap)(newobject(t.bucket))
	}
	h.incrnoverflow() // 更新溢出桶计数，这个溢出桶计数可用来是否进行rehash的依据
	if t.bucket.ptrdata == 0 { // 如果map中的key和value都不是指针类型，那么将溢出桶指针添加到extra.overflow这个切片中
		h.createOverflow()
		*h.extra.overflow = append(*h.extra.overflow, ovf)
	}
	b.setoverflow(t, ovf)
	return ovf
}

func (h *hmap) createOverflow() {
	if h.extra == nil {
		h.extra = new(mapextra)
	}
	if h.extra.overflow == nil {
		h.extra.overflow = new([]*bmap)
	}
}

func (b *bmap) overflow(t *maptype) *bmap {
	return *(**bmap)(add(unsafe.Pointer(b), uintptr(t.bucketsize)-sys.PtrSize))
}

func (b *bmap) setoverflow(t *maptype, ovf *bmap) {
	*(**bmap)(add(unsafe.Pointer(b), uintptr(t.bucketsize)-sys.PtrSize)) = ovf
}

func (h *hmap) incrnoverflow() {
	if h.B < 16 {
		h.noverflow++
		return
	}
	
	// 当h.B大于等于16时候，有1/(1<<(h.B-15))的概率会更新h.noverflow
	// 比如h.B == 18时，mask==7，那么fastrand & 7 == 0的概率就是1/8
	mask := uint32(1)<<(h.B-15) - 1
	if fastrand()&mask == 0 {
		h.noverflow++
	}
}
```

## 映射的删除操作

在map中删除key-value时候，都会调用`runtime.mapdelete`方法，同访问操作一样，Go编译器针对不同类型的key，会采用优化版本函数：

key 类型 | 方法
---- | ----
uint64 | func mapdelete_fast64(t *maptype, h *hmap, key uint64)
uint32 | func mapdelete_fast32(t *maptype, h *hmap, key uint32)
string | func mapdelete_faststr(t *maptype, h *hmap, ky string)


这里面我们只大概分析通用删除操作mapdelete函数：

**删除map中元素时候并不会释放内存**。删除时候，会清空映射中相应位置的key和value数据，并将对应的tophash置为emptyOne。此外会检查当前单元旁边单元的状态是否也是空状态，如果也是空状态，那么会将当前单元和旁边空单元状态都改成emptyRest。

```go
func mapdelete(t *maptype, h *hmap, key unsafe.Pointer) {
	if h == nil || h.count == 0 { // 对nil map或者数量为0的map进行删除
		if t.hashMightPanic() {
			t.hasher(key, 0) // see issue 23734
		}
		return
	}
	if h.flags&hashWriting != 0 { // 有其他Goroutine正在写操作，则直接panic
		throw("concurrent map writes")
	}

	hash := t.hasher(key, uintptr(h.hash0))
	h.flags ^= hashWriting // 将写标志置为1，删除操作也是一种写操作

	bucket := hash & bucketMask(h.B)
	if h.growing() {
		growWork(t, h, bucket)
	}
	b := (*bmap)(add(h.buckets, bucket*uintptr(t.bucketsize)))
	bOrig := b
	top := tophash(hash)
search:
	for ; b != nil; b = b.overflow(t) {
		for i := uintptr(0); i < bucketCnt; i++ {
			if b.tophash[i] != top {
				if b.tophash[i] == emptyRest {
					break search
				}
				continue
			}
			k := add(unsafe.Pointer(b), dataOffset+i*uintptr(t.keysize))
			k2 := k
			if t.indirectkey() {
				k2 = *((*unsafe.Pointer)(k2))
			}
			if !t.key.equal(key, k2) {
				continue
			}
			
			// 清空key
			if t.indirectkey() {
				*(*unsafe.Pointer)(k) = nil
			} else if t.key.ptrdata != 0 {
				memclrHasPointers(k, t.key.size)
			}
			// 清空value
			e := add(unsafe.Pointer(b), dataOffset+bucketCnt*uintptr(t.keysize)+i*uintptr(t.elemsize))
			if t.indirectelem() {
				*(*unsafe.Pointer)(e) = nil
			} else if t.elem.ptrdata != 0 {
				memclrHasPointers(e, t.elem.size)
			} else {
				memclrNoHeapPointers(e, t.elem.size)
			}
			b.tophash[i] = emptyOne // 将tophash置为emptyOne
			
			// 下面代码是将当前单元附近的emptyOne状态的单元都改成emptyRest状态
			if i == bucketCnt-1 {
				if b.overflow(t) != nil && b.overflow(t).tophash[0] != emptyRest {
					goto notLast
				}
			} else {
				if b.tophash[i+1] != emptyRest {
					goto notLast
				}
			}
			for {
				b.tophash[i] = emptyRest
				if i == 0 {
					if b == bOrig {
						break
					}
					c := b
					for b = bOrig; b.overflow(t) != c; b = b.overflow(t) {
					}
					i = bucketCnt - 1
				} else {
					i--
				}
				if b.tophash[i] != emptyOne {
					break
				}
			}
		notLast:
			h.count--
			break search
		}
	}

	if h.flags&hashWriting == 0 {
		throw("concurrent map writes")
	}
	h.flags &^= hashWriting
}
```

## 扩容方式

Go语言中映射扩容采用渐进式扩容，避免一次性迁移数据过多造成性能问题。当对映射进行新增、更新时候会触发扩容操作然后进行扩容操作（删除操作只会进行扩容操作，不会进行触发扩容操作），每次最多迁移2个bucket。扩容方式有两种类型：

1. 等容量扩容
2. 双倍容量扩容

### 等容量扩容

当对一个map不停进行新增和删除操作时候，会创建了很多溢出桶，而加载因子没有超过阈值不会发生双倍容量扩容，这些桶利用率很低，就会导致查询效率变慢。这时候就需要采用等容量扩容，使用桶中数据更紧凑，减少溢出桶数量，从而提高查询效率。**等容量扩容的条件是在未达到加载因子阈值情况下，如果B小于15时，溢出桶的数量大于2^B，B大于等于15时候，溢出桶数量大于2^15时候**会进行等容量扩容操作：

```go
func tooManyOverflowBuckets(noverflow uint16, B uint8) bool {
	if B > 15 {
		B = 15
	}
	return noverflow >= uint16(1)<<(B&15)
}
```

### 双倍容量扩容

双倍容量扩容指的是桶的数量变成旧桶数量的2倍。当映射的负载因子超过阈值时候，会触发双倍容量扩容。

```go
func overLoadFactor(count int, B uint8) bool {
	return count > bucketCnt && uintptr(count) > loadFactorNum*(bucketShift(B)/loadFactorDen)
}
```

不论是等容量扩容，还是双倍容量扩容，都会新创建一个buckets，然后将hmap.buckets指向这个新的buckets，hmap.oldbuckets指向旧的buckets。


## 进一步阅读

- [深度解密Go语言之map](https://www.cnblogs.com/qcrao-2018/p/10903807.html)