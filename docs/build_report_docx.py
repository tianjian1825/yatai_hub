#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成《2026 年上半年工作汇报讲稿》Word 文档。

内容按用户原文排版，未改写措辞。
运行：/tmp/pptx-venv/bin/python docs/build_report_docx.py
"""

from docx import Document
from docx.shared import Pt, RGBColor, Cm
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_LINE_SPACING
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.oxml.ns import qn
from docx.oxml import OxmlElement

# ── 字体（国内办公场景通用，Win/Mac 均可解析）────────────────────
HEI = "黑体"
SONG = "宋体"
BLUE = RGBColor(0x1F, 0x4E, 0x79)
DARK = RGBColor(0x26, 0x26, 0x26)
GRAY = RGBColor(0x59, 0x59, 0x59)
RED = RGBColor(0xC0, 0x00, 0x00)
ORANGE = RGBColor(0xBF, 0x60, 0x00)


def set_run(run, text=None, font=SONG, size=12, bold=False, color=DARK, italic=False):
    if text is not None:
        run.text = text
    run.font.name = font
    run.font.size = Pt(size)
    run.font.bold = bold
    run.font.italic = italic
    run.font.color.rgb = color
    rPr = run._element.get_or_add_rPr()
    rFonts = rPr.find(qn("w:rFonts"))
    if rFonts is None:
        rFonts = OxmlElement("w:rFonts")
        rPr.append(rFonts)
    rFonts.set(qn("w:eastAsia"), font)
    rFonts.set(qn("w:ascii"), font)
    rFonts.set(qn("w:hAnsi"), font)
    return run


def shade(paragraph, hex_fill):
    """给段落加底纹。"""
    pPr = paragraph._p.get_or_add_pPr()
    shd = OxmlElement("w:shd")
    shd.set(qn("w:val"), "clear")
    shd.set(qn("w:color"), "auto")
    shd.set(qn("w:fill"), hex_fill)
    pPr.append(shd)


def left_border(paragraph, hex_color, size=18):
    """给段落加左侧竖线。"""
    pPr = paragraph._p.get_or_add_pPr()
    bdr = OxmlElement("w:pBdr")
    left = OxmlElement("w:left")
    left.set(qn("w:val"), "single")
    left.set(qn("w:sz"), str(size))
    left.set(qn("w:space"), "8")
    left.set(qn("w:color"), hex_color)
    bdr.append(left)
    pPr.append(bdr)


doc = Document()

# 页面设置：A4 + 常规页边距
sec = doc.sections[0]
sec.page_width, sec.page_height = Cm(21.0), Cm(29.7)
sec.top_margin = sec.bottom_margin = Cm(2.4)
sec.left_margin = sec.right_margin = Cm(2.6)

# 默认样式
st = doc.styles["Normal"]
st.font.name = SONG
st.font.size = Pt(12)
st.element.rPr.rFonts.set(qn("w:eastAsia"), SONG)


def P(text="", font=SONG, size=12, bold=False, color=DARK, align=None,
      space_before=0, space_after=6, line=1.5, indent_first=False, italic=False):
    p = doc.add_paragraph()
    pf = p.paragraph_format
    pf.space_before = Pt(space_before)
    pf.space_after = Pt(space_after)
    pf.line_spacing = line
    if align is not None:
        p.alignment = align
    if indent_first:
        pf.first_line_indent = Pt(size * 2)
    if text:
        set_run(p.add_run(), text, font=font, size=size, bold=bold, color=color,
                italic=italic)
    return p


def H1(text, num=None):
    """章节标题：蓝色 + 左侧竖线。"""
    p = doc.add_paragraph()
    pf = p.paragraph_format
    pf.space_before = Pt(18)
    pf.space_after = Pt(10)
    pf.line_spacing = 1.3
    set_run(p.add_run(), text, font=HEI, size=15, bold=True, color=BLUE)
    left_border(p, "1F4E79", size=24)
    return p


def H2(text):
    p = doc.add_paragraph()
    pf = p.paragraph_format
    pf.space_before = Pt(12)
    pf.space_after = Pt(6)
    pf.line_spacing = 1.35
    set_run(p.add_run(), text, font=HEI, size=13, bold=True, color=DARK)
    return p


def bullet(text, bold_head=None, size=12, color=DARK):
    """项目符号段落；bold_head 为需要加粗的前缀（如「素材协同，」）。"""
    p = doc.add_paragraph()
    pf = p.paragraph_format
    pf.space_before = Pt(0)
    pf.space_after = Pt(6)
    pf.line_spacing = 1.5
    pf.left_indent = Pt(18)
    pf.first_line_indent = Pt(-18)
    set_run(p.add_run(), "● ", font=SONG, size=size, bold=True, color=BLUE)
    if bold_head:
        set_run(p.add_run(), bold_head, font=HEI, size=size, bold=True, color=DARK)
    set_run(p.add_run(), text, font=SONG, size=size, color=color)
    return p


def numbered(idx, text, bold_head=None):
    p = doc.add_paragraph()
    pf = p.paragraph_format
    pf.space_before = Pt(0)
    pf.space_after = Pt(6)
    pf.line_spacing = 1.5
    pf.left_indent = Pt(22)
    pf.first_line_indent = Pt(-22)
    set_run(p.add_run(), f"{idx}. ", font=HEI, size=12, bold=True, color=BLUE)
    if bold_head:
        set_run(p.add_run(), bold_head, font=HEI, size=12, bold=True, color=DARK)
    set_run(p.add_run(), text, font=SONG, size=12, color=DARK)
    return p


def callout(label, text, fill="FFF4E5", bar="BF6000", label_color=ORANGE):
    """提示框：底纹 + 左竖线。"""
    p = doc.add_paragraph()
    pf = p.paragraph_format
    pf.space_before = Pt(6)
    pf.space_after = Pt(10)
    pf.line_spacing = 1.4
    pf.left_indent = Pt(10)
    pf.right_indent = Pt(6)
    set_run(p.add_run(), label, font=HEI, size=11, bold=True, color=label_color)
    set_run(p.add_run(), text, font=SONG, size=11, color=DARK)
    shade(p, fill)
    left_border(p, bar, size=24)
    return p


def hr():
    p = doc.add_paragraph()
    p.paragraph_format.space_before = Pt(10)
    p.paragraph_format.space_after = Pt(10)
    pPr = p._p.get_or_add_pPr()
    bdr = OxmlElement("w:pBdr")
    bot = OxmlElement("w:bottom")
    bot.set(qn("w:val"), "single")
    bot.set(qn("w:sz"), "6")
    bot.set(qn("w:space"), "1")
    bot.set(qn("w:color"), "D9D9D9")
    bdr.append(bot)
    pPr.append(bdr)


# ═══ 封面区 ═════════════════════════════════════════════════════════
P("2026 年上半年工作汇报", font=HEI, size=24, bold=True, color=BLUE,
  align=WD_ALIGN_PARAGRAPH.CENTER, space_before=36, space_after=8, line=1.2)
P("SZST 新质 OA 平台 · 汇报讲稿", font=HEI, size=14, bold=False, color=GRAY,
  align=WD_ALIGN_PARAGRAPH.CENTER, space_after=24, line=1.2)

info = doc.add_table(rows=3, cols=2)
info.alignment = WD_TABLE_ALIGNMENT.CENTER
info.autofit = False
rows = [("汇 报 人", "田健"),
        ("所属部门", "TEG 技术西安事业部 · 西安技术组 · 前端开发"),
        ("统计周期", "2026 年 3 月 1 日 — 8 月 1 日")]
for i, (k, v) in enumerate(rows):
    c0, c1 = info.rows[i].cells
    c0.width, c1.width = Cm(2.8), Cm(11.5)
    p0 = c0.paragraphs[0]
    p0.alignment = WD_ALIGN_PARAGRAPH.RIGHT
    set_run(p0.add_run(), k, font=HEI, size=11, bold=True, color=GRAY)
    p1 = c1.paragraphs[0]
    set_run(p1.add_run(), "　" + v, font=SONG, size=11, color=DARK)
for row in info.rows:
    for cell in row.cells:
        cell.paragraphs[0].paragraph_format.space_after = Pt(4)

hr()

# ═══ 开场 ═══════════════════════════════════════════════════════════
P("尊敬的老大，各位总监、各位同事，大家下午好。", font=SONG, size=12.5,
  space_before=10, space_after=8)
P("今天我汇报下我们组 2026 年上半年的工作汇总情况。", space_after=8)
p = doc.add_paragraph()
p.paragraph_format.line_spacing = 1.5
p.paragraph_format.space_after = Pt(6)
set_run(p.add_run(), "首先看下我们的 SZST 新质 OA 这个 App，最初上线的时候，定位是一个"
                     "素材上传工具 —— 就是大家熟悉的", font=SONG, size=12)
set_run(p.add_run(), "「随心拍」", font=HEI, size=12, bold=True)
set_run(p.add_run(), "，主要就是为了解决钉钉内上传卡顿的问题。到今天，它已经扩展成一个覆盖 ",
        font=SONG, size=12)
set_run(p.add_run(), "素材协同、客户服务、商务管理、兼职调度", font=HEI, size=12,
        bold=True, color=BLUE)
set_run(p.add_run(), " 四条业务线的一体化平台，目前支持 iOS、安卓。", font=SONG, size=12)

# ═══ 一、平台运行数据 ═══════════════════════════════════════════════
H1("一、平台运行数据")
P("先看数据。这一页所有数字都来自 SZST 综合管理系统的数据统计模块，统计周期是今年 3 月 1 日到 8 月 1 日。")
P("其中，最突出的是第一个：随心拍素材上传 2347 次。能有这组数据的主要原因，还是上传速度及"
  "服务有所提升。")
P("创建客户档案 314 份，新建预约 171 次。这两个数据低的原因是这些操作主要集中在佳节日 —— "
  "虽然数据量低，但是解决了节假日大家使用电脑不方便的问题，在 App 上可以快速地进行客户处理。")
P("日活人数 113 人，是平台的活跃使用人数。这个数字还在上升期，因为我们的商务后台也已经"
  "开始投入使用了。")

# ═══ 二、能力全景 ═══════════════════════════════════════════════════
H1("二、五大能力全景")
P("这一页是平台能力的全貌。")
bullet("也就是随心拍。支持 9 类素材分类、11 类归属标签，可见范围分公开、院内、科室内三级，"
       "大文件走分片直传 NAS。", bold_head="素材协同，")
bullet("从建档、预约、排期到派单的完整链路，支持中韩英三语展示。", bold_head="客户服务，")
bullet("医院和合同的全生命周期管理，配 KPI 看板和周报月报。", bold_head="商务管理，")
bullet("从接单、打卡、资料录入到工时结算的闭环，这块待会儿单独展开讲。", bold_head="兼职调度，")
bullet("考勤打卡、加班调休、韩国商务科室事宜审批。", bold_head="组织管理，")
P("〔可略〕这几块不是并列堆出来的，是按业务线长出来的 —— 先有素材，再有客服，然后是商务和"
  "兼职。每一块上线都对应一个真实的业务诉求。", color=GRAY, size=11.5, space_before=4)

# ═══ 三、角色权限体系 ═══════════════════════════════════════════════
H1("三、角色权限体系")
P("这一页我想特别讲一下，因为它是这个平台设计上的一个关键点。")
P("同一个 App，不同岗位登录进去，看到的是完全不同的界面。", font=HEI, bold=True)
P("客服登录，首页是工作台，能看到日程和预约组；商务 BD 登录，首页出现商务 Tab；"
  "兼职人员登录，底部连首页都没有，直接是接单大厅、消息和我的三个入口；"
  "游客不登录，只能浏览公开素材，传不了也参与不了协同。")
P("这么做有两个好处：一是每个岗位打开就是自己的工作界面，不用在无关功能里翻找；"
  "二是数据权限天然隔离 —— 兼职人员看不到客户档案，游客看不到内部素材。")
P("管理员账号则是叠加所有角色标记，可以看到全部模块 —— 后面几页的截图就是用管理员账号截的。")

# ═══ 四、工作台 · 客服业务 ══════════════════════════════════════════
H1("四、工作台 · 客服业务")
P("这是客服登录后的工作台首页。上面是今日需要关注的事项汇总，下面按业务分块：预约这一块，"
  "客服待确认、医院待确认、待上传预约金、预约时间变更、医院拒绝取消、待录单预约，"
  "每一个数字都是可以点进去直接办的，不是看板式的展示。再下面是跟进总览 —— 今日日程、"
  "今日跟进、逾期跟进。")
P("这个设计的核心是「待办驱动」：客服上班打开 App，不需要自己去想今天该干什么，"
  "页面直接告诉他有几件事等着处理。")
P("这是客户管理页。每个客户卡片上有客户 ID、意向等级、意向地区、意向项目、客户来源和注册时间，"
  "底下三个直达按钮：派单、档案、预约。")
P("除了截图上这两块，客服这条线还包括：", space_after=4)
bullet("拍一张护照首页，姓名、生日、护照号自动填进去；", bold_head="建档支持护照 OCR 自动识别 —— ")
bullet("不同医院要填的东西不一样，系统自动匹配；", bold_head="预约表单按医院模板动态生成字段 —— ")
bullet("方便对接韩方；", bold_head="预约详情支持中韩英三语 —— ")
bullet("排期、支付凭证上传、整外手术履历等。", bold_head="其他 —— ")

# ═══ 五、商务 BD 模块 ═══════════════════════════════════════════════
H1("五、商务 BD 模块")
P("这是商务条线的界面。")
H2("运营概览")
P("最上面一行是快捷操作，待审批的数量直接标在上面，包含部长及科长的医院新增重复、BD 变更等"
  "审批事宜。接下来就是数据总览，可以清晰地了解科室及个人的医院运营情况，方便工作计划安排。")
p = doc.add_paragraph()
p.paragraph_format.line_spacing = 1.5
p.paragraph_format.space_after = Pt(6)
set_run(p.add_run(), "三要素", font=HEI, size=12, bold=True, color=BLUE)
set_run(p.add_run(), "指的是医院合同、CRM 开通、价格表，缺任何一项这家医院的合作就是不完整的。"
                     "系统把缺失数量直接摆在首页。而这个也是商务奖金的重要凭证及来源。",
        font=SONG, size=12)
P("再往下是业绩统计和预约组统计，成交单数、派单数、预约单量、已完成、已取消这些都在一屏内。")
H2("医院管理列表")
P("每张卡片上直接标着这家医院缺什么 —— 合同缺失、CRM 未开通、价格表缺失，用红色标出来，"
  "一眼就能看到问题在哪。上面还能按待签约、三要素缺失、新增、待跟进、逾期这些维度筛选。"
  "同时也有快捷的 CRM 开通及账密查看按钮，方便外出时直接操作。")
callout("进展说明：", "目前商务后台在朴科长的指导与协助下已完成所有功能开发，于本月投入使用，"
                     "后期将根据使用情况进行优化调整。",
        fill="EAF1F8", bar="1F4E79", label_color=BLUE)

# ═══ 六、兼职业务闭环 ═══════════════════════════════════════════════
H1("六、兼职业务闭环")
P("整个流程四个环节，全部在 App 里完成。")
numbered(1, "兼职人员自己注册，提交护照、收款码和打工证，后台审核通过才放行。",
         bold_head="人员准入 —— ")
numbered(2, "接单大厅按时间和报酬展示任务，一键接单锁定名额。", bold_head="接单 —— ")
numbered(3, "手动开始兼职记录上班时间。", bold_head="到院打卡 —— ")
numbered(4, "到院后为任务录入客户和订单资料，拍的素材随任务一起提交。",
         bold_head="资料录入 —— ")
P("兼职任务完成后，在客服系统后台会有审核功能，包含根据录入客户和订单资料进行录单操作，"
  "以及工时结算 —— 自动生成结算单和收入流水。兼职可以在 App 里手动提现或走后台月结。",
  space_before=4)
P("下面这套流程的三个特点：", space_before=6, space_after=4)
bullet("每个环节的提交、审核、驳回、重提都有记录和推送；", bold_head="全程留痕 —— ")
bullet("交通费按韩币计价，请求带时区，中韩两地口径一致；", bold_head="异地适配 —— ")
bullet("打卡、任务资料、报销单是三条独立的审核线，被驳回可以修改重交。",
       bold_head="审核闭环 —— ")
P("而兼职任务发布包含关联日程和不关联日程的，在咱们的日程安排页面。同时预留了三方兼职任务"
  "接口，为后期接入其他任务做好准备。", space_before=6)

# ═══ 总结 ═══════════════════════════════════════════════════════════
H1("总结")
p = doc.add_paragraph()
p.paragraph_format.line_spacing = 1.5
p.paragraph_format.space_after = Pt(6)
set_run(p.add_run(), "这个平台今年完成的最大变化，是", font=SONG, size=12)
set_run(p.add_run(), "从一个素材工具变成了一个覆盖多岗位的业务协同平台", font=HEI,
        size=12, bold=True, color=BLUE)
set_run(p.add_run(), "。客服的待办、商务的风险预警、兼职的履约结算，这三条线现在都跑在上面，"
                     "并且都有真实数据在产生。", font=SONG, size=12)
P("下一步我们会继续把还没完全搬到线上的环节补齐，也欢迎各位在使用中随时提需求。")
P("我的汇报到这里，谢谢大家。", font=HEI, bold=True, space_before=6)

doc.add_page_break()

# ═══ 附：预设问答 ═══════════════════════════════════════════════════
P("附：预设问答", font=HEI, size=18, bold=True, color=BLUE,
  align=WD_ALIGN_PARAGRAPH.CENTER, space_after=14, line=1.2)

QA = [
    ("1", "「日活才 113 人，是不是用的人太少了？」",
     ["这是统计周期内的平台活跃使用人数，口径以综合管理系统的统计模块定义为准。需要结合业务"
      "范围看 —— 平台覆盖的是客服、商务、兼职这几个特定岗位，不是全员工具。同期产生了 "
      "2347 次素材上传和 314 份客户档案，说明在用的人使用强度是够的。"],
     ("[提前做] ", "汇报前请先跟后台确认 113 的口径究竟是「周期内去重活跃人数」还是"
                   "「某日日活」。如果是前者，可以补一句「人均上传约 20 次」；"
                   "如果是后者，这句话不能说。")),
    ("2", "「客户信息在手机上安全吗？」",
     ["三层控制：一是角色权限，兼职人员和游客根本看不到客户档案；二是可见范围，素材分公开／"
      "院内／科室内三级；三是接口鉴权，所有请求带 Token，失效自动登出。",
      "另外汇报材料本身也做了处理 —— PPT 里客户管理页的联系方式已经做了模糊。"],
     ("[待改进项] ", "客户列表的「微信」字段目前存的是完整手机号明文，虽然上面的手机号栏"
                     "做了打码，这一行等于绕过了打码，建议后端一并处理。")),
    ("3", "「录单笔数为什么是 0？」",
     ["录单目前主要走 PC 端，App 端不是主入口，所以 App 侧统计为 0。这个和业务量无关。"],
     None),
    ("4", "「兼职这块投入产出怎么样？」",
     ["兼职模块是今年 5 月立项、7 月完成二期的，目前跑出了 62 次打卡和完整的结算流水。"
      "它替代的是原来线下发表单、人工统计工时、人工对账的流程。具体节省多少人力需要业务侧"
      "核算，App 这边能提供的是全程留痕的数据。"],
     None),
    ("5", "「商务概览里 245 成交单数、591 派单数是什么周期？」",
     ["这两个数字受页面顶部的时间筛选和 BD 筛选影响，截图当时的筛选条件是「本日 / 所有 BD」。"],
     ("[提前做] ", "汇报前请确认这两个数字对应的实际口径，避免现场被追问答不上来。")),
    ("6", "「工作台和商务的截图为什么和其他页风格不同？」",
     ["这两页是用管理员账号截的，其他兼职页面是用兼职账号截的 —— 因为不同角色看到的界面"
      "本来就不一样，这正好印证了第 4 页讲的角色权限体系。"],
     None),
]
for num, q, answers, note in QA:
    p = doc.add_paragraph()
    p.paragraph_format.space_before = Pt(14)
    p.paragraph_format.space_after = Pt(6)
    p.paragraph_format.line_spacing = 1.4
    set_run(p.add_run(), f"Q{num}　", font=HEI, size=12.5, bold=True, color=BLUE)
    set_run(p.add_run(), q, font=HEI, size=12.5, bold=True, color=DARK)
    for a in answers:
        pa = doc.add_paragraph()
        pa.paragraph_format.left_indent = Pt(20)
        pa.paragraph_format.space_after = Pt(5)
        pa.paragraph_format.line_spacing = 1.5
        set_run(pa.add_run(), a, font=SONG, size=11.5, color=DARK)
    if note:
        label, text = note
        fill, bar, lc = ("FFF4E5", "BF6000", ORANGE)
        if label.startswith("[待改进"):
            fill, bar, lc = ("FDEAEA", "C00000", RED)
        callout(label, text, fill=fill, bar=bar, label_color=lc)

doc.add_page_break()

# ═══ 控场提示 ═══════════════════════════════════════════════════════
P("控场提示", font=HEI, size=18, bold=True, color=BLUE,
  align=WD_ALIGN_PARAGRAPH.CENTER, space_after=14, line=1.2)

tips = [
    ("总时长约 14 分钟。", "如果只给 8 分钟：保留第 2 页（数据）、第 5 页（工作台）、"
                          "第 7 页（兼职闭环）、第 10 页（技术底座），其余快速带过。"),
    ("最容易被打断的是第 2 页，", "数字最好提前背下来，不要现场找。"),
    ("第 5、6 页的截图字很小，", "投屏时如果看不清，口头把关键指标念出来，不要让大家眯着眼看。"),
    ("兼职是今年新业务，管理层可能最关心，", "第 7、8 页可以适当多停留。"),
]
for head, body in tips:
    p = doc.add_paragraph()
    pf = p.paragraph_format
    pf.space_after = Pt(9)
    pf.line_spacing = 1.5
    pf.left_indent = Pt(18)
    pf.first_line_indent = Pt(-18)
    set_run(p.add_run(), "● ", font=SONG, size=12, bold=True, color=BLUE)
    set_run(p.add_run(), head, font=HEI, size=12, bold=True, color=DARK)
    set_run(p.add_run(), body, font=SONG, size=12, color=DARK)

out = "/Users/tianjian/Desktop/project/yatai_hub/docs/2026上半年工作汇报讲稿.docx"
doc.save(out)
print(f"已生成: {out}")
print(f"段落数: {len(doc.paragraphs)}")
