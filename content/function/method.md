---
title: "方法"
---

# 方法

Go 语言中具有接收者的函数，即为方法。若函数的接收者类型是T，那么我们可以说该函数是类型T的方法。那么方法底层实现是怎么样的，和函数有什么区别呢？这一章节我们将探讨这个。

## 方法的本质就是普通函数

我们来看下如下的代码：

```go
type A struct {
    name string
}

func (a A) Name() string {
    a.name = "Hi " + a.name
    return a.name
}

func main() {
    a := A{name: "new world"}
    println(a.Name())
    println(A.Name(a))
}

func NameofA(a A) string {
    a.name = "Hi " + a.name
    return a.name
}
```

上面代码中，a.Name()表示的是调用对象a的Name方法。它实际上是一个语法糖，等效于A.Name(a)，其中a就是方法接收者。我们可以通过以下代码证明两者是相等的：

```go
t1 := reflect.TypeOf(A.Name)
t2 := relect.TypeOf(NameOfA)

fmt.Println(t1 == t2) // true
```

我们在看下a.Name()底层实现是怎么样的，点击[在线查看](https://go.godbolt.org/z/PrYqcd13z)：

```go
LEAQ    go.string."new world"(SB), AX
MOVQ    AX, "".a+32(SP)
MOVQ    $9, "".a+40(SP)
PCDATA  $0, $0
MOVQ    AX, (SP)
MOVQ    $9, 8(SP)
CALL    "".A.Name(SB)
```
a.Name()底层其实调用的就是A.Name函数，只不过传递的第一参数就是对象a。

综上所述，**方法本质就是普通的函数，方法的接收者就是隐含的第一个参数**。对于其他面向对象的语言来说，类对象就是相应的函数的第一个参数。

### 值接收者和指针接收者混合的方法

比如以下代码中，展示的值接收者和指针接收者混合的方法

```go
type A struct {
    name string
}

func (a A) GetName() string {
    return a.name
}

func (pa *A) SetName() string {
    pa.name = "Hi " + p.name
    return pa.name
}

func main() {
    a := A{name: "new world"}
    pa := &a

    println(pa.GetName()) // 通过指针调用定义的值接收者方法
    println(a.SetName()) // 通过值调用定义的指针接收者方法
}
```

上面代码中通过指针调用值接收者方法和通过值调用指针接收者方法，都能够正常运行。这是因为两者都是语法糖，Go 语言会在编译阶段会将两者转换如下形式：

```go
println((*pa).GetName())
println((&a).SetName())
```

## 方法表达式与方法变量

```go
type A struct {
    name string
}

func (a A) GetName() string {
    return a.name
}

func main() {
    a := A{name: "new world"}

    f1 := A.GetName // 方法表达式
    f1(a)

    f2 := a.GetName // 方法变量
    f2()
}
```

方法表达式(Method Expression) 与方法变量(Method Value)本质上都是 [Function Value](./closure.html#function-value) ，区别在于方法变量会捕获方法接收者形成闭包，此方法变量的生命周期与方法接收者一样，编译器会将其进行优化转换成对类型T的方法调用，并传入接收者作为参数。
根据上面描述我们可以将上面代码中f2理解成如下代码：

```go
func GetFunc() (func()) string {
    a := A{name: "new world"}
    return func() string {
        return A.GetName(a)
    }
}

f2 = GetFunc()
```