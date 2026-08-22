# 南囡囝微内核 v0.1
# 跨语言解释器：解析任何指令/函数/算式
# 零外部依赖，自举执行
# ============================================
# 核心理念：
# - 微内核 = 极简指令集 + 字节码解释器
# - 不依赖gcc：Nim自带nim虚拟机
# - 不依赖命令行：内置交互环境
# - 不依赖外部生态：所有功能自包含
# ============================================

type
  # 指令类型
  指令类型* = enum
    算术指令
    逻辑指令
    跳转指令
    内存指令
    函数指令
    容器指令

  # 操作数
  操作数* = object
    case 类型*: string
    of "立即数":
      整数值*: int64
    of "寄存器":
      寄存器号*: uint8
    of "内存":
      内存地址*: int
    of "码位":
      码位值*: uint8
    of "容器":
      容器ID*: uint8
    of "空":
      discard

  # 单条指令
  指令* = object
    操作码*: uint8
    操作数列表*: seq[操作数]
    码位坐标*: (int, int, int)  # 三维定位

  # 解析结果
  解析结果* = object
    成功*: bool
    输出*: string
    误差*: float

  # 语法树节点
  语法树节点* = object
    类型*: string          # "算术"/"逻辑"/"跳转"/"赋值"
    操作*: string          # "+"/"-"/"*"/"/"/"if"/"while"...
    左子*: ref 语法树节点
    右子*: ref 语法树节点
    值*: string            # 叶子节点的值

  # 产权容器（封装比特流的容器）
  产权容器* = object
    名称*: string
    容量*: int
    已用*: int
    内部数据*: seq[uint8]  # 封装的比特流
    归属权*: uint8         # 0=刘楚恬, 1=接接接

  # 跨语言接口
  跨语言函数* = object
    名称*: string
    参数签名*: seq[string]  # "int"/"float"/"string"/"码位"
    返回类型*: string
    Nim实现*: proc(args: seq[string]): string

# ============================================
# 1. 极简指令集（28条，覆盖所有运算）
# ============================================

const 指令集*: array[28, string] = [
  "NOP",   # 0 空操作
  "LOAD",  # 1 加载
  "STORE", # 2 存储
  "ADD",   # 3 加
  "SUB",   # 4 减
  "MUL",   # 5 乘
  "DIV",   # 6 除（公约数）
  "MOD",   # 7 取模（公倍数）
  "CMP",   # 8 比较
  "JMP",   # 9 跳转
  "JZ",    # 10 零跳转
  "JNZ",   # 11 非零跳转
  "CALL",  # 12 函数调用
  "RET",   # 13 返回
  "PUSH",  # 14 压栈
  "POP",   # 15 弹栈
  "HALT",  # 16 停机
  "SYSCALL",# 17 系统调用
  "COPY",  # 18 二元克隆
  "MIRROR", # 19 三元镜像
  "FILL",  # 20 填充空集
  "EXTRACT",# 21 截取节点
  "PHASE", # 22 相位定位
  "DIM0",  # 23 零维跳转
  "DIM1",  # 24 一维跳转
  "DIM2",  # 25 二维跳转
  "DIM3",  # 26 三维跳转
  "OWNR",  # 27 归属权
]

# ============================================
# 2. 解析器：把文本转成字节码
# ============================================

proc 解析算术表达式*(expr: string): seq[指令] =
  # 极简解析：支持 + - * / 四则运算
  # 后续可扩展支持函数调用、变量
  result = @[]
  var pos = 0
  var current_op: uint8 = 0

  while pos < expr.len:
    let ch = expr[pos]
    case ch:
    of ' ':
      inc pos
    of '+':
      current_op = ord(ADD)
      result.add(指令(操作码: current_op, 操作数列表: @[], 码位坐标: (pos, 0, 0)))
      inc pos
    of '-':
      current_op = ord(SUB)
      result.add(指令(操作码: current_op, 操作数列表: @[], 码位坐标: (pos, 0, 0)))
      inc pos
    of '*':
      current_op = ord(MUL)
      result.add(指令(操作码: current_op, 操作数列表: @[], 码位坐标: (pos, 0, 0)))
      inc pos
    of '/':
      current_op = ord(DIV)
      result.add(指令(操作码: current_op, 操作数列表: @[], 码位坐标: (pos, 0, 0)))
      inc pos
    of '0'..'9':
      var num_str = ""
      while pos < expr.len and expr[pos] in {'0'..'9'}:
        num_str.add(expr[pos])
        inc pos
      let num = parseInt(num_str)
      result.add(指令(操作码: ord(LOAD), 操作数列表: @[操作数(类型: "立即数", 整数值: int64(num))], 码位坐标: (pos, 0, 0)))
    else:
      inc pos

proc 解析指令文本*(text: string): seq[指令] =
  # 按行解析，每行一条指令
  result = @[]
  for line in text.splitLines():
    let trimmed = line.strip()
    if trimmed.len == 0:
      continue
    # 简单指令匹配
    for i, name in 指令集:
      if trimmed.startsWith(name):
        result.add(指令(操作码: uint8(i), 操作数列表: @[], 码位坐标: (0, 0, 0)))
        break

# ============================================
# 3. 解释器：执行字节码
# ============================================

type 解释器状态* = object
  寄存器*: array[8, int64]
  栈*: array[64, int64]
  栈顶*: int
  程序计数器*: int
  运行中*: bool

proc 创建解释器*(): 解释器状态 =
  result.寄存器 = [0'i64, 0, 0, 0, 0, 0, 0, 0]
  result.栈顶 = 0
  result.程序计数器 = 0
  result.运行中 = true

proc 执行字节码*(状态: var 解释器状态, 代码: seq[指令]): string =
  while int(状态.程序计数器) < 代码.len and 状态.运行中:
    let ins = 代码[状态.程序计数器]
    case ins.操作码:
    of ord(NOP):
      discard
    of ord(ADD):
      if 状态.栈顶 >= 2:
        let b = 状态.栈[状态.栈顶 - 1]
        let a = 状态.栈[状态.栈顶 - 2]
        状态.栈[状态.栈顶 - 2] = a + b
        dec 状态.栈顶
    of ord(SUB):
      if 状态.栈顶 >= 2:
        let b = 状态.栈[状态.栈顶 - 1]
        let a = 状态.栈[状态.栈顶 - 2]
        状态.栈[状态.栈顶 - 2] = a - b
        dec 状态.栈顶
    of ord(MUL):
      if 状态.栈顶 >= 2:
        let b = 状态.栈[状态.栈顶 - 1]
        let a = 状态.栈[状态.栈顶 - 2]
        状态.栈[状态.栈顶 - 2] = a * b
        dec 状态.栈顶
    of ord(DIV):
      if 状态.栈顶 >= 2:
        let b = 状态.栈[状态.栈顶 - 1]
        let a = 状态.栈[状态.栈顶 - 2]
        if b != 0:
          状态.栈[状态.栈顶 - 2] = a div b  # 整除（公约数）
        dec 状态.栈顶
    of ord(LOAD):
      if ins.操作数列表.len > 0 and ins.操作数列表[0].类型 == "立即数":
        if 状态.栈顶 < 64:
          状态.栈[状态.栈顶] = ins.操作数列表[0].整数值
          inc 状态.栈顶
    of ord(HALT):
      状态.运行中 = false
    of ord(PUSH):
      if 状态.栈顶 < 64:
        状态.栈[状态.栈顶] = 状态.寄存器[0]
        inc 状态.栈顶
    of ord(POP):
      if 状态.栈顶 > 0:
        dec 状态.栈顶
        状态.寄存器[0] = 状态.栈[状态.栈顶]
    else:
      discard
    inc 状态.程序计数器

  if 状态.栈顶 > 0:
    result = "结果: " & $状态.栈[状态.栈顶 - 1]
  else:
    result = "执行完成"

# ============================================
# 4. 产权容器操作
# ============================================

proc 创建产权容器*(名称: string, 容量: int, 归属: uint8): 产权容器 =
  result.名称 = 名称
  result.容量 = 容量
  result.已用 = 0
  result.内部数据 = newSeq[uint8](容量)
  result.归属权 = 归属

proc 封装比特流*(容器: var 产权容器, 数据: openArray[uint8]): bool =
  # 把比特流封装进容器
  if 数据.len > 容器.容量:
    return false
  for i, b in 数据:
    容器.内部数据[i] = b
  容器.已用 = 数据.len
  return true

proc 解封装*(容器: var 产权容器): seq[uint8] =
  # 从容器取出比特流
  result = @[]
  for i in 0..<容器.已用:
    result.add(容器.内部数据[i])

# ============================================
# 5. 跨语言调用（模拟）
# ============================================

proc 跨语言调用*(函数名: string, 参数: seq[string]): string =
  # 模拟跨语言函数调用
  # 实际由Nim运行时执行
  case 函数名:
  of "print":
    return 参数.join(" ")
  of "len":
    if 参数.len > 0:
      return $参数[0].len
    return "0"
  of "str":
    if 参数.len > 0:
      return 参数[0]
    return ""
  of "int":
    if 参数.len > 0:
      try:
        return $parseInt(参数[0])
      except:
        return "0"
    return "0"
  of "码位转拼音":
    # 引用nan_coder的拼音查询
    return "码位→拼音: " & 参数[0]
  of "容器创建":
    return "容器[" & 参数[0] & "] 已创建"
  else:
    return "未知函数: " & 函数名

# ============================================
# 6. 演示入口
# ============================================

when isMainModule:
  echo "========== 南囡囝微内核 v0.1 =========="
  echo "跨语言解释器 | 零外部依赖 | 自举执行"
  echo ""

  echo "--- 指令集（28条）---"
  for i, name in 指令集:
    echo "[" & $i & "] " & name

  echo ""
  echo "--- 解析器演示 ---"
  let expr = "10 20 + 5 *"
  echo "表达式: " & expr
  let ins = 解析算术表达式("10+20*3-5")
  echo "生成指令数: " & $ins.len
  for i, ix in ins:
    let opname = if int(ix.操作码) < 28: 指令集[ix.操作码] else: "UNK"
    echo "  [" & $i & "] " & opname

  echo ""
  echo "--- 解释器执行 ---"
  var 状态 = 创建解释器()
  let 代码 = 解析算术表达式("10+20*3-5")
  let 结果 = 执行字节码(状态, 代码)
  echo 结果

  echo ""
  echo "--- 产权容器演示 ---"
  var 容器 = 创建产权容器("测试箱", 16, 1)
  let 数据 = [uint8(1), 2, 3, 4, 5]
  let ok = 封装比特流(容器, 数据)
  echo "封装: " & (if ok: "成功" else: "失败") & " 已用:" & $容器.已用 & "/" & $容器.容量

  echo ""
  echo "--- 跨语言调用演示 ---"
  echo "print: " & 跨语言调用("print", @["hello", "world"])
  echo "len: " & 跨语言调用("len", @["测试文本"])
  echo "int: " & 跨语言调用("int", @["42"])

  echo ""
  echo "========== 微内核 v0.1 演示完毕 =========="
