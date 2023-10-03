---
title: "值传递"
---

# 值传递

函数传参有三种方式，分别是值传递（pass by value)、引用传递（pass by reference)，以及指针传递（pass by pointer)。指针传递也称为地址传递，本质上也属于值传递，它只不过传递的值是地址而已。所以按照广义的函数传递来分，分为值传递和引用传递。Go语言中函数传参值传递，不支持引用传递。但是由于切片，通道，映射等具有引用传递的某些特性，往往令人疑惑其应该是引用传递。这个章节我们就来探究下Go语言中函数传递的问题。

在探究Go语言中函数传递的问题，我们先研究C++语言下的引用传递和指针传递是怎么回事。

## C++中指针传递

```cpp
#include <stdio.h>

void swap(int* a,int *b){
    printf("交换中：变量a值：%d， 地址：%p； 变量b值：%d，地址：%p\n", *a, &a, *b, &b);
    int temp = *a;
    *a = *b;
    *b = temp;
}

int main() {
    int a = 1;
    int b = 2;
    printf("交换前：变量a值：%d， 地址：%p； 变量b值：%d，地址：%p\n", a, &a, b, &b);
    swap(&a,&b);
    printf("交换后：变量a值：%d， 地址：%p； 变量b值：%d，地址：%p\n", a, &a, b, &b);
    return 0;
}
```

## C++中引用传递

```cpp
#include <stdio.h>
void swap(int &a, int &b){
    printf("交换中：变量a值：%d， 地址：%p； 变量b值：%d，地址：%p\n", a, &a, b, &b);
    int temp = a;
    a = b;
    b = temp;
}

int main() {
    int a = 1;
    int b = 2;
    printf("交换前：变量a值：%d， 地址：%p； 变量b值：%d，地址：%p\n", a, &a, b, &b);
    swap(a,b);
    printf("交换后：变量a值：%d， 地址：%p； 变量b值：%d，地址：%p\n", a, &a, b, &b);
    return 0;
}
```

## 进一步阅读

- [When are function parameters passed by value?](https://golang.org/doc/faq#pass_by_value)
