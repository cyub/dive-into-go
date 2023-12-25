---
title: "for-range语法"
---

# 遍历 - for-range语法

for-range语法可以用来遍历数组、指向数组的指针，切片、字符串、映射和通道。

## 遍历数组

当遍历一个数组a时候，循环范围会从0到len(a) -1：

```go
func main() {
	var a [3]int
	for i, v := range a {
		fmt.Println(i, v)
	}

    for i, v := range &a {
		fmt.Println(i, v)
	}
}
```

## 遍历切片

当遍历一个切片s时候，循环范围会从0到len(s) -1，若切片是nil，则迭代次数是0次：

```go
func main() {
	a := make([]int, 3)
	for i, v := range a {
		fmt.Println(i, v)
	}

    a = nil
    for i, v := range a {
		fmt.Println(i, v)
	}
}
```

### for-range切片时候可以边遍历边append吗？

当遍历切片时候，可以边遍历边append操作，这并不会造成死循环。因为遍历之前已经确定了循环范围，遍历操作相当如下伪代码：

```go
len_temp := len(range) // 循环上界
range_temp := range
for index_temp = 0; index_temp < len_temp; index_temp++ {
    value_temp = range_temp[index_temp]
    index = index_temp
    value = value_temp
    original body
}
```

### for-range切片时候，返回的是值拷贝

无论遍历数组还是切片，返回都是数组或切片中的值拷贝：

```go
func main() {
	users := []User{
		{
			Name: "a1",
			Age:  100,
		},
		{
			Name: "a2",
			Age:  101,
		},
		{
			Name: "a2",
			Age:  102,
		},
	}

	fmt.Println("before: ", users)
	for _, v := range users {
		v.Age = v.Age + 10 // 想给users中所有用户年龄增加10岁
	}
	fmt.Println("after:  ", users)

}
```

执行上面代码，输入以下内容：

```
before:  [{a1 100} {a2 101} {a2 102}]
after:   [{a1 100} {a2 101} {a2 102}]
```

解决办法可以通过索引访问原切片或数组：

```go
func main() {
	users := []User{
		{
			Name: "a1",
			Age:  100,
		},
		{
			Name: "a2",
			Age:  101,
		},
		{
			Name: "a2",
			Age:  102,
		},
	}

	fmt.Println("before: ", users)
	for i := range users {
		users[i].Age = users[i].Age + 10
	}
	fmt.Println("after:  ", users)
}
```

## 遍历字符串

当遍历字符串时候，返回的是rune类型，rune类型是int32类型的别名，一个rune就是一个码点(code point)：

```go
// rune is an alias for int32 and is equivalent to int32 in all ways. It is
// used, by convention, to distinguish character values from integer values.
type rune = int32
```


由于遍历字符串时候，返回的是码点，所以索引并不总是依次增加1的：

```go
func main() {
	var str = "hello，你好"
	var buf [100]byte
	for i, v := range str {
		vl := utf8.RuneLen(v)
		si := i + vl
		copy(buf[:], str[i:si])
		fmt.Printf("索引%2d: %q，\t 码点: %#6x，\t 码点转换成字节: %#v\n", i, v, v, buf[:vl])
	}
}
```

执行上面代码将输出以下内容：

```
索引 0: 'h'，	 码点:   0x68，	 码点转换成字节: []byte{0x68}
索引 1: 'e'，	 码点:   0x65，	 码点转换成字节: []byte{0x65}
索引 2: 'l'，	 码点:   0x6c，	 码点转换成字节: []byte{0x6c}
索引 3: 'l'，	 码点:   0x6c，	 码点转换成字节: []byte{0x6c}
索引 4: 'o'，	 码点:   0x6f，	 码点转换成字节: []byte{0x6f}
索引 5: '，'，	 码点: 0xff0c，	 码点转换成字节: []byte{0xef, 0xbc, 0x8c}
索引 8: '你'，	 码点: 0x4f60，	 码点转换成字节: []byte{0xe4, 0xbd, 0xa0}
索引11: '好'，	 码点: 0x597d，	 码点转换成字节: []byte{0xe5, 0xa5, 0xbd}
```

## 遍历映射

当遍历映射时候，Go语言是不会保证遍历顺序的，为了明确强调这一点，Go语言在实现的时候，故意随机地选择一个桶开始遍历。当映射通道为nil时候，遍历次数为0次。

```go
func main() {
	m := map[int]int{
		1: 10,
		2: 20,
		3: 30,
	}

	for i, v := range m {
		fmt.Println(i, v)
	}

	m = nil
	for i, v := range m {
		fmt.Println(i, v)
	}
}
```

### for-range映射时候可以边遍历，边新增或删除吗？

若在一个Goroutine里面边遍历边新增、删除，理论上是可以的，不会触发写检测的，新增的key-value可能会被访问到，也可能不会。

若多个Goroutine中进行遍历、新增、删除操作的话，是不可以的，是可能触发写检测的，然后直接panic。

## 遍历通道

当遍历通道时，直到通道关闭才会终止，若通道是nil，则会永远阻塞。遍历通道源码分析请见《**[运行时篇-通道-从channel中读取数据]({{< relref "concurrency/channel#从channel中读取数据" >}})** 》。


## 进一步阅读

- [Go Range Loop Internals](https://garbagecollected.org/2017/02/22/go-range-loop-internals/)
- [For statements](https://golang.org/ref/spec#For_statements)