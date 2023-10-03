---
title: "闭包"
---

# 闭包

C语言中函数名称就是函数的首地址。Go语言中函数名称跟C语言一样，函数名指向函数的首地址，即函数的入口地址。从前面《[基础篇-函数-一等公民](../first-class)》那一章节我们知道Go 语言中函数是一等公民，它可以绑定变量，作函数参数，做函数返回值，那么它底层是怎么实现的呢？

我们先来了解下`Function Value`这个概念。

## Function Value

Go 语言中函数是一等公民，函数可以绑定到变量，也可以做参数传递以及做函数返回值。Golang把这样的参数、返回值、变量称为**Function value**。

Go 语言中**Function value**本质上是一个指针，但是其并不直接指向函数的入口地址，而是指向的`runtime.funcval`([runtime/runtime2.go](https://github.com/cyub/go-1.14.13/blob/master/src/runtime/runtime2.go#L195-L198))这个结构体。该结构体中的fn字段存储的是函数的入口地址：

```go
type funcval struct {
	fn uintptr
	// variable-size, fn-specific data here
}
```

我们以下面这段代码为例来看下**Function value**是如何使用的:

```go
func A(i int) {
	i++
	fmt.Println(i)
}

func B() {
	f1 := A
	f1(1)
}

func C() {
	f2 := A
	f2(2)
}
```

上面代码中，函数A被赋值给变量f1和f2，这种情况下编译器会做出优化，让f1和f2共用一个funcval结构体，该结构体是在编译阶段分配到数据段的只读区域(.rodata)。如下图所示那样，f1和f2都指向了该结构体的地址addr2，该结构体的fn字段存储了函数A的入口地址addr1：

```eval_rst
.. image:: https://static.cyub.vip/images/202105/fuc_var.png
    :alt: Go语言函数调用栈
    :width: 400px
    :align: center
```

为什么f1和f2需要通过了一个二级指针来获取到真正的函数入口地址，而不是直接将f1，f2指向函数入口地址addr1。关于这个原因就涉及到Golang中闭包设计与实现了。

## 闭包

闭包(Closure)通俗点讲就是能够访问外部函数内部变量的函数。像这样能被访问的变量通常被称为捕获变量。

闭包函数指令在编译阶段生成，但因为每个闭包对象都要保存自己捕获的变量，所以要等到执行阶段才创建对应的闭包对象。我们来看下下面闭包的例子：

```go
package main

func A() func() int {
    i := 3
    return func() int {
        return i
    }
}

func main() {
    f1 := A()
    f2 := A()
    
    print(f1())
    pirnt(f2())
}
```

上面代码中当执行main函数时，会在其栈帧区间内为局部变量f1和f2分配栈空间，当执行第一个A函数时候，会在其栈帧空间分配栈空间来存放局部变量i，然后在堆上分配一个funcval结构体（其地址假定addr2)，该结构体的fn字段存储的是A函数内那个闭包函数的入口地址（其地址假定为addr1）。A函数除了分配一个funcval结构体外，还会挨着该结构体分配闭包函数的变量捕获列表，该捕获列表里面只有一个变量i。由于捕获列表的存在，所以说**闭包函数是一个有状态函数**。

当A函数执行完毕后，其返回值赋值给f1，此时f1指向的就是地址addr2。同理下来f2指向地址addr3。f1和f2都能通过funcval取到了闭包函数入口地址，但拥有不同的捕获列表。

当执行f1()时候，Go 语言会将其对应funcval地址存储到特定寄存器（比如amd64平台中使用rax寄存器），这样在闭包函数中就可以通过该寄存器取出funcval地址，然后通过偏移找到每一个捕获的变量。由此可以看出来**Golang中闭包就是有捕获列表的Function value**。

根据上面描述，我们画出内存布局图：

```eval_rst
.. image:: https://static.cyub.vip/images/202105/func_clo.png
    :alt: Go语言函数调用栈
    :width: 400px
    :align: center
```


若闭包捕获的变量会发生改变，编译器会智能的将该变量逃逸到堆上，这样外部函数和闭包引用的是同一个变量，此时不再是变量值的拷贝。这也是为什么下面代码总是打印循环的最后面一个值。

```go
package main

func main() {
	fns := make([]func(), 0, 5)
	for i := 0; i < 5; i++ {
		fns = append(fns, func() {
			println(i)
		})
	}

	for _, fn := range fns { // 最后输出5个5，而不是0，1，2，3，4
		fn()
	}
}
```

感兴趣的可以仿造上图，画出上面代码的内存布局图。重点关注闭包函数捕获的不是值拷贝，而是引用一个堆变量。
