---
title: "逗号ok模式"
---

# 逗号ok模式

通过逗号ok模式(comma ok idiom)，我们可以进行类型断言，判断映射中是否存在某个key以及通道是否关闭。

## 类型断言

```go
// 方式1
var (
    v T
    ok bool
)
v, ok = x.(T)

// 方式2
v, ok := x.(T) // x是接口类型的变量，T是要断言的类型

// 方式3
var v, ok = x.(T)

// 方式4
v := x.(T) // 当心此种方式断言，若断言失败会发生恐慌
```

## 判断key是否存在映射中

```go
// 方式1
v, ok := a[x]

// 方式2
var v, ok = a[x]
```

## 判断通道是否关闭

```go
// 方式1
var (
    x T
    ok bool
)
x, ok = <-ch

// 方式2
x, ok := <-ch

// 方式3
var x, ok = <-ch
```