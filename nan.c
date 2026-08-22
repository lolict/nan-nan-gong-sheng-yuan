/* ============================================================================
 * nan.c — 南囡囝共生元·最小解释器 v0.1
 * ----------------------------------------------------------------------------
 * 编译:  gcc -O2 -o nan nan.c   (只需要 libc，无其他依赖)
 * 用途:  读取 .nan 文件，用你自己的编码体系执行
 * 原理:  自举第一步 — 用最小C解释器启动你自己的规则体系
 *        以后用 nan 写的解释器来重写 nan.c，C 就消失了
 * ===========================================================================*/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <math.h>

/* ============================================================================
 * 南囡囝共生元·绝对定位编码表
 * ----------------------------------------------------------------------------
 * 绝对三维空间定位，用汉字方向词组合
 * 格式: x(东西) + y(南北) + z(天地) = 绝对坐标
 * ===========================================================================*/

typedef struct {
    int x, y, z;       /* 绝对坐标: x=东正西负, y=南正北负, z=天正地负 */
} AbsPos;

typedef struct {
    int8_t u, d, l, r, f, b;  /* 相对定位: 上下左右前后 */
} RelPos;

typedef struct {
    int8_t x, y, z;   /* 体素偏移: 相对于身体中心 */
    char name[32];     /* 部位名 */
} BodyPos;

/* 绝对定位表（预加载完毕） */
static const char* ABS_X[3] = {"西", "中", "东"};
static const char* ABS_Y[3] = {"南", "中", "北"};
static const char* ABS_Z[3] = {"地", "中", "天"};

/* 相对定位表 */
static const char* REL_DIRS[6] = {"上", "下", "左", "右", "前", "后"};

/* 体素定位表（本体论定位） */
static const char BODY_PARTS[][16] = {
    /* 头 */    "头顶","头前","头后","头左","头右",
    /* 肩 */    "左肩","右肩",
    /* 胸 */    "前胸","后胸","左胸","右胸",
    /* 腰 */    "前腰","后腰","左腰","右腰",
    /* 胯 */    "前胯","后胯",
    /* 腿 */    "左腿","右腿","左膝","右膝","左脚","右脚",
    /* 臂 */    "左臂","右臂","左手","右手",
    /* 背 */    "左背","右背"
};

/* ============================================================================
 * 三维棋子（移动模式）
 * ----------------------------------------------------------------------------
 * 每个棋子的移动模式 = 一个移动向量集合
 * 骑士=跳马, 战车=跳车, 主教=跳象, 炮=跳炮, 王=周围一圈
 * ===========================================================================*/

typedef struct {
    char name[16];      /* 棋子名: 兵/马/车/象/后/王 */
    int vec_count;       /* 移动向量数 */
    int8_t vecs[8][3]; /* 每个向量的 (x,y,z) 偏移 */
} PieceType;

static PieceType PIECES[] = {
    {"王",  26, {  /* 周围一圈 3×3×3 - 中心 */
        -1,-1,-1, -1,-1,0, -1,-1,1,
        -1,0,-1,  -1,0,0,  -1,0,1,
        -1,1,-1,  -1,1,0,  -1,1,1,
        0,-1,-1,   0,-1,0,   0,-1,1,
        0,0,-1,               0,0,1,
        0,1,-1,    0,1,0,    0,1,1,
        1,-1,-1,   1,-1,0,   1,-1,1,
        1,0,-1,    1,0,0,    1,0,1,
        1,1,-1,    1,1,0,    1,1,1
    }},
    {"后",  49, {  /* 全方向射线（王的所有方向无限延伸） */
        -2,-2,-2,-2,-2,-1,-2,-2,0,-2,-2,1,-2,-2,2,
        -2,-1,-2,-2,-1,-1,-2,-1,0,-2,-1,1,-2,-1,2,
        -2,0,-2,-2,0,-1,-2,0,0,-2,0,1,-2,0,2,
        -2,1,-2,-2,1,-1,-2,1,0,-2,1,1,-2,1,2,
        -2,2,-2,-2,2,-1,-2,2,0,-2,2,1,-2,2,2,
        -1,-2,-2,-1,-2,-1,-1,-2,0,-1,-2,1,-1,-2,2,
        -1,-1,-2,-1,-1,-1,-1,-1,0,-1,-1,1,-1,-1,2,
        -1,0,-2,-1,0,-1,-1,0,0,-1,0,1,-1,0,2,
        -1,1,-2,-1,1,-1,-1,1,0,-1,1,1,-1,1,2,
        -1,2,-2,-1,2,-1,-1,2,0,-1,2,1,-1,2,2,
        0,-2,-2, 0,-2,-1, 0,-2,0, 0,-2,1, 0,-2,2,
        0,-1,-2, 0,-1,-1, 0,-1,0, 0,-1,1, 0,-1,2,
        0,0,-2,             0,0,2,
        0,1,-2, 0,1,-1, 0,1,0, 0,1,1, 0,1,2,
        0,2,-2, 0,2,-1, 0,2,0, 0,2,1, 0,2,2,
        1,-2,-2, 1,-2,-1, 1,-2,0, 1,-2,1, 1,-2,2,
        1,-1,-2, 1,-1,-1, 1,-1,0, 1,-1,1, 1,-1,2,
        1,0,-2,  1,0,-1,  1,0,0,  1,0,1,  1,0,2,
        1,1,-2,  1,1,-1,  1,1,0,  1,1,1,  1,1,2,
        1,2,-2,  1,2,-1,  1,2,0,  1,2,1,  1,2,2
    }},
    {"车",  7, {  /* 十字射线（前后左右上下直线） */
        -2,0,0,  2,0,0,  0,-2,0,  0,2,0,  0,0,-2,  0,0,2
    }},
    {"象",  7, {  /* 对角射线（8条空间对角线） */
        -2,-2,-2, 2,2,2,  -2,-2,2, 2,2,-2,
        -2,2,-2,  2,-2,2,  -2,2,2,  2,-2,-2
    }},
    {"马",  8, {  /* 跳马（L形三维） */
        -1,-2,-2, -1,-2,2,  -1,2,-2, -1,2,2,
         1,-2,-2,  1,-2,2,   1,2,-2,  1,2,2
    }},
    {"炮",  7, {  /* 跳炮（隔一格吃子） */
        -2,0,0,  2,0,0,  0,-2,0,  0,2,0,  0,0,-2,  0,0,2
    }}
};
static int PIECE_COUNT = sizeof(PIECES) / sizeof(PieceType);

/* ============================================================================
 * 产权容器
 * ----------------------------------------------------------------------------
 * 产权容器 = 归某个所有者管辖的三维空间
 * 所有者 0=刘楚恬, 1=接接接
 * ===========================================================================*/

typedef struct {
    int owner;           /* 0=刘楚恬, 1=接接接 */
    int x1,y1,z1;       /* 边界起点 */
    int x2,y2,z2;       /* 边界终点 */
    char content[256];   /* 容器内容 */
} PropertyContainer;

/* ============================================================================
 * 解释器状态
 * ----------------------------------------------------------------------------
 * 当前坐标, 所有者, 产权容器列表
 * ===========================================================================*/

static AbsPos cur_abs = {0,0,0};     /* 当前位置 */
static RelPos cur_rel = {0,0,0,0,0,0};  /* 当前相对坐标 */
static int cur_owner = 1;             /* 默认我是内容=1 */
static PropertyContainer containers[256];
static int container_count = 0;

/* ============================================================================
 * 核心操作函数
 * ===========================================================================*/

static void move_abs(int x, int y, int z) {
    cur_abs.x = x; cur_abs.y = y; cur_abs.z = z;
    printf("  [移动] → 东%+d 南%+d 天%+d\n", x, y, z);
}

static void move_rel(int u, int d, int l, int r, int f, int b) {
    cur_rel.u = u; cur_rel.d = d;
    cur_rel.l = l; cur_rel.r = r;
    cur_rel.f = f; cur_rel.b = b;
    printf("  [移动] → 上%d 下%d 左%d 右%d 前%d 后%d\n", u, d, l, r, f, b);
}

static void claim_property(int x1, int y1, int z1, int x2, int y2, int z2, int owner, const char *content) {
    if (container_count >= 256) { printf("  [产权] 容器已满\n"); return; }
    PropertyContainer *c = &containers[container_count++];
    c->owner = owner;
    c->x1 = x1; c->y1 = y1; c->z1 = z1;
    c->x2 = x2; c->y2 = y2; c->z2 = z2;
    if (content) strncpy(c->content, content, 255);
    else c->content[0] = 0;
    printf("  [产权] claim #%d: 东[%d,%d] 南[%d,%d] 天[%d,%d] → %s\n",
        container_count-1, x1,x2, y1,y2, z1,z2,
        owner==0?"刘楚恬":"接接接");
}

static void bind_to_cell(int x, int y, int z, int owner) {
    printf("  [绑定] 坐标(东%+d,南%+d,天%+d) → %s\n",
        x, y, z, owner==0?"刘楚恬":"接接接");
}

static void piece_move(const char *piece, int x, int y, int z) {
    for (int i = 0; i < PIECE_COUNT; i++) {
        if (strcmp(PIECES[i].name, piece) == 0) {
            printf("  [棋子移动] %s 移动: 从(东%+d,南%+d,天%+d)\n", piece, x, y, z);
            printf("  可达方向: %d个\n", PIECES[i].vec_count);
            /* 打印前5个可达方向 */
            for (int v = 0; v < PIECES[i].vec_count && v < 5; v++) {
                printf("    → 东%+d 南%+d 天%+d\n",
                    x + PIECES[i].vecs[v][0],
                    y + PIECES[i].vecs[v][1],
                    z + PIECES[i].vecs[v][2]);
            }
            if (PIECES[i].vec_count > 5) printf("    ... 共%d个方向\n", PIECES[i].vec_count);
            return;
        }
    }
    printf("  [棋子] 未知: %s\n", piece);
}

static void show_pos(void) {
    printf("  [状态] 当前位置: 东%+d 南%+d 天%+d\n", cur_abs.x, cur_abs.y, cur_abs.z);
    printf("  [状态] 相对坐标: 上%+d 下%+d 左%+d 右%+d 前%+d 后%+d\n",
        cur_rel.u, cur_rel.d, cur_rel.l, cur_rel.r, cur_rel.f, cur_rel.b);
    printf("  [状态] 所有者: %s\n", cur_owner==0?"刘楚恬":"接接接");
    printf("  [状态] 产权容器: %d个\n", container_count);
}

static void show_pieces(void) {
    printf("  [棋子] 南囡囝共生元·三维棋子移动规则:\n");
    for (int i = 0; i < PIECE_COUNT; i++) {
        printf("    %s: %d个方向\n", PIECES[i].name, PIECES[i].vec_count);
    }
}

/* ============================================================================
 * .nan 文件解析器
 * ----------------------------------------------------------------------------
 * .nan 文件是纯文本，用你自己的编码词作为指令
 * 格式: 指令 [参数]
 * 行首 # 为注释
 * ===========================================================================*/

static void parse_nan_file(const char *path) {
    FILE *fp = fopen(path, "r");
    if (!fp) { printf("[nan] 无法打开: %s\n", path); return; }
    printf("\n=== 南囡囝共生元·执行 %s ===\n\n", path);

    char line[512];
    int lineno = 0;
    while (fgets(line, sizeof(line), fp)) {
        lineno++;
        /* 去掉换行 */
        size_t len = strlen(line);
        if (len > 0 && line[len-1] == '\n') line[--len] = 0;
        /* 跳过空行和注释 */
        if (len == 0 || line[0] == '#') continue;

        /* 解析指令 */
        char cmd[64] = {0};
        int x=0, y=0, z=0, x2=0, y2=0, z2=0, owner=1;
        char arg[256] = {0};

        /* 绝对定位移动 */
        if (sscanf(line, "东 %d 南 %d 天 %d", &x, &y, &z) == 3) {
            move_abs(x, y, z);
        }
        else if (sscanf(line, "相对 上%d 下%d 左%d 右%d 前%d 后%d", &x, &y, &z, &x2, &y2, &z2) == 6) {
            move_rel(x, y, z, x2, y2, z2);
        }
        else if (strncmp(line, "产权 claim", 9) == 0) {
            /* 格式: 产权 claim 东起点 南起点 天起点 东终点 南终点 天终点 所有者 名称 */
            int p1,p2,p3,p4,p5,p6,po; char name[128];
            if (sscanf(line+9, "%d %d %d %d %d %d %d %s", &p1,&p2,&p3,&p4,&p5,&p6,&po,name) >= 7) {
                claim_property(p1,p2,p3,p4,p5,p6, po, name);
            }
        }
        else if (strncmp(line, "绑定", 4) == 0) {
            if (sscanf(line+4, "%d %d %d %d", &x, &y, &z, &owner) == 4) {
                bind_to_cell(x, y, z, owner);
            }
        }
        else if (strncmp(line, "我是内容", 8) == 0) {
            cur_owner = 1; printf("  [身份] 接接接=内容=1\n");
        }
        else if (strncmp(line, "我是容器", 8) == 0) {
            cur_owner = 0; printf("  [身份] 刘楚恬=容器=0\n");
        }
        else if (strncmp(line, "跳马", 4) == 0) {
            if (sscanf(line+4, "%d %d %d", &x, &y, &z) == 3) piece_move("马", x, y, z);
        }
        else if (strncmp(line, "跳车", 4) == 0) {
            if (sscanf(line+4, "%d %d %d", &x, &y, &z) == 3) piece_move("车", x, y, z);
        }
        else if (strncmp(line, "跳象", 4) == 0) {
            if (sscanf(line+4, "%d %d %d", &x, &y, &z) == 3) piece_move("象", x, y, z);
        }
        else if (strncmp(line, "跳炮", 4) == 0) {
            if (sscanf(line+4, "%d %d %d", &x, &y, &z) == 3) piece_move("炮", x, y, z);
        }
        else if (strncmp(line, "周围", 4) == 0) {
            if (sscanf(line+4, "%d %d %d", &x, &y, &z) == 3) piece_move("王", x, y, z);
        }
        else if (strncmp(line, "全方向", 6) == 0) {
            if (sscanf(line+6, "%d %d %d", &x, &y, &z) == 3) piece_move("后", x, y, z);
        }
        else if (strcmp(line, "状态") == 0) {
            show_pos();
        }
        else if (strcmp(line, "棋子") == 0) {
            show_pieces();
        }
        else if (strcmp(line, "帮助") == 0) {
            printf("  [帮助] nan 解释器指令:\n");
            printf("    东 N 南 N 天 N     绝对定位移动\n");
            printf("    相对 上N 下N...   相对定位移动\n");
            printf("    产权 claim x1 y1 z1 x2 y2 z2 所有者 名称   声明产权容器\n");
            printf("    绑定 X Y Z 所有者  绑定坐标到所有者\n");
            printf("    跳马 X Y Z        跳马移动（3D L形）\n");
            printf("    跳车 X Y Z        跳车移动（十字直线）\n");
            printf("    跳象 X Y Z        跳象移动（对角线）\n");
            printf("    跳炮 X Y Z        跳炮移动（隔格）\n");
            printf("    周围 X Y Z         王移动（周围一圈）\n");
            printf("    全方向 X Y Z       后移动（全方向）\n");
            printf("    我是内容           身份=接接接(1)\n");
            printf("    我是容器           身份=刘楚恬(0)\n");
            printf("    状态               显示当前状态\n");
            printf("    棋子               显示棋子移动规则\n");
            printf("    帮助               本帮助\n");
        }
        else {
            printf("  [行%d] 未知指令: %s\n", lineno, line);
        }
    }
    fclose(fp);
    printf("\n=== 执行完毕 ===\n\n");
}

/* ============================================================================
 * 主入口
 * ===========================================================================*/

int main(int argc, char *argv[]) {
    printf("\n");
    printf("╔══════════════════════════════════════════╗\n");
    printf("║  南囡囝共生元·最小解释器 nan v0.1        ║\n");
    printf("║  自举第一步: 几百行C启动你的规则体系      ║\n");
    printf("║  以后用 nan 写的解释器重写 nan.c,C消失   ║\n");
    printf("╚══════════════════════════════════════════╝\n\n");

    if (argc < 2) {
        printf("用法: nan <程序.nan>\n");
        printf("示例: nan boot.nan\n");
        printf("内置指令: 状态 / 棋子 / 帮助\n");
        printf("\n");
        /* 交互模式 */
        char line[256];
        printf("nan> ");
        while (fgets(line, sizeof(line), stdin)) {
            if (strncmp(line, "nan ", 4) == 0) {
                parse_nan_file(line + 4);
            } else if (strncmp(line, "exit", 4) == 0 || strncmp(line, "quit", 4) == 0) {
                break;
            } else {
                parse_nan_file(line);
            }
            printf("nan> ");
        }
    } else {
        parse_nan_file(argv[1]);
    }
    return 0;
}
