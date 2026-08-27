# nan_mirror.nim - 镜像对比逻辑引擎
# 版本：v0.1
# 用途：解决"对比后怎么解决问题"的思路
# 原理：镜像 = 参照系对称，对比 = 找偏差轴

# ============================================================
# 镜像对比的核心概念
# ============================================================
# 
# 镜像对比不是"是/否"判断，而是：
# 1. 找到对称轴（参照系）
# 2. 判断哪些点在这个轴上对齐
# 3. 计算偏离的方向和幅度
# 4. 找到弥合偏离的路径
#
# 正负迭代对比图的结构：
#   正向迭代 → ← 负向迭代
#      ↓           ↓
#   行动链     反思链
#      ↓           ↓
#      → → 交汇点 ← ←
#      （共识或冲突区域）
#
# ============================================================

# 镜像类型定义
type
  MirrorType* = enum
    mtNone = "无镜像"
    mtSpatial = "空间镜像"    # 左右/上下对称
    mtTemporal = "时间镜像"    # 过去=未来
    mtRelational = "关系镜像"  # A→B = B→A
    mtPositive = "正负镜像"   # 正向=负向
    mtDynamic = "动态镜像"    # 过程=逆过程
  
  MirrorAxis* = object
    dimension*: int           # 轴所在维度（0=声母,1=韵母,2=偏旁...）
    direction*: int           # 轴的方向（1=正向,-1=负向）
    position*: int           # 轴的位置（容器内的码位）
  
  MirrorPoint* = object
    source*: int              # 原始码位
    mirror*: int              # 镜像码位
    distance*: int            # 到轴的距离
    aligned*: bool            # 是否对齐
  
  MirrorContrast* = object
    axis*: MirrorAxis         # 对称轴
    positiveSide*: seq[int]   # 正向侧成员
    negativeSide*: seq[int]   # 负向侧成员
    alignedPoints*: seq[MirrorPoint]  # 对齐点
    deviationPoints*: seq[MirrorPoint] # 偏离点
  
  IterationNode* = object
    step*: int                # 第几步
    content*: string          # 内容描述
    positiveAction*: string   # 正向行动
    negativeReflection*: string  # 负向反思
    convergence*: float        # 收敛度（0-1）
  
  IterationGraph* = object
    nodes*: seq[IterationNode]  # 迭代节点序列
    positiveTrack*: seq[int]     # 正向迭代路径
    negativeTrack*: seq[int]     # 负向迭代路径
    meetingPoints*: seq[int]     # 交汇点索引

# ============================================================
# 预加载镜像索引表（零维符号，运行时只查表不生成）
# ============================================================

const
  # 镜像轴定义（声母容器内的对称轴）
  MIRROR_AXIS_SHENGMU*: array[23, MirrorAxis] = [
    # 声母23个，分成11+1+11对称
    # b:p  m:f  d:t  g:k  h:q  j:zh  x:sh  r:r  l:l  n:n  y:y
    # 轴在中间位置
    MirrorAxis(dimension: 0, direction: -1, position: 11),  # b-p轴
    MirrorAxis(dimension: 0, direction: 1, position: 11),   # p-b轴
    MirrorAxis(dimension: 0, direction: -1, position: 10),  # m-f轴
    MirrorAxis(dimension: 0, direction: 1, position: 10),  # f-m轴
    MirrorAxis(dimension: 0, direction: -1, position: 9),  # d-t轴
    MirrorAxis(dimension: 0, direction: 1, position: 9),    # t-d轴
    MirrorAxis(dimension: 0, direction: -1, position: 8),  # g-k轴
    MirrorAxis(dimension: 0, direction: 1, position: 8),    # k-g轴
    MirrorAxis(dimension: 0, direction: -1, position: 7),  # h-q轴
    MirrorAxis(dimension: 0, direction: 1, position: 7),   # q-h轴
    MirrorAxis(dimension: 0, direction: -1, position: 6),  # j-zh轴
    MirrorAxis(dimension: 0, direction: 1, position: 6),   # zh-j轴
    MirrorAxis(dimension: 0, direction: -1, position: 5),  # x-sh轴
    MirrorAxis(dimension: 0, direction: 1, position: 5),   # sh-x轴
    MirrorAxis(dimension: 0, direction: -1, position: 4),  # r-r轴（自身对称）
    MirrorAxis(dimension: 0, direction: -1, position: 3),  # l-l轴（自身对称）
    MirrorAxis(dimension: 0, direction: -1, position: 2),  # n-n轴（自身对称）
    MirrorAxis(dimension: 0, direction: -1, position: 1),  # y-y轴（自身对称）
    MirrorAxis(dimension: 0, direction: -1, position: 0),  # 零声母轴
    MirrorAxis(dimension: 0, direction: 0, position: 11),   # 中心轴
    MirrorAxis(dimension: 0, direction: 0, position: 10),
    MirrorAxis(dimension: 0, direction: 0, position: 9),
    MirrorAxis(dimension: 0, direction: 0, position: 8),
    MirrorAxis(dimension: 0, direction: 0, position: 7)
  ]
  
  # 韵母容器内的镜像轴（37个韵母的对称分布）
  MIRROR_AXIS_YUNMU*: array[37, MirrorAxis] = [
    # a o e i u ü ai ei ao ou ia ie ua uo...
    # 按开口度对称：a(最大) < o < e < i(最小)
    MirrorAxis(dimension: 1, direction: -1, position: 18),  # a-ia轴
    MirrorAxis(dimension: 1, direction: 1, position: 18),  # ia-a轴
    MirrorAxis(dimension: 1, direction: -1, position: 17),  # o-uo轴
    MirrorAxis(dimension: 1, direction: 1, position: 17),  # uo-o轴
    MirrorAxis(dimension: 1, direction: -1, position: 16),  # e-ie轴
    MirrorAxis(dimension: 1, direction: 1, position: 16),  # ie-e轴
    MirrorAxis(dimension: 1, direction: -1, position: 15),  # i-ü轴
    MirrorAxis(dimension: 1, direction: 1, position: 15),  # ü-i轴
    MirrorAxis(dimension: 1, direction: -1, position: 14),  # ai-ua轴
    MirrorAxis(dimension: 1, direction: 1, position: 14),  # ua-ai轴
    MirrorAxis(dimension: 1, direction: -1, position: 13),  # ei-ui轴
    MirrorAxis(dimension: 1, direction: 1, position: 13),  # ui-ei轴
    MirrorAxis(dimension: 1, direction: -1, position: 12),  # ao-ou轴
    MirrorAxis(dimension: 1, direction: 1, position: 12),  # ou-ao轴
    MirrorAxis(dimension: 1, direction: -1, position: 11),  # an-en轴
    MirrorAxis(dimension: 1, direction: 1, position: 11),  # en-an轴
    MirrorAxis(dimension: 1, direction: -1, position: 10),  # ang-eng轴
    MirrorAxis(dimension: 1, direction: 1, position: 10),  # eng-ang轴
    MirrorAxis(dimension: 1, direction: -1, position: 9),  # ian-uen轴
    MirrorAxis(dimension: 1, direction: 1, position: 9),   # uen-ian轴
    MirrorAxis(dimension: 1, direction: -1, position: 8),  # iang-ueng轴
    MirrorAxis(dimension: 1, direction: 1, position: 8),   # ueng-iang轴
    MirrorAxis(dimension: 1, direction: -1, position: 7),  # uan-ün轴
    MirrorAxis(dimension: 1, direction: 1, position: 7),   # ün-uan轴
    MirrorAxis(dimension: 1, direction: -1, position: 6),  # iou-uei轴
    MirrorAxis(dimension: 1, direction: 1, position: 6),   # uei-iou轴
    MirrorAxis(dimension: 1, direction: 0, position: 12),  # 中心轴
    MirrorAxis(dimension: 1, direction: 0, position: 11),
    MirrorAxis(dimension: 1, direction: 0, position: 10),
    MirrorAxis(dimension: 1, direction: 0, position: 9),
    MirrorAxis(dimension: 1, direction: 0, position: 8),
    MirrorAxis(dimension: 1, direction: 0, position: 7),
    MirrorAxis(dimension: 1, direction: 0, position: 6),
    MirrorAxis(dimension: 1, direction: 0, position: 5),
    MirrorAxis(dimension: 1, direction: 0, position: 4),
    MirrorAxis(dimension: 1, direction: 0, position: 3),
    MirrorAxis(dimension: 1, direction: 0, position: 2),
    MirrorAxis(dimension: 1, direction: 0, position: 1),
    MirrorAxis(dimension: 1, direction: 0, position: 0)
  ]
  
  # 偏旁容器内的镜像轴（20个常用偏旁）
  MIRROR_AXIS_PIANBANG*: array[20, MirrorAxis] = [
    # 左右对称：亻彳忄扌氵...
    MirrorAxis(dimension: 2, direction: -1, position: 9),   # 亻-亻轴
    MirrorAxis(dimension: 2, direction: 1, position: 9),    # 亻自身对称
    MirrorAxis(dimension: 2, direction: -1, position: 8),  # 彳-彳轴
    MirrorAxis(dimension: 2, direction: 1, position: 8),    # 彳自身对称
    MirrorAxis(dimension: 2, direction: -1, position: 7),  # 忄-忄轴
    MirrorAxis(dimension: 2, direction: 1, position: 7),    # 忄自身对称
    MirrorAxis(dimension: 2, direction: -1, position: 6),  # 扌-礻轴
    MirrorAxis(dimension: 2, direction: 1, position: 6),   # 礻-扌轴
    MirrorAxis(dimension: 2, direction: -1, position: 5),  # 氵-氺轴
    MirrorAxis(dimension: 2, direction: 1, position: 5),   # 氺-氵轴
    MirrorAxis(dimension: 2, direction: -1, position: 4),  # 火-灬轴
    MirrorAxis(dimension: 2, direction: 1, position: 4),   # 灬-火轴
    MirrorAxis(dimension: 2, direction: -1, position: 3),  # 土-垚轴
    MirrorAxis(dimension: 2, direction: 1, position: 3),   # 垚-土轴
    MirrorAxis(dimension: 2, direction: -1, position: 2),  # 口-囗轴
    MirrorAxis(dimension: 2, direction: 1, position: 2),   # 囗-口轴
    MirrorAxis(dimension: 2, direction: -1, position: 1),  # 日-曰轴
    MirrorAxis(dimension: 2, direction: 1, position: 1),   # 曰-日轴
    MirrorAxis(dimension: 2, direction: -1, position: 0),  # 月-肉轴
    MirrorAxis(dimension: 2, direction: 1, position: 0)    # 肉-月轴
  ]

# ============================================================
# 核心函数：镜像码位计算
# ============================================================

proc computeMirrorCode*(sourceCode: int, axis: MirrorAxis): int =
  ## 计算sourceCode在给定轴上的镜像码位
  ## 公式：mirror = 2 * axis_position - sourceCode
  result = 2 * axis.position - sourceCode

proc computeMirrorPoint*(sourceCode: int, axis: MirrorAxis): MirrorPoint =
  ## 计算镜像点完整信息
  result.source = sourceCode
  result.mirror = computeMirrorCode(sourceCode, axis)
  result.distance = abs(sourceCode - axis.position)
  result.aligned = (result.distance == 0)

# ============================================================
# 核心函数：对比两个列表的镜像对齐度
# ============================================================

proc contrastMirror*(
  positiveList: seq[int],
  negativeList: seq[int],
  axis: MirrorAxis
): MirrorContrast =
  ## 对比正向列表和负向列表的镜像对齐度
  result.axis = axis
  result.positiveSide = positiveList
  result.negativeSide = negativeList
  
  # 计算每个正向码位的镜像
  for posCode in positiveList:
    let mirrorPoint = computeMirrorPoint(posCode, axis)
    if mirrorPoint.mirror in negativeList:
      # 对齐点：在负向列表中找到了镜像
      result.alignedPoints.add(mirrorPoint)
    else:
      # 偏离点：镜像不在负向列表中
      result.deviationPoints.add(mirrorPoint)

proc computeAlignmentRate*(contrast: MirrorContrast): float =
  ## 计算对齐率（0-1）
  let totalPoints = contrast.alignedPoints.len + contrast.deviationPoints.len
  if totalPoints == 0:
    return 0.0
  return float(contrast.alignedPoints.len) / float(totalPoints)

# ============================================================
# 核心函数：正负迭代对比图
# ============================================================

proc addPositiveNode*(
  graph: var IterationGraph,
  action: string,
  content: string
): int =
  ## 添加正向迭代节点
  let node = IterationNode(
    step: graph.nodes.len,
    content: content,
    positiveAction: action,
    negativeReflection: "",
    convergence: 0.0
  )
  graph.nodes.add(node)
  graph.positiveTrack.add(node.step)
  return node.step

proc addNegativeNode*(
  graph: var IterationGraph,
  reflection: string,
  content: string
): int =
  ## 添加负向迭代节点
  let node = IterationNode(
    step: graph.nodes.len,
    content: content,
    positiveAction: "",
    negativeReflection: reflection,
    convergence: 0.0
  )
  graph.nodes.add(node)
  graph.negativeTrack.add(node.step)
  return node.step

proc addMeetingPoint*(graph: var IterationGraph, nodeIndex: int) =
  ## 添加交汇点（共识或冲突区域）
  graph.meetingPoints.add(nodeIndex)

proc computeConvergence*(
  graph: var IterationGraph,
  positiveTrack: seq[int],
  negativeTrack: seq[int]
): float =
  ## 计算正向和负向轨迹的收敛度
  if positiveTrack.len == 0 or negativeTrack.len == 0:
    return 0.0
  
  # 找到最近的交汇点
  var minDistance = high(int)
  for pStep in positiveTrack:
    for nStep in negativeTrack:
      let distance = abs(pStep - nStep)
      if distance < minDistance:
        minDistance = distance
  
  # 收敛度 = 1 / (1 + distance)
  result = 1.0 / float(1 + minDistance)

# ============================================================
# 高级函数：弥合裂缝的路径
# ============================================================

proc findBridgePath*(
  deviationPoints: seq[MirrorPoint],
  positiveList: seq[int],
  negativeList: seq[int]
): seq[int] =
  ## 找到弥合偏离的桥梁路径
  ## 原理：从偏离点出发，找一个中间点连接到对方列表
  
  var bridgePath: seq[int]
  
  for devPoint in deviationPoints:
    # 计算偏离方向
    let direction = if devPoint.source > devPoint.mirror then 1 else -1
    
    # 从偏离点向轴移动，每次移动半个单位
    var currentPos = devPoint.source
    let halfStep = devPoint.distance div 2
    
    for i in 1..halfStep:
      currentPos = currentPos - direction
      if currentPos notin bridgePath:
        bridgePath.add(currentPos)
    
    # 添加交汇点
    if devPoint.distance > 0:
      let midPoint = (devPoint.source + devPoint.mirror) div 2
      if midPoint notin bridgePath:
        bridgePath.add(midPoint)
  
  return bridgePath

proc traceCrackFillProcess*(
  graph: var IterationGraph,
  positiveList: seq[int],
  negativeList: seq[int],
  axis: MirrorAxis
): string =
  ## 追踪弥合裂缝的过程
  var result = "弥合裂缝过程追踪：\n"
  
  # 第一步：对比分析
  let contrast = contrastMirror(positiveList, negativeList, axis)
  result &= "1. 镜像对比分析\n"
  result &= "   - 对齐点数量：" & $contrast.alignedPoints.len & "\n"
  result &= "   - 偏离点数量：" & $contrast.deviationPoints.len & "\n"
  result &= "   - 对齐率：" & $computeAlignmentRate(contrast) & "\n"
  
  # 第二步：找桥梁
  let bridgePath = findBridgePath(contrast.deviationPoints, positiveList, negativeList)
  result &= "2. 桥梁路径\n"
  result &= "   - 桥梁节点：" & $bridgePath & "\n"
  
  # 第三步：迭代收敛
  for step, bridgeNode in bridgePath:
    let nodeIndex = graph.addPositiveNode(
      "桥接偏离点" & $step,
      "第" & $step & "步桥接"
    )
    graph.addMeetingPoint(nodeIndex)
  
  result &= "3. 迭代收敛\n"
  result &= "   - 交汇点：" & $graph.meetingPoints & "\n"
  result &= "   - 收敛度：" & $computeConvergence(graph, graph.positiveTrack, graph.negativeTrack) & "\n"
  
  return result

# ============================================================
# 解决方案分类器：判断是哪类问题
# ============================================================

type
  SolutionType* = enum
    stSpatial = "空间变化方案"      # 位置移动、形状变换
    stTemporal = "时间变化方案"      # 时序调整、版本回溯
    stRelational = "关系变化方案"    # 连接重构、关系重配
    stPositive = "正负变化方案"      # 正负对调、镜像翻转
    stDynamic = "动态交互方案"       # 迭代反馈、迂回调整

proc classifySolutionType*(
  contrast: MirrorContrast
): SolutionType =
  ## 根据镜像对比结果判断解决方案类型
  let alignmentRate = computeAlignmentRate(contrast)
  
  if alignmentRate > 0.8:
    # 高对齐率 = 空间微调
    return stSpatial
  elif alignmentRate > 0.5:
    # 中对齐率 = 需要关系重构
    return stRelational
  elif contrast.deviationPoints.len > 0:
    # 有偏离点 = 需要正负对调
    return stPositive
  else:
    # 低对齐率 = 需要动态迭代
    return stDynamic

# ============================================================
# 零维符号接口：只查表，不运行时生成
# ============================================================

proc getMirrorAxisList*(dimension: int): seq[MirrorAxis] =
  ## 获取指定维度的镜像轴列表（零维查表）
  case dimension:
  of 0:
    result = @MIRROR_AXIS_SHENGMU
  of 1:
    result = @MIRROR_AXIS_YUNMU
  of 2:
    result = @MIRROR_AXIS_PIANBANG
  else:
    discard

proc findBestAxis*(
  positiveList: seq[int],
  negativeList: seq[int]
): MirrorAxis =
  ## 找到最优镜像轴（对齐率最高的轴）
  var bestAxis: MirrorAxis
  var bestRate = 0.0
  
  # 检查所有维度
  for dim in 0..2:
    for axis in getMirrorAxisList(dim):
      let contrast = contrastMirror(positiveList, negativeList, axis)
      let rate = computeAlignmentRate(contrast)
      if rate > bestRate:
        bestRate = rate
        bestAxis = axis
  
  return bestAxis
