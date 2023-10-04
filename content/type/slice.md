---
title: "切片"
---

# 切片

切片是Go语言中最常用的数据类型之一，它类似数组，但相比数组它更加灵活，高效，由于它本身的特性，往往也更容易用错。

不同于数组是值类型，而切片是引用类型。虽然两者作为函数参数传递时候都是值传递（pass by value），但是切片传递的包含数据指针（可以细分为pass by pointer），如果切片使用不当，会产生意想不到的副作用。

## 初始化

切片的初始化方式可以分为三种：

- 使用make函数创建切片

    make函数语法格式为：make([]T, length, capacity)，capacity可以省略，默认等于length
- 使用字面量创建切片
- 从数组或者切片派生(reslice)出新切片

	Go支持从数组、指向数组的指针、切片类型变量再reslice一个新切片。
	
	reslice操作语法可以是[]T[low : high]，也可以是[]T[low : high : max]。其中low,high,max都可以省略，low默认值是0，high默认值cap([]T)，max默认值cap([]T)。low,hight,max取值范围是`0 <= low <= high <= max <= cap([]T)`，其中high-low是新切片的长度，max-low是新切片的容量。

	对于[]T[low : high]，其包含的元素是[]T中下标low开始，到high结束（不含high所在位置的，相当于左闭右开[low, high)）的元素，元素个数是high - low个，容量是cap([]T) - low。

```go
func main() {
	slice1 := make([]int, 0)
	slice2 := make([]int, 1, 3)
	slice3 := []int{}
	slice4 := []int{1: 2, 3}
	arr := []int{1, 2, 3}
	slice5 := arr[1:2]
	slice6 := arr[1:2:2]
	slice7 := arr[1:]
	slice8 := arr[:1]
	slice9 := arr[3:]
	slice10 := slice2[1:2]
	fmt.Printf("%s = %v,\t len = %d, cap = %d\n", "slice1", slice1, len(slice1), cap(slice1))
	fmt.Printf("%s = %v,\t len = %d, cap = %d\n", "slice2", slice2, len(slice2), cap(slice2))
	fmt.Printf("%s = %v,\t len = %d, cap = %d\n", "slice3", slice3, len(slice3), cap(slice3))
	fmt.Printf("%s = %v,\t len = %d, cap = %d\n", "slice4", slice4, len(slice4), cap(slice4))
	fmt.Printf("%s = %v,\t len = %d, cap = %d\n", "slice5", slice5, len(slice5), cap(slice5))
	fmt.Printf("%s = %v,\t len = %d, cap = %d\n", "slice6", slice6, len(slice6), cap(slice6))
	fmt.Printf("%s = %v,\t len = %d, cap = %d\n", "slice7", slice7, len(slice7), cap(slice7))
	fmt.Printf("%s = %v,\t len = %d, cap = %d\n", "slice8", slice8, len(slice8), cap(slice8))
	fmt.Printf("%s = %v,\t len = %d, cap = %d\n", "slice9", slice9, len(slice9), cap(slice9))
	fmt.Printf("%s = %v,\t len = %d, cap = %d\n", "slice10", slice10, len(slice10), cap(slice10))
}
```

上面代码输出一下内容：

```bash
slice1 = [],	 len = 0, cap = 0
slice2 = [0],	 len = 1, cap = 3
slice3 = [],	 len = 0, cap = 0
slice4 = [0 2 3],	 len = 3, cap = 3
slice5 = [2],	 len = 1, cap = 2
slice6 = [2],	 len = 1, cap = 1
slice7 = [2 3],	 len = 2, cap = 2
slice8 = [1],	 len = 1, cap = 3
slice9 = [],	 len = 0, cap = 0
slice10 = [0],	 len = 1, cap = 2
```

{{< hint warning >}}
**注意：** 

我们使用arr[3]访问切片元素时候会报 ``index out of range [3] with length`` 错误，而使用arr[3:]来初始化slice9却是可以的。因为这是Go语言故意为之的。具体原因可以参见 [Why slice not painc](https://github.com/golang/go/issues/42069) 这个issue。
{{< /hint >}}


接下来我们来看看切片的底层数据结构。

## 数据结构

Go语言中切片的底层数据结构是 `runtime.slice`（**[runtime/slice.go](https://github.com/golang/go/blob/go1.14.13/src/runtime/slice.go#L13-L17)**），其中包含了指向数据数组的指针，切片长度以及切片容量：

```go
type slice struct {
	array unsafe.Pointer // 底层数据数组的指针
	len   int // 切片长度
	cap   int // 切片容量
}
```

{{< hint warning >}}
**注意：** 

切片底层数据结构也可以说成是 `reflect.SliceHeader`，两者没有冲突。`reflect.SliceHeader` 是暴露出来的类型，可以被用户程序代码直接使用。
{{< /hint >}}

我们来看看下面切片如何共用同一个底层数组的：

```go
func main() {
	a := []byte{'h', 'e', 'l', 'l', 'o'}
	b := a[2:3]
	c := a[2:3:3]
	fmt.Println(string(a), string(b), string(c)) // 输出 hello l l
}
```

{{< figure src="https://static.cyub.vip/images/202104/go_slice.png" width="400px" class="text-center" title="Go语言切片底层结构示意图">}}

在前面 《**[基础篇-字符串]({{< relref "type/string" >}})** 》 章节，我们使用了 **[GDB]({{< relref "analysis-tools/gdb" >}})** 工具验证了字符串的数据结构，这一次我们使用另外一种方式验证切片的数据结构。我们通过打印切片的底层结构信息来验证：

```go
func main() {
	type sliceHeader struct {
		array unsafe.Pointer // 底层数据数组的指针
		len   int            // 切片长度
		cap   int            // 切片容量
	}
	a := []byte{'h', 'e', 'l', 'l', 'o'}
	b := a[2:3]
	c := a[2:3:3]
	ptrA := (*sliceHeader)(unsafe.Pointer(&a))
	ptrB := (*sliceHeader)(unsafe.Pointer(&b))
	ptrC := (*sliceHeader)(unsafe.Pointer(&c))

	fmt.Printf("切片%s: 底层数组地址=0x%x, 长度=%d, 容量=%d\n", "a", ptrA.array, ptrA.len, ptrA.cap)
	fmt.Printf("切片%s: 底层数组地址=0x%x, 长度=%d, 容量=%d\n", "b", ptrB.array, ptrB.len, ptrB.cap)
	fmt.Printf("切片%s: 底层数组地址=0x%x, 长度=%d, 容量=%d\n", "c", ptrC.array, ptrC.len, ptrC.cap)
}
```

上面代码输出以下内容：

```shell
切片a: 底层数组地址=0xc00009400b, 长度=5, 容量=5
切片b: 底层数组地址=0xc00009400d, 长度=1, 容量=3
切片c: 底层数组地址=0xc00009400d, 长度=1, 容量=1
```

从输出内容可以看到切片变量 `b`和 `c` 都指向同一个底层数组地址 `0xc00009400d`，它们与切片变量 `a` 指向的底层数组地址 `0xc00009400b` 恰好相差2个字节，这两个字节大小的内存空间存在的是 `h` 和 `e` 字符。

## 副作用

由于切片底层结构的特殊性，当我们使用切片的时候需要特别留心，防止产生副作用(side effect)。

### 示例1：append操作产生副作用

```go
func main() {
	slice1 := []byte{'h', 'e', 'l', 'l', 'o'}
	slice2 := slice1[2:3]
	slice2 = append(slice2, 'g')
	fmt.Println(string(slice2)) // lg
	fmt.Println(string(slice1)) // 输出helge，slice1的值也变了。
}
```

上面代码本意是将切片slice2追加`g`字符，却产生副作用，即也修改了slice1的值：

{{< figure src="https://static.cyub.vip/images/202104/slice_append_effect.png" width="400px" class="text-center" title="Go语言append切片时产生副作用">}}

#### 解决append产生的副作用

解决由于append产生的副作用，有两种解决办法：
- reslice时候指定max边界
- 使用copy函数拷贝出一个副本

##### reslice时候指定max边界

```go
func main() {
	slice1 := []byte{'h', 'e', 'l', 'l', 'o'}
	slice2 := slice1[2:3:3]
	slice2 = append(slice2, 'g') // 此时slice2容量扩大到8
	fmt.Println(string(slice2)) // 输出lg
	fmt.Println(string(slice1)) // 输出hello
}
```

通过`slice2 := slice1[2:3:3]` 方式进行reslice之后，slice2的长度和容量一样，若对slice2再进行append操作其一定会发送扩容操作，此后slice2和slice1之间就没有任何关系了。

{{< figure src="https://static.cyub.vip/images/202104/slice_append_effect2.png" width="500px" class="text-center" title="reslice时候指定max边界">}}

##### 使用copy函数拷贝出一个副本

```go
func main() {
	slice1 := []byte{'h', 'e', 'l', 'l', 'o'}
	slice2 := make([]byte, 1)
	copy(slice2, slice1[2:3])
	slice2 = append(slice2, 'g')
	fmt.Println(string(slice2)) // 输出lg
	fmt.Println(string(slice1)) // 输出hello
}
```

### 示例2：指针类型变量引用切片产生副作用

```go
type User struct {
	Likes int
}

func main() {
	users := make([]User, 1)
	pFirstUser := &users[0]
	pFirstUser.Likes++
	fmt.Println("所有用户：")
	for i := range users {
		fmt.Printf("User: %d Likes: %d\n\n", i, users[i].Likes)
	}
	users = append(users, User{}) // 添加一个新用户到集合中
	pFirstUser.Likes++                // 第一个用户的Likes次数加一
	fmt.Println("所有用户：")
	for i := range users {
		fmt.Printf("User: %d Likes: %d\n", i, users[i].Likes)
	}
}
```

指向上面代码输出以下内容：

```shell
所有用户：
User: 0 Likes: 1

所有用户：
User: 0 Likes: 1
User: 1 Likes: 0
```

代码本意是通过User类型指针变量`pUsers`进行第一个用户Likes更新操作，没想到切片进行append之后，产生了副作用：`pUsers`指向切片已经与切片变量`users`不一样了。

{{< figure src="https://static.cyub.vip/images/202104/slice_append_effect3.png" width="500px" class="text-center" title="引用切片变量产生副作用">}}

### 避免切片副作用黄金法则

1. **在边界处拷贝切片**，这里面的边界指的是函数接受切片参数或返回切片的时候。
2. **永远不要使用一个变量来引用切片数据**


## 扩容策略

当对切片进行append操作时候，若切片容量不够时候，会进行扩容处理。当切片进行扩容时候会先调用`runtime.growslice`函数，该函数返回一个新的slice底层结构体，该结构体array字段指向新的底层数组地址，cap字段是新切片的容量，**len字段是旧切片的长度**，旧切片的内容会拷贝到新切片中，最后再把要追加的数据复制到新切片中，并更新切片len长度。

```go
// et是slice元素类型
// old是旧的slice
// cap是新slice最低要求容量大小。是旧的slice的长度加上append函数中追加的元素的个数
// 比如s := []int{1, 2, 3}；s = append(s, 4, 5); 此时growslice中的cap参数值为5
func growslice(et *_type, old slice, cap int) slice {
	if cap < old.cap {
		panic(errorString("growslice: cap out of range"))
	}

	if et.size == 0 {
		return slice{unsafe.Pointer(&zerobase), old.len, cap}
	}

	newcap := old.cap
	doublecap := newcap + newcap
	if cap > doublecap { // 最小cap要求大于旧slice的cap两倍大小
		newcap = cap
	} else {
		if old.len < 1024 { // 当旧slice的len小于1024, 扩容一倍
			newcap = doublecap
		} else { // 否则每次扩容25%
			for 0 < newcap && newcap < cap {
				newcap += newcap / 4
			}
			if newcap <= 0 {
				newcap = cap
			}
		}
	}

	var overflow bool
	var lenmem, newlenmem, capmem uintptr
	switch {
	case et.size == 1: // 元素大小
		lenmem = uintptr(old.len)
		newlenmem = uintptr(cap)
		capmem = roundupsize(uintptr(newcap))
		overflow = uintptr(newcap) > maxAlloc
		newcap = int(capmem) // 调整newcap大小
	case et.size == sys.PtrSize:
		lenmem = uintptr(old.len) * sys.PtrSize
		newlenmem = uintptr(cap) * sys.PtrSize
		capmem = roundupsize(uintptr(newcap) * sys.PtrSize)
		overflow = uintptr(newcap) > maxAlloc/sys.PtrSize
		newcap = int(capmem / sys.PtrSize)
	case isPowerOfTwo(et.size):
		var shift uintptr
		if sys.PtrSize == 8 {
			// Mask shift for better code generation.
			shift = uintptr(sys.Ctz64(uint64(et.size))) & 63
		} else {
			shift = uintptr(sys.Ctz32(uint32(et.size))) & 31
		}
		lenmem = uintptr(old.len) << shift
		newlenmem = uintptr(cap) << shift
		capmem = roundupsize(uintptr(newcap) << shift)
		overflow = uintptr(newcap) > (maxAlloc >> shift)
		newcap = int(capmem >> shift)
	default:
		lenmem = uintptr(old.len) * et.size
		newlenmem = uintptr(cap) * et.size
		capmem, overflow = math.MulUintptr(et.size, uintptr(newcap))
		capmem = roundupsize(capmem)
		newcap = int(capmem / et.size)
	}

	if overflow || capmem > maxAlloc {
		panic(errorString("growslice: cap out of range"))
	}

	var p unsafe.Pointer
	if et.ptrdata == 0 { // 切片元素中没有指针类型数据，不用考虑写屏障问题
		p = mallocgc(capmem, nil, false)
		memclrNoHeapPointers(add(p, newlenmem), capmem-newlenmem)
	} else {
		p = mallocgc(capmem, et, true)
		if lenmem > 0 && writeBarrier.enabled {
			bulkBarrierPreWriteSrcOnly(uintptr(p), uintptr(old.array), lenmem)
		}
	}
	// 涉及到slice扩容都会有内存移动操作
	memmove(p, old.array, lenmem)

	return slice{p, old.len, newcap}
}
```

从上面代码中可以总结出切片扩容的策略是：

1. 若切片容量小于1024，会扩容一倍
2. 若切片容量大于等于1024，会扩容1/4大小，由于考虑内存对齐，最终实际扩容大小可能会大于1/4

从上面代码中可以看到，切片进行扩容时一定会进行内存拷贝，这是成本较大操作。所以**切片一大优化点就是在使用之前尽量指定好切片所需容量，避免出现扩容情况**。

## string类型与[]byte类型如何实现zero-copy互相转换？

### 什么是零拷贝(zero-copy)

**零拷贝(zero-copy)** 指的是CPU不需要先将数据从某处内存复制到另一个特定区域。当应用程序读取文件，需要从磁盘中加载内核区域，然后将内核区域内容复制到应用内存区域，这就涉及到内存拷贝。若采用mmap技术可以文件映射到特定内存中，只需加载一次，应用程序和内核都可以共享内存中文件数据，这就实现了zero-copy。或者当应用程序需要发送文件给远程时候，可以采用sendfile技术实现零拷贝，若未实现零拷贝，则需要进行四次拷贝过程:

> 磁盘---（DMA copy）--> 系统内核 --> 应用程序区域 --> 系统内核(socket) ---（DMA copy）---> 网卡

### 使用[]byte(string) 和 string([]byte)方式进行字符串和字节切片互转时候会不会发生内存拷贝？

```go
package main

func byteArrayToString(b []byte) string {
	return string(b)
}

func stringToByteArray(s string) []byte {
	return []byte(s)
}

func main() {
}
```

我们来看下上面代码中的底层实现

```shell
go tool compile -N -l -S main.go
```

执行上面命名，输出以下内容：

{{< highlight shell "linenos=table,hl_lines=15 25" >}}
"".byteArrayToString STEXT size=117 args=0x28 locals=0x38
	0x0000 00000 (main.go:3)	TEXT	"".byteArrayToString(SB), ABIInternal, $56-40
	0x0000 00000 (main.go:3)	MOVQ	(TLS), CX
	0x0009 00009 (main.go:3)	CMPQ	SP, 16(CX)
	0x000d 00013 (main.go:3)	PCDATA	$0, $-2
	0x000d 00013 (main.go:3)	JLS	110
	0x000f 00015 (main.go:3)	PCDATA	$0, $-1
	0x000f 00015 (main.go:3)	SUBQ	$56, SP
	0x0013 00019 (main.go:3)	MOVQ	BP, 48(SP)
	0x0018 00024 (main.go:3)	LEAQ	48(SP), BP
	...
	0x003c 00060 (main.go:4)	MOVQ	AX, 8(SP)
	0x0041 00065 (main.go:4)	MOVQ	CX, 16(SP)
	0x0046 00070 (main.go:4)	MOVQ	DX, 24(SP)
	0x004b 00075 (main.go:4)	CALL	runtime.slicebytetostring(SB)
	0x0050 00080 (main.go:4)	MOVQ	40(SP), AX
	....
"".stringToByteArray STEXT size=144 args=0x28 locals=0x50
	0x0000 00000 (main.go:7)	TEXT	"".stringToByteArray(SB), ABIInternal, $80-40
	0x0000 00000 (main.go:7)	MOVQ	(TLS), CX
	0x0009 00009 (main.go:7)	CMPQ	SP, 16(CX)
	...
	0x0040 00064 (main.go:8)	MOVQ	AX, 8(SP)
	0x0045 00069 (main.go:8)	MOVQ	CX, 16(SP)
	0x004a 00074 (main.go:8)	CALL	runtime.stringtoslicebyte(SB)
	0x004f 00079 (main.go:8)	MOVQ	32(SP), AX
	0x0054 00084 (main.go:8)	MOVQ	40(SP), CX
	....
{{< / highlight >}}

从上面汇编代码可以看到 `string([]byte)` 底层调用的是 `runtime.slicebytetostring`，`[]byte(string)` 底层调用的是 `runtime.stringtoslicebyte`。查看这两个底层函数实现可以看到两者都是先创建一段内存空间，然后使用 `memmove` 函数拷贝内存，将数据拷贝到新内存空间。这也就是说 `[]byte(string)` 和 `string([]byte)` 进行转换时候需要内存拷贝。

### string类型与[]byte类型 zero-copy转换实现

那么能不能实现不需要内存拷贝的字符串和字节切片的转换呢？答案是可以的。

根据前面 《**[基础篇-字符串]({{< relref "type/string" >}})** 》 章节和本章节，我们可以看到字符串和字节切片底层结构很相似，它们相同部分都有指向底层数据指针和记录底层数据长度len字段，而字节切片额外多了一个字段cap，记录底层数据的容量。我们只要转换时候让它们共享底层数据就能实现zero-copy。让我们再看看字符串和切片的数组结构：

```go
type StringHeader struct {
	Data uintptr
	Len  int
}

type SliceHeader struct {
	Data uintptr
	Len  int
	Cap  int
}
```

我们来看下网上比较常见zero-copy的实现方式，它是有bug的：

```go
func string2bytes(s string) []byte {
    return *(*[]byte)(unsafe.Pointer(&s))
}

func bytes2string(b []byte) string{
    return *(*string)(unsafe.Pointer(&b))
}
```

我们来测试一下：

```go
func main() {
	a := "hello"
	b := string2bytes(a)
	fmt.Println(string(b), len(b), cap(b))
}
```
上面代码输出以下内容：

```shell
hello 5 824634122328
```

从上面输入内容，我们可以看到字符串转换成字节切片后的容量明显是有问题的。让我们来分析下具体原因。

上面两个函数借助 **[非安全指针类型]({{< relref "type/pointer#unsafepointer" >}})** 强制转换类型实现的。对于字节切片转换字符串使用这种方式是可以的，字节切片多余的cap字段会自动溢出掉；而反过来由于字符串没有记录容量字段，那么将其强制转换成字节切片时候，字节切片的cap字段是未知的，这有可能导致非常严重问题。所以将字符串转换成字节切片时候需要保证字节切片的cap设置正确。

正确的字符串转字节切片实现如下：

```go
func StringToBytes(s string) (b []byte) {
	sh := *(*reflect.StringHeader)(unsafe.Pointer(&s))
	bh := (*reflect.SliceHeader)(unsafe.Pointer(&b))
	bh.Data, bh.Len, bh.Cap = sh.Data, sh.Len, sh.Len
	return b
}
```
或者

```go
func StringToBytes(s string) []byte {
	return *(*[]byte)(unsafe.Pointer(
		&struct {
			string
			Cap int
		}{s, len(s)},
	))
}
```

## 进一步阅读

- [The Go Programming Language Specification: Slice expressions](https://golang.org/ref/spec#Slice_expressions)
- [Uber Go Style Guide: Copy Slices and Maps at Boundaries](https://github.com/uber-go/guide/blob/master/style.md#copy-slices-and-maps-at-boundaries)