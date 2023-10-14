---
title: "简介"
---

{{< figure src="https://static.cyub.vip/images/202104/dive_info_go_feature.png" width="420px" class="text-center">}}

欢迎阅读《深入Go语言之旅》。本书从Go语言源码出发，分析Goroutine调度流程，通道、上下文等的源码，以及defer，panic等语言特性，希望能够帮助阅读此书的人更好的理解Go语言的设计与实现机制。
本书分析的源码基于 [go1.14.13](https://github.com/golang/go/tree/go1.14.13) 版本，运行在ubuntu16 64位系统下，如无特殊说明，本书所有展示分析的源码，以及示例执行结果都是基于此环境。

欢迎扫描下面二维码进微信群，探讨交流Go语言知识。申请加入时候请备注：**深入Go语言之旅**。群主会拉你进群。

{{< figure src="https://static.cyub.vip/images/202112/wx_qrc.jpeg"  width="185px" class="text-center">}}

如果觉得作者写的不错，对您有些帮助，欢迎赞助作者一杯咖啡☕️。在阅读中有什么问题不懂，或者可以指正的都可以通过上面微信码联系作者，或者发邮件(qietingfy#gmail.com)交流沟通。

{{< figure src="https://static.cyub.vip/images/202201/wepay.jpeg" width="160px" class="text-center">}}

<!-- .. image:: https://static.cyub.vip/images/202201/wepay.jpeg
    :alt: 深入Go语言之旅赞助
    :align: center
    :width: 160px
    :target: https://go.cyub.vip -->

## 感谢打赏

十分感谢以下读者的打赏❤️

姓名 | 金额 | 留言
--- | --- | ---
铁头班\*友 | 10 |
 \*w |  50 | 写的很好，加油
 \*油 | 33 |
\*谭 | 10
 林*壕  | 20
 张*冲 | 20
 强* | 6.6
 w*g | 20 | excellent work

## 参考资料

- [Go语言调度器源代码情景分析](https://www.cnblogs.com/abozhang/tag/goroutine%E8%B0%83%E5%BA%A6%E5%99%A8/)
- [cch123/golang-notes](https://github.com/cch123/golang-notes)
- [Go语言设计与实现](https://u.jd.com/Kbpnch5)
- [深度探索Go语言：对象模型与runtime的原理、特性及应用](https://u.jd.com/K8pazHz)
