# 南囡囝共生元体系

## 编译方式

### Zig 编译（推荐）
```bash
zig build-exe nan.c
./nan boot.nan
```

### Nim 编译
```bash
nim c -r nan_coder.nim
nim c -r nan_category.nim
nim c -r nan_microkernel.nim
```

## 文件说明

- nan.c         - 自举起点，C代码，Zig编译
- boot.nan      - 启动脚本
- nan_coder.nim - 码位进制+零维符号+微内核 v0.8
- nan_category.nim - 范畴论编码系统 v0.1
- nan_microkernel.nim - 微内核核心 v0.1

## 自举路径
C(Zig编译) → nan解释器 → boot.nan → 生成更多代码 → 扔掉C
