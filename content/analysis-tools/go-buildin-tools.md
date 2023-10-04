---
title: "Go语言内置分析工具"
---

# Go 内置分析工具

这一章节将介绍Go 内置分析工具。通过这些工具我们可以分析、诊断、跟踪竞态，GMP调度，CPU耗用等问题。

## go build

`go build`命令用来编译Go 程序。`go build`重要的命令行选项有以下几个：

### go build -n
`-n`选项用来显示编译过程中所有执行的命令，不会真正执行。通过该选项我们可以查看编译器，连接器如何工作的：

```shell
#
# _/home/vagrant/dive-into-go
#

mkdir -p $WORK/b001/
cat >$WORK/b001/importcfg << 'EOF' # internal
# import config
packagefile fmt=/usr/lib/go/pkg/linux_amd64/fmt.a
packagefile runtime=/usr/lib/go/pkg/linux_amd64/runtime.a
EOF
cd /home/vagrant/dive-into-go
/usr/lib/go/pkg/tool/linux_amd64/compile -o $WORK/b001/_pkg_.a -trimpath "$WORK/b001=>" -p main -complete -buildid RcHLBQbXBa2gQVsMR6P0/RcHLBQbXBa2gQVsMR6P0 -goversion go1.14.13 -D _/home/vagrant/dive-into-go -importcfg $WORK/b001/importcfg -pack ./empty_string.go ./string.go
/usr/lib/go/pkg/tool/linux_amd64/buildid -w $WORK/b001/_pkg_.a # internal
cat >$WORK/b001/importcfg.link << 'EOF' # internal
packagefile _/home/vagrant/dive-into-go=$WORK/b001/_pkg_.a
packagefile fmt=/usr/lib/go/pkg/linux_amd64/fmt.a
packagefile runtime=/usr/lib/go/pkg/linux_amd64/runtime.a
packagefile errors=/usr/lib/go/pkg/linux_amd64/errors.a
packagefile internal/fmtsort=/usr/lib/go/pkg/linux_amd64/internal/fmtsort.a
packagefile io=/usr/lib/go/pkg/linux_amd64/io.a
packagefile math=/usr/lib/go/pkg/linux_amd64/math.a
packagefile os=/usr/lib/go/pkg/linux_amd64/os.a
packagefile reflect=/usr/lib/go/pkg/linux_amd64/reflect.a
packagefile strconv=/usr/lib/go/pkg/linux_amd64/strconv.a
packagefile sync=/usr/lib/go/pkg/linux_amd64/sync.a
packagefile unicode/utf8=/usr/lib/go/pkg/linux_amd64/unicode/utf8.a
packagefile internal/bytealg=/usr/lib/go/pkg/linux_amd64/internal/bytealg.a
packagefile internal/cpu=/usr/lib/go/pkg/linux_amd64/internal/cpu.a
packagefile runtime/internal/atomic=/usr/lib/go/pkg/linux_amd64/runtime/internal/atomic.a
packagefile runtime/internal/math=/usr/lib/go/pkg/linux_amd64/runtime/internal/math.a
packagefile runtime/internal/sys=/usr/lib/go/pkg/linux_amd64/runtime/internal/sys.a
packagefile internal/reflectlite=/usr/lib/go/pkg/linux_amd64/internal/reflectlite.a
packagefile sort=/usr/lib/go/pkg/linux_amd64/sort.a
packagefile math/bits=/usr/lib/go/pkg/linux_amd64/math/bits.a
packagefile internal/oserror=/usr/lib/go/pkg/linux_amd64/internal/oserror.a
packagefile internal/poll=/usr/lib/go/pkg/linux_amd64/internal/poll.a
packagefile internal/syscall/execenv=/usr/lib/go/pkg/linux_amd64/internal/syscall/execenv.a
packagefile internal/syscall/unix=/usr/lib/go/pkg/linux_amd64/internal/syscall/unix.a
packagefile internal/testlog=/usr/lib/go/pkg/linux_amd64/internal/testlog.a
packagefile sync/atomic=/usr/lib/go/pkg/linux_amd64/sync/atomic.a
packagefile syscall=/usr/lib/go/pkg/linux_amd64/syscall.a
packagefile time=/usr/lib/go/pkg/linux_amd64/time.a
packagefile unicode=/usr/lib/go/pkg/linux_amd64/unicode.a
packagefile internal/race=/usr/lib/go/pkg/linux_amd64/internal/race.a
EOF
mkdir -p $WORK/b001/exe/
cd .
/usr/lib/go/pkg/tool/linux_amd64/link -o $WORK/b001/exe/a.out -importcfg $WORK/b001/importcfg.link -buildmode=exe -buildid=nR64Q3qx-0ZdNI4_-qJS/RcHLBQbXBa2gQVsMR6P0/RcHLBQbXBa2gQVsMR6P0/nR64Q3qx-0ZdNI4_-qJS -extld=gcc $WORK/b001/_pkg_.a
/usr/lib/go/pkg/tool/linux_amd64/buildid -w $WORK/b001/exe/a.out # internal
mv $WORK/b001/exe/a.out dive-into-go
```

### go build -race

`-race`选项用来检查代码中是否存在竞态问题。`-race`可以用在多个子命令中：

```
go test -race mypkg
go run -race mysrc.go
go build -race mycmd
go install -race mypkg
```

下面是来自Go语言官方博客的一个示例[^1]，在该示例中演示了使用`-race`选项检查代码中的竞态问题：

```go
func main() {
	start := time.Now()
	var t *time.Timer
	t = time.AfterFunc(randomDuration(), func() {
		fmt.Println(time.Now().Sub(start))
		t.Reset(randomDuration())
	})

	time.Sleep(5 * time.Second)
}

func randomDuration() time.Duration {
	return time.Duration(rand.Int63n(1e9))
}
```

上面代码完成的功能是通过`time.AfterFunc`创建定时器，该定时器会在`randomDuration()`时候打印消息，此外还会通过`Rest()`方法重置该定时器，以达到重复利用该定时器目的。

当我们使用`-race`选项执行检查时候，可以发现上面代码是存在竞态问题的：

```shell
$ go run -race main.go
==================
WARNING: DATA RACE
Read by goroutine 5:
  main.func·001()
     race.go:14 +0x169

Previous write by goroutine 1:
  main.main()
      race.go:15 +0x174

Goroutine 5 (running) created at:
  time.goFunc()
      src/pkg/time/sleep.go:122 +0x56
  timerproc()
     src/pkg/runtime/ztime_linux_amd64.c:181 +0x189
==================
```

### go build -gcflags

`-gcflags`选项用来设置编译器编译时参数，支持的参数有：

- -N选项指示禁止优化
- -l选项指示禁止内联
- -S选项指示打印出汇编代码
- -m选项指示打印出变量变量逃逸信息，`-m -m`可以打印出更丰富的变量逃逸信息

`-gcflags`支持只在编译特定包时候才传递编译参数，此时的`-gcflags`格式为`包名=参数列表`。

```
go build -gcflags="-N -l -S"  main.go // 打印出main.go对应的汇编代码
go build -gcflags="log=-N -l" main.go // 只对log包进行禁止优化，禁止内联操作
```

## go tool compile

`go tool compile`命令用于汇编处理Go 程序文件。`go tool compile`支持常见选项有：

- -N选项指示禁止优化
- -l选项指示禁止内联
- -S选项指示打印出汇编代码
- -m选项指示打印出变量内存逃逸信息

```shell
go tool compile -N -l -S main.go # 打印出main.go对应的汇编代码
GOOS=linux GOARCH=amd64 go tool compile -N -l -S main.go # 打印出针对特定系统和CPU架构的汇编代码
```

## go tool nm

`go tool nm`命令用来查看Go 二进制文件中符号表信息。

```shell
go tool nm ./main | grep "runtime.zerobase"
```

## go tool objdump

`go tool objdump`命令用来根据目标文件或二进制文件反编译出汇编代码。该命令支持两个选项：

- -S选项指示打印汇编代码
- -s选项指示搜索相关的汇编代码

```
go tool compile -N -l main.go # 生成main.o
go tool objdump main.o # 打印所有汇编代码
go tool objdump -s "main.(main|add)" ./test # objdump支持搜索特定字符串
```

## go tool trace


## GODEBUG环境变量

`GODEBUG`是控制运行时调试的变量，其参数以逗号分隔，格式为：name=val。`GODEBUG`可以用来观察GMP调度和GC过程。

### GMP调度

与GMP调度相关的两个参数：

- schedtrace：设置 schedtrace=X 参数可以使运行时在每 X 毫秒输出一行调度器的摘要信息到标准 err 输出中。

- scheddetail：设置 schedtrace=X 和 scheddetail=1 可以使运行时在每 X 毫秒输出一次详细的多行信息，信息内容主要包括调度程序、处理器、OS 线程 和 Goroutine 的状态。

我们以下面代码为例：

```go
package main

import (
    "sync"
    "time"
)

func main() {
	var wg sync.WaitGroup
	for i := 0; i < 2000; i++ {
		wg.Add(1)
		go func() {
			a := 0

			for i := 0; i < 1e6; i++ {
				a += 1
			}

			wg.Done()
        }()
        time.Sleep(100 * time.Millisecond)
	}

	wg.Wait()
}
```

执行以下代码获取GMP调度信息：

```shell
GODEBUG=schedtrace=1000 go run ./test.go
```

笔者本人电脑输出以下内容：

```shell
SCHED 0ms: gomaxprocs=8 idleprocs=6 threads=4 spinningthreads=1 idlethreads=0 runqueue=0 [0 0 0 0 0 0 0 0]
SCHED 0ms: gomaxprocs=8 idleprocs=5 threads=3 spinningthreads=1 idlethreads=0 runqueue=0 [1 0 0 0 0 0 0 0]
SCHED 0ms: gomaxprocs=8 idleprocs=5 threads=5 spinningthreads=1 idlethreads=0 runqueue=0 [0 0 0 0 0 0 0 0]
SCHED 0ms: gomaxprocs=8 idleprocs=5 threads=5 spinningthreads=2 idlethreads=0 runqueue=0 [0 0 0 0 0 0 0 0]
SCHED 1007ms: gomaxprocs=8 idleprocs=8 threads=16 spinningthreads=0 idlethreads=9 runqueue=0 [0 0 0 0 0 0 0 0]
SCHED 1000ms: gomaxprocs=8 idleprocs=8 threads=5 spinningthreads=0 idlethreads=3 runqueue=0 [0 0 0 0 0 0 0 0]
SCHED 2018ms: gomaxprocs=8 idleprocs=8 threads=16 spinningthreads=0 idlethreads=9 runqueue=0 [0 0 0 0 0 0 0 0]
```

上面输出内容解释说明：

- SCHED XXms: SCHED是调度日志输出标志符。XXms是自程序启动之后到输出当前行时间
- gomaxprocs： P的数量，等于当前的 CPU 核心数，或者GOMAXPROCS环境变量的值
- idleprocs： 空闲P的数量，与gomaxprocs的差值即运行中P的数量
- threads： 线程数量，即M的数量
- spinningthreads：自旋状态线程的数量。当M没有找到可供其调度执行的 Goroutine 时，该线程并不会销毁，而是出于自旋状态
- idlethreads：空闲线程的数量
- runqueue：全局队列中G的数量
- [0 0 0 0 0 0 0 0]：表示P本地队列下G的数量，有几个P中括号里面就会有几个数字

### GC

与GC相关的参数是gctrace，当设置为1时候，会输出gc信息到标准err输出中。使用方式示例如下：

```shell
GODEBUG=gctrace=1 godoc -http=:8080
```

GC时候输出的内容格式如下：

> gc# @#s #%: #+#+# ms clock, #+#/#/#+# ms cpu, #->#-># MB, # MB goal, #P

格式解释说明如下：

- gc#：GC 执行次数的编号，每次叠加。
- @#s：自程序启动后到当前的具体秒数。
- #%：自程序启动以来在GC中花费的时间百分比。
- #+...+#：GC 的标记工作共使用的 CPU 时间占总 CPU 时间的百分比。
- #->#-># MB：分别表示 GC 启动时, GC 结束时, GC 活动时的堆大小.
- #MB goal：下一次触发 GC 的内存占用阈值。
- #P：当前使用的处理器 P 的数量。

比如对于以下输出内容：

> gc 100 @0.904s 11%: 0.043+2.8+0.029 ms clock, 0.34+3.4/5.4/0+0.23 ms cpu, 10->11->6 MB, 12 MB goal, 8 P

- gc 100：第 100 次 GC
- @0.904s：当前时间是程序启动后的0.904s
- 11%：程序启动后到现在共花费 11% 的时间在 GC 上
- 0.043+2.8+0.029 ms clock
    - 0.043：表示单个 P 在 mark 阶段的 STW 时间
    - 2.8：表示所有 P 的 mark concurrent（并发标记）所使用的时间
    - 0.029：表示单个 P 的 markTermination 阶段的 STW 时间

- 0.34+3.4/5.4/0+0.23 ms cpu:
    - 0.34：表示整个进程在 mark 阶段 STW 停顿的时间，一共0.34秒
    - 3.4/5.4/0：3.4 表示 mutator assist 占用的时间，5.4 表示 dedicated + fractional 占用的时间，0 表示 idle 占用的时间
    - 0.23 ms：0.23 表示整个进程在 markTermination 阶段 STW 时间

- 10->11->6 MB:
    - 10：表示开始 mark 阶段前的 heap_live 大小
    - 11：表示开始 markTermination 阶段前的 heap_live 大小
    - 6：表示被标记对象的大小
- 12 MB goal：表示下一次触发 GC 回收的阈值是 12 MB
- 8 P：本次 GC 一共涉及8 P


#### GOGC参数

Go语言GC相关的另外一个参数是GOGC。GOGC 用于控制GC的处发频率， 其值默认为100, 这意味着直到自上次垃圾回收后heap size已经增长了100%时GC才触发运行，live heap size每增长一倍，GC触发运行一次。若设定GOGC=200, 则live heap size 自上次垃圾回收后，增长2倍时，GC触发运行， 总之，其值越大则GC触发运行频率越低， 反之则越高。如果GOGC=off 则关闭GC。

```bash
# 表示当前应用占用的内存是上次GC时占用内存的两倍时，触发GC
export GOGC=100
```

## 进一步阅读

<!-- - [Introducing the Go Race Detector](https://blog.golang.org/race-detector) -->
- [Go 大杀器之跟踪剖析 trace](https://eddycjy.gitbook.io/golang/di-9-ke-gong-ju/go-tool-trace)
- [go runtime Environment Variables](https://pkg.go.dev/runtime#hdr-Environment_Variables)

[^1]: [Introducing the Go Race Detector](https://blog.golang.org/race-detector)