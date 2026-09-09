# OpenBy 图标概念稿

两套原创矢量方案，使用 SVG 几何路径绘制。已选定 B 方案并接入应用构建；A 方案保留作设计记录。

## 查看与编辑

- `preview.html`：浏览器对比页。
- `comparison.png` / `comparison.svg`：对比图与矢量版。
- `OpenBy-A.svg` / `OpenBy-B.svg`：1024 × 1024 可编辑主稿，可导入 Figma、Illustrator、Inkscape 等矢量工具。
- 同名 PDF：矢量交换文件。
- `OpenBy-?-16.png` 至 `OpenBy-?-1024.png`：透明背景、多尺寸应用图标。
- `OpenBy-?-menu.svg`：独立紧凑画板的单色菜单栏符号；PNG 提供 16、18、32、36 像素。接入 AppKit 时需设置为 template image，由系统适配明暗模式。

## 构图规范

主稿采用 1024 单位画板，底板从 (64, 64) 起，尺寸 896，圆角半径 202；外侧留透明空间。所有主体采用圆头线条与圆角连接，强调轻巧的原生工具感。

共同底板为 #2865DA → #2047AE → #142B6F，主体白色 #F5FAFF，强调色 #70DEFA → #BCF7FF。细亮边与轻微投影用于区分层次。

A：220 单位半径的开口圆环，88 单位线宽，箭头线宽 76。符号表达首字母 O、打开与转交。设计取舍：开口圆环与箭头的组合也可能被理解为登录/退出，品牌识别需要使用场景辅助。

B：一个输入、两个出口。上方路径高亮，表示匹配到的目标；下方路径用 #7395D9 弱化。设计取舍：功能表达更直接，但 16 像素下分支细节较 A 更密集。

## 验证与后续

已用 librsvg 从 SVG 导出 PNG / PDF，并检查对比页的大图、16–128 像素显示和单色符号，未见裁切。小尺寸 PNG 当前由矢量主稿统一缩放；选定方案后可继续逐像素优化 16 / 32 像素图形，并制作 `.icns`、接入 Info.plist 与构建脚本。尚未进行系统 Dock / Finder 实装检查。

B 方案通过 `bash scripts/build-icons.sh` 导出 `Resources/OpenBy.icns` 和 `Resources/MenuBarIcon.pdf`。应用构建直接复制这两份资源，不依赖矢量渲染工具。菜单栏以 template image 加载单色 PDF，保留 SF Symbol 作为资源缺失时的后备。

## 重新生成

依赖 Python 3 与 `rsvg-convert`：

```sh
python3 design/icons/build_icons.py
```

生成脚本仅写入此目录。图标不包含字体或外部图片依赖。
