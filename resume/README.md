# 韩竣成个人简历

- [中文简历 PDF](Han_Juncheng_Resume.pdf)
- [LaTeX 源码](Han_Juncheng_Resume.tex)
- `assets/`：个人照片及组织标志素材
- `common/resume.cls`：简历文档类

当前版本更新于 2026-08-08，为两页 A4 中文简历。

## 构建

在本目录安装 XeLaTeX 后执行：

```powershell
xelatex -interaction=nonstopmode -halt-on-error Han_Juncheng_Resume.tex
```
