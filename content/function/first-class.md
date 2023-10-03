---
title: "Go函数是一等公民"
---

# 一等公民

Go语言中函数是一等公民（first class)，因为它既可以作为变量，也可作为函数参数，函数返回值。Go语言还支持匿名函数，闭包，函数返回多个值。

## 一等公民特征

### 函数赋值给一个变量

```go
func add(a, b int) int {
	return a + b
}

func main() {
	fn := add
	fmt.Println(fn(1, 2)) // 3
}
```

### 函数作为返回值

```go
func pow(a int) func(int) int {
	return func(b int) int {
		result := 1
		for i := 0; i < b; i++ {
			result *= a
		}
		return result
	}
}

func main() {
	powOfTwo := pow(2)         // 2的x次幂
	fmt.Println(powOfTwo(3))   // 8
	fmt.Println(powOfTwo(4))   // 16
	powOfThree := pow(3)       // 3的x次幂
	fmt.Println(powOfThree(3)) // 27
	fmt.Println(powOfThree(4)) // 81
}
```

### 函数作为函数参数传递

下面示例中使用匿名函数作为函数参数传递另外一个函数。

```go
func filter(a []int, fn func(int) bool) (result []int) {
	for _, v := range a {
		if fn(v) {
			result = append(result, v)
		}
	}

	return result
}

func main() {
	data := []int{1, 2, 3, 4, 5}
	// 传递奇数过滤器函子，过滤出奇数
	fmt.Println(filter(data, func(a int) bool {
		return a&1 == 1
	})) // 1, 3, 5
	// 过滤出偶数
	fmt.Println(filter(data, func(a int) bool {
		return a&1 == 0
	})) // 2, 4
}
```

### 使用闭包函数构建一个生成器

生成器指的是每次调用时候总是返回下一序列值。下面演示一个整数的生成器：

```go
func generateInteger() func() int {
	ch := make(chan int)
	count := 0
	go func() {
		for {
			ch <- count
			count++
		}
	}()

	return func() int {
		return <-ch
	}
}

func main() {
	generate := generateInteger()
	fmt.Println(generate()) // 0
	fmt.Println(generate()) // 1
	fmt.Println(generate()) // 2
}
```

## 函数式编程

函数式编程（functional programming）是一种编程范式，其核心思想是将复杂的操作采用函数嵌套、组合调用方式来处理。函数式编程一大特征是函数是一等公民，Go语言中函数是一等公民，但是由于其不支持泛型，Go语言中采用函数式编程有时候是无法通用性的。比如上面的过滤器示例，当想要支持过滤int64类型的，就需要重写一遍或者传递interface{}参数。

### 高阶函数

高阶函数（Higher-order function）指的是至少满足下列一个条件的函数：
- 接受一个或多个函数作为输入
- 输出一个函数

高阶函数是函数式编程中常用范式，常见使用案例有：

- 过滤器
- apply函数
- 排序函数
- 回调函数
- 函数柯里化
- 合成函数


## 进一步阅读

- [7 Easy functional programming techniques in Go](https://deepu.tech/functional-programming-in-go/)
