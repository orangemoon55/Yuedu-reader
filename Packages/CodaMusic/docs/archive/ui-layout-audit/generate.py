from pathlib import Path
import re,json,collections,subprocess
root=Path(__file__).resolve().parents[2]
paths=sorted(list((root/'Sources').rglob('*.swift'))+list((root/'ios/KumoneIOS').rglob('*.swift'))+list((root/'ios/KumoneIOSPackage/Sources').rglob('*.swift')))
# Mask comments and strings while preserving source coordinates.
def mask(s):
    pat=r'//[^\n]*|/\*[\s\S]*?\*/|"""[\s\S]*?"""|"(?:\\.|[^"\\])*"'
    return re.sub(pat,lambda m: ''.join('\n' if c=='\n' else ' ' for c in m[0]),s)
def endcall(s,start):
    depth=0
    for i in range(start,len(s)):
        if s[i]=='(':depth+=1
        elif s[i]==')':
            depth-=1
            if depth==0:return i+1
    return start+1
records=[]; inventory=[]
mods={'font':'字号/字体','padding':'内边距','lineSpacing':'附加行距','tracking':'字距','kerning':'字距','frame':'尺寸约束','listRowInsets':'列表内边距','contentMargins':'滚动内容边距','safeAreaPadding':'安全区留白','safeAreaInset':'安全区插入','pageHeaderTopPadding':'页面顶部留白','navigationSplitViewColumnWidth':'导航列宽','defaultSize':'默认窗口尺寸','windowResizability':'窗口约束','dynamicTypeSize':'文字缩放范围','minimumScaleFactor':'文字压缩下限'}
pattern=re.compile(r'\.(%s)\s*\(' % '|'.join(mods))
ctor=re.compile(r'\b(HStack|VStack|ZStack|LazyHStack|LazyVStack|LazyHGrid|LazyVGrid|Grid|GridRow|GridItem|Spacer|MarqueeText|LyricText|RubyText|TextField|Form|List)\s*\(')
metric=re.compile(r'(?:\b(?:let|var)\s+\w*(?:[Ss]pacing|[Ii]nset|[Pp]adding|[Mm]argin|[Hh]eight|[Ww]idth|[Ss]ize|[Ff]ont|[Gg]ap|[Cc]learance|[Ll]ineHeight|[Ss]cale)\w*|@ScaledMetric|\.fontSize\s*=|\b(?:UIFont|NSFont|PlatformFont|Font)\.(?:systemFont|preferredFont|system|custom)|\b(?:NSAttributedString|NSMutableAttributedString)\s*\()')
for path in paths:
    relpath=str(path.relative_to(root))
    if not (relpath.startswith(('Sources/Kumone/Features/', 'Sources/Kumone/DesignSystem/', 'Sources/KumoneLauncher/', 'Sources/Kumone/Core/CarPlay/', 'ios/')) or relpath in ('Sources/Kumone/KumoneApp.swift', 'Sources/Kumone/Core/PlatformCompatibility.swift', 'Sources/Kumone/Core/UpdaterManager.swift')):
        inventory.append(dict(file=relpath,records=0))
        continue
    s=path.read_text(); ms=mask(s); rel=str(path.relative_to(root)); lines=s.splitlines(); branches=[]; branch_by_line={}
    for n,line in enumerate(lines,1):
        st=line.strip()
        if st.startswith('#if '): branches.append(st)
        elif st.startswith(('#elseif ','#else')) and branches: branches[-1]+=' / '+st
        branch_by_line[n]=' → '.join(branches) or '共享/运行时分支见源码'
        if st.startswith('#endif') and branches:branches.pop()
    found=[]
    def add(pos,kind,expr):
        line=s.count('\n',0,pos)+1
        before=s[:pos]
        types=list(re.finditer(r'\b(?:struct|class|enum|extension)\s+(\w+)',mask(before)))
        # nearest declaration is a navigation aid, not a Swift semantic owner.
        rec=dict(file=rel,line=line,category=kind,expression=' '.join(expr.split()),conditional=branch_by_line.get(line,''),nearest_declaration=types[-1][1] if types else '',context='\n'.join(lines[max(0,line-4):min(len(lines),line+2)]))
        found.append(rec);records.append(rec)
    for m in pattern.finditer(ms):add(m.start(),mods[m[1]],s[m.start():endcall(ms,ms.index('(',m.start()))])
    for m in ctor.finditer(ms):
        e=endcall(ms,ms.index('(',m.start()));expr=s[m.start():e]
        add(m.start(),'容器布局/默认间距',expr)
    known=set(mods)|set(re.findall(r'\w+', 'HStack VStack ZStack LazyHStack LazyVStack LazyHGrid LazyVGrid Grid GridRow GridItem Spacer MarqueeText LyricText RubyText TextField Form List'))
    for m in re.finditer(r'\b([A-Z][A-Za-z0-9_]*)\s*\(',ms):
        if m[1] in known: continue
        e=endcall(ms,ms.index('(',m.start()));expr=s[m.start():e]
        if re.search(r'\b(?:fontSize|size|width|height|spacing|rowHeight|horizontalInset|leadingInset|trailingInset|horizontalPadding|glyphSize):',expr):
            add(m.start(),'自定义组件/原生构造尺寸参数',expr)
    for m in re.finditer(r'\b(HStack|VStack|ZStack|LazyHStack|LazyVStack|Grid|GridRow|Form|List)\s*\{',ms):
        add(m.start(),'容器布局/默认间距',m[1]+' { … } // 无显式参数，使用系统/上下文默认值')
    for n,line in enumerate(lines,1):
        if metric.search(mask(line)):
            pos=sum(len(x)+1 for x in lines[:n-1])
            expr=line.strip()
            if re.search(r'\b(?:let|var)\s+\w+', mask(line)) and '{' in mask(line):
                start=ms.find('{',pos); depth=0
                for end in range(start,len(ms)):
                    if ms[end]=='{': depth+=1
                    elif ms[end]=='}':
                        depth-=1
                        if depth==0:
                            expr=s[pos:end+1].strip();break
            add(pos,'尺寸/字体/间距声明或原生字体',expr)
    inventory.append(dict(file=rel,records=len(found)))
out=root/'docs/ui-layout-audit'
(out/'occurrences.json').write_text(json.dumps(dict(date='2026-10-29',method='静态源码提取；不是 Swift AST 或运行时测量；保留平台编译分支，运行时条件在 context/源码中；nearest_declaration 仅为最近声明导航提示',scanned_files=inventory,records=records),ensure_ascii=False,indent=2)+'\n')
def esc(x):return x.replace('|','\\|').replace('`','\\`')
md=['# 全界面间距与字号：逐项源码清单','','日期：2026-10-29。入口总览：[审计报告](../ui-spacing-typography-audit.md)。','','本表是静态候选清单：包括所有编译分支、共享组件、加载/空态和调试界面；不等于每项都在当前设备可见。单位为 pt（比例、行数、压缩系数除外）。系统默认间距、原生 Form/List/菜单和继承字体无法仅凭源码得到最终数值。尺寸约束与字号分列；Image 的 font 表示符号尺寸，不能直接当正文。多层 padding 需结合父级计算，frame 不是间距。最近声明仅为导航提示。','','扫描文件数：%d；有候选项文件数：%d；候选记录数：%d。'%(len(paths),sum(x['records']>0 for x in inventory),len(records)),'','## 文件索引','', '| 文件 | 候选记录 |','| --- | ---: |']
for i in inventory:
    if i['records']:md.append('| [%s](#%s) | %d |'%(i['file'],Path(i['file']).stem.lower(),i['records']))
for rel,rs in __import__('itertools').groupby(records,key=lambda x:x['file']):
    rs=list(rs);md+=['','## '+Path(rel).stem,'','源码：`'+rel+'`。','','| 行 | 类型 | 当前表达式 | 编译分支 |','| ---: | --- | --- | --- |']
    for r in sorted(rs,key=lambda x:x['line']):md.append('| [%d](../../%s#L%d) | %s | `%s` | %s |'%(r['line'],rel,r['line'],r['category'],esc(r['expression']),esc(r['conditional'])))
(out/'inventory.md').write_text('\n'.join(md)+'\n')
fonts=collections.Counter();spacing=collections.Counter();semantic=collections.Counter()
for r in records:
    if r['category']=='字号/字体':
        for m in re.finditer(r'\.system\(size:\s*(\d+(?:\.\d+)?)\s*[,)]',r['expression']):fonts[m[1]]+=1
        for m in re.finditer(r'\.(largeTitle|title[23]?|headline|subheadline|body|callout|footnote|caption2?)\b',r['expression']):semantic[m[1]]+=1
    if r['category'] in ('内边距','容器布局/默认间距'):
        m=re.search(r'(?:spacing:\s*|\.padding\((?:\.[a-zA-Z]+,\s*)?)(-?\d+(?:\.\d+)?)\s*[,)]',r['expression'])
        if m:spacing[m[1]]+=1
stats={'scanned_files':len(paths),'matched_files':sum(x['records']>0 for x in inventory),'records':len(records),'categories':dict(collections.Counter(r['category'] for r in records)),'literal_font_sizes':dict(sorted(fonts.items(),key=lambda x:float(x[0]))),'semantic_font_styles':dict(semantic),'direct_literal_spacing':dict(sorted(spacing.items(),key=lambda x:float(x[0])))}
(out/'summary.json').write_text(json.dumps(stats,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(stats,ensure_ascii=False,indent=2))
