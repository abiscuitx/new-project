1. 项目文件夹为
2. 按下列要求修改项目文件夹下的：README.md，.gitignore。
3. 严格按照示例文件结构：README.md.example，深度分析项目文件夹，不要关联其他项目文件夹。
4. README.md将原有内容删除，移动在文档最下方## 原有内容中。
5. README.md根据深度分析内容修改，完全按照示例文件结构：README.md.example。
6. .gitignore保留原有内容基础上，添加系统，编辑器，缓存，密钥，敏感，语言等通用忽略规则，参考示例文件内容：.gitignore.example，。
7. 使用gitRemove.sh删除项目文件夹中已被.gitignore忽略的文件，参考命令：/gitRemove.sh --apply video ' 项目文件夹路径 '。