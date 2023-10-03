---
title: "指针"
---

# 指针

Golang支持指针，但是不能像C语言中那样进行算术运算。**对于任意类型T，其对应的的指针类型是\*T，类型T称为指针类型\*T的基类型**。

## 引用与解引用
一个指针类型\*T变量B存储的是类型T变量A的内存地址，我们称该指针类型变量B**引用(reference)**了A。从指针类型变量B获取（或者称为访问）A变量的值的过程，叫**解引用**。解引用是通过解引用操作符*操作的。

```go
func main() {
	var A int = 100
	var B *int = &A

	fmt.Println(A == *B)
}
```

## 转换和可比较性

对于指针类型变量能不能够比较和显示转换需要满足以下规则：

- 指针类型\*T1和\*T2相应的基类型T1和T2的底层类型必须一致。

```go
type MyInt int
type PInt *int
type PMyInt *MyInt

func main() {
	p1 := new(int)
	var p2 PInt = p1 // p2底层类型是*int
	p3 := new(MyInt)
	var p4 PMyInt = p3 // p4底层类型是*MyInt
	fmt.Println(p1, p2, p3, p4)
}
```

## uintptr

uintptr是一个足够大的整数类型，能够存放任何指针。不同C语言，Go语言中普通类型指针不能进行算术运算，我们可以将普通类型指针转换成uintptr然后进行运算，但普通类型指针不能直接转换成uintptr，必须先转换成unsafe.Pointer类型之后，再转换成uintptr。

```go
// uintptr is an integer type that is large enough to hold the bit pattern of
// any pointer.
type uintptr uintptr
```

## unsafe.Pointer

`unsafe`标准库包提供了`unsafe.Pointer`类型，`unsafe.Pointer`类型称为非安全指针类型。

```go
type ArbitraryType int
type Pointer *ArbitraryType
```

`unsafe`标准库包中也提供了三个函数：

```go
func Alignof(variable ArbitraryType) uintptr // 用来获取变量variable的对齐保证
func Offsetof(selector ArbitraryType) uintptr // 用来获取结构体值中的某个字段的地址相对于此结构体值地址的偏移
func Sizeof(variable ArbitraryType) uintptr // 用来获取变量variable变量的大小尺寸
```

**任何指针类型都可以转换成`unsafe.Pointer`类型**，即`unsafe.Pointer`可以指向任何类型（arbitrary type），但是该类型值是不能够解引用(dereferenced)的。`unsafe.Pointer`类型的零值是nil。反过来，**`unsafe.Pointer`也可以转换成任何指针类型**。

`unsafe.Pointer`类型变量可以显示转换成内置的`uintptr`类型变量，`uintptr`变量是整数，可以进行算术运算，也可以反向转换成`unsafe.Pointer`。

> 安全类型指针(普通类型指针) <----> unsafe.Pointer <-----> uintptr

### 如何正确地使用非类型安全指针？

`unsafe`包中列出[6种正确使用`unsafe.Pointer`的模式](https://golang.google.cn/pkg/unsafe/#Pointer)。

> Code not using these patterns is likely to be invalid today or to become invalid in the future 在代码中不使用这些模式可能现在无效，或者将来也会变成无效的。

#### 通过非安全类型指针，将*T1转换成*T2

```go
func Float64bits(f float64) uint64 {
	return *(*uint64)(unsafe.Pointer(&f))
}
```
此时`unsafe.Pointer`充当桥梁，注意T2类型的尺寸不应该大于T1，否则会出现溢出异常

#### 将非安全类型指针转换成`uintptr`类型

```go
type MyInt int

func main() {
	a := 100
	fmt.Printf("%p\n", &a)
	fmt.Printf("%x\n", uintptr(unsafe.Pointer(&a)))
}
```

#### 将非安全类型指针转换成`uintptr`类型，并进行算术运算

这种模式常用来访问结构体字段或者数组的地址。

```go
type MyType struct {
	f1 uint8
	f2 int
	f3 uint64
}

func main() {
	s := MyType{f1: 10, f2: 20, f3: 30}
	f2UintPtr := uintptr(unsafe.Pointer(uintptr(unsafe.Pointer(&s)) + unsafe.Offsetof(s.f2)))
	fmt.Printf("%p\n", &s)
	fmt.Printf("%x\n", f2UintPtr) // f2UintPtr = s地址 + 8

	arr := [3]int{}
	fmt.Printf("%p\n", &arr)
	for i := 0; i < 3; i++ {
		addr := uintptr(unsafe.Pointer(uintptr(unsafe.Pointer(&arr[0])) + uintptr(i)*unsafe.Sizeof(arr[0])))
		fmt.Printf("%x\n", addr)
	}
}
```

通过指针移动到变量内存地址的末尾是无效的：

```go
// INVALID: end points outside allocated space.
var s thing
end = unsafe.Pointer(uintptr(unsafe.Pointer(&s)) + unsafe.Sizeof(s))

// INVALID: end points outside allocated space.
b := make([]byte, n)
end = unsafe.Pointer(uintptr(unsafe.Pointer(&b[0])) + uintptr(n))
```

```eval_rst
.. warning:: 当将uintptr转换回unsafe.Pointer时，其不能赋值给一个变量进行中转。
```

我们来看看下面这个例子：

```go
type MyType struct {
	f1 uint8
	f2 int
	f3 uint64
}

func main() {
	// 方式1
	s := MyType{f1: 10, f2: 20, f3: 30}
	ptr := uintptr(unsafe.Pointer(&s)) + unsafe.Offsetof(s.f2)
	f2Ptr := (*int)(unsafe.Pointer(ptr))
	fmt.Println(*f2Ptr)

	// 方式2
	f2Ptr2 := (*int)(unsafe.Pointer(uintptr(unsafe.Pointer(&s)) + unsafe.Offsetof(s.f2)))
	fmt.Println(*f2Ptr2)
}
```

上面代码中方式1是不安全的，尽管大多数情况结果是符合我们期望的，但是由于将uintptr赋值给ptr时，变量s已不再被引用，这时候若恰好进行GC，变量s会被回收处理。这会造成此后的操作都是非法访问内存地址。所以对于uintptr转换成unsafe.Pointer的场景，我们应该采用方式2将其写在一行里面。

#### 将非类型安全指针值转换为uintptr值，然后传递给syscall.Syscall函数

如果unsafe.Pointer参数必须转换为uintptr才能作为参数使用，这个转换必须出现在调用表达式中：

```go
syscall.Syscall(SYS_READ, uintptr(fd), uintptr(unsafe.Pointer(p)), uintptr(n))
```
将unsafe.Pointer转换成uintptr后传参时，无法保证执行函数时其执行的内存未回收。只有将这个转换放在函数调用表达时候，才能保证函数能够安全的访问该内存，这个是编译器进行安全保障实现的。

#### 将reflect.Value.Pointer或reflect.Value.UnsafeAddr方法的uintptr返回值转换为非类型安全指针

reflect标准库包中的Value类型的Pointer和UnsafeAddr方法都返回uintptr类型值，而不是unsafe.Pointer类型值，是**为了避免用户在不引用unsafe包情况下就可以将这两个方法的返回值转换为任何类型安全指针类型**。

调用reflect.Value.Pointer或reflect.Value.UnsafeAddr方法获取uintptr，并转换unsafe.Pointer必须放在一行表达式中：

```go
p := (*int)(unsafe.Pointer(reflect.ValueOf(new(int)).Pointer()))
```

下面这种形式是非法：

```go
// INVALID: uintptr cannot be stored in variable
// before conversion back to Pointer.
u := reflect.ValueOf(new(int)).Pointer()
p := (*int)(unsafe.Pointer(u))
```

#### 将reflect.SliceHeader或reflect.StringHeader的Data字段转换成非安全类型，或反之操作

正确的转换操作如下：

```go
var s string
hdr := (*reflect.StringHeader)(unsafe.Pointer(&s)) // 模式1
hdr.Data = uintptr(unsafe.Pointer(p))              // 模式6
hdr.Len = n
```

下面操作是存在bug的：

```go
var hdr reflect.StringHeader
hdr.Data = uintptr(unsafe.Pointer(p))
// 当执行下面代码时候，hdr.Data指向的内存可以已经被回收了
hdr.Len = n
s := *(*string)(unsafe.Pointer(&hdr))
```