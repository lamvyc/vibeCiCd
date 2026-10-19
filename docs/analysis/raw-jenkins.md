# Jenkins 课程逐字稿可行性/索引报告（Phase 0）

> 来源：`docs/course-materials/jenkins.md`（907 行，第 3–5 章，53 小节）。语音转写、ASR 噪声极重。
> 标记约定：**原** = 原文事实（逐字稿明确陈述/演示）；**推** = 我的推断（含依据）；**？** = 无法确认。行号均为原文件行号。

## 1. 章节清单

| 号 | 主题 | 工具/技术 | 关键操作 | 前置 | 预期结果 |
|---|---|---|---|---|---|
|3-1|本章概述|Docker/K8s/Helm、Pipeline、RBAC|仅提纲|无|描述模糊|
|3-2|Jenkins 定位|插件、共享库|概念讲解|无|描述模糊|
|3-3|Docker 装 Jenkins|docker、`/var/jenkins_home`、docker.sock|8080→81、50000、TZ/UTF-8；取 initialAdminPassword；装推荐插件；改密码|Docker、81 空闲|admin 可登录|
|3-4|Helm 装 Jenkins|helm3、NFS SC、SA/Role|建 ns/SA；values 改 SC、`serviceAccount.create=false`；nodePort|NFS SC、helm 仓库、多节点|helm 部署成功|
|3-5|YAML 装 Jenkins|`jenkins/jenkins:lts`、PVC、SA|ns/SC/PVC/Deployment/Service/SA 一起 apply|NFS SC|Pod Running|
|3-6|接 OpenLDAP|LDAP 插件、389|全局安全→LDAP；uid 过滤、mail 属性、manager DN|可用 LDAP、ou=user/group|test 账号可登录|
|3-7|凭据/系统配置|Credentials、视图|建列表视图；建 user/password 凭据(ID)；改并发数|已装插件|凭据可按 ID 引用|
|3-8|视图/文件夹规范|视图、文件夹|环境视图→项目文件夹→子视图三级|无|分类规范建立|
|3-9|RBAC|Role-based Strategy|全局角色 + item 角色（pattern 需绝对路径）|LDAP 用户|无权限用户看不到 job|
|3-10|Pipeline 入门|Declarative、`agent any`|pipeline/stages/steps 骨架、自由式对比|无|多阶段构建成功|
|3-11|构建代理|`agent{node{label}}`、JNLP|建固定节点/标签，按 label 调度|从节点+JDK|演示报"节点不在线"|
|3-12|options|retry/timeout/timestamps/并发/discarder|逐项开关演示|无|行为生效|
|3-13|sh 三种用法|引号与转义|单/双/三引号、换行|无|echo 正常|
|3-14|Groovy 沙盒|Script Approval|关沙盒→待批准→批准|管理员|未批准即报错|
|3-15|环境变量|`environment`/`withEnv`/`env.X`|全局/局部/块内|无|跨 stage 引用局部变量报错|
|3-16|凭据使用|withCredentials、`_USR/_PSW`|按 ID 引用|已建凭据|密码被掩码|
|3-17|post|`post{always/success/failure/aborted}`|全局与 stage 级|无|局部+全局各报一次|
|3-18|清理工作空间|`cleanWs()`|首个 stage 清理|无|上次文件被删|
|3-19|内置变量/构建信息|BUILD_NUMBER、build user vars|echo 变量、改描述/显示名|插件|页面显示描述与用户|
|3-20|指令生成器|Directive/Snippet Generator|页面生成后粘贴|无|免手写语法|
|3-21|计划任务|`triggers{cron}`、H 哈希|分时日月周|无|定时自动触发|
|3-22|并行/Blue Ocean|`parallel`、`parallelsAlwaysFailFast()`|parallel 内多 stage|Blue Ocean 插件|并行可见、失败即停|
|3-23|when/input|`when{anyOf/expression}`、`input`|按参数判断、人工审核|参数化|跳过或阻塞待审|
|3-24|postbuild 徽章|插件名未听清(addBadge?)|页面黄底文字|？|构建页显示徽章|
|3-25|Jenkinsfile 存储(一)|Git、`skipDefaultCheckout`|配置仓库+脚本路径|代码仓库+凭据|从 SCM 读脚本|
|3-26|存储(二)|`checkout scm`|手动拉代码|同上|工作空间有代码|
|3-27|Jenkins CLI|`jenkins-cli.jar`、JDK11|`-s/-auth build -p`|已下 jar|命令触发构建|
|3-28|状态回传 GitLab|GitLab 插件、API token|建 token→凭据→连接→`gitlabCommitStatus`|GitLab、外网|提交旁显示状态|
|3-29|Webhook 触发|Generic Webhook Trigger|token+`$.ref` 表达式、Groovy 截分支|插件、webhook、关 CSRF|推送即构建|
|3-30|多分支流水线|multibranch、branch source 正则|扫 main/pre|各分支有 Jenkinsfile|自动生成 job|
|3-31|小结|—|—|—|描述模糊|
|4-1|进阶概述|静/动态节点、Groovy、共享库、Kaniko|提纲|无|描述模糊|
|4-2|静态 Slave|JNLP、label、端口 50000/31000|建节点、下载 agent.jar、`java -jar`|CentOS+JDK11|标签调度成功|
|4-3|Docker 流水线|docker pipeline、`withRegistry`|`agent{docker{image/label/args -v}}`|从节点有 docker|容器内构建/push|
|4-4|K8s 动态节点|kubernetes 插件、Pod 模板 YAML|cloud 配置+kubeconfig 凭据|K8s、kubeconfig|Pod 临时建/销|
|4-5|Groovy 基础|def/for/if/try-catch/函数|脚本命令行验证|无|输出正确|
|4-6|共享库|`vars/`、`src/org`、`@Library`|全局共享库+实例化|Git 仓库|调用 info/warning|
|4-7|参数(5 类基础)|string/text/boolean/choice/password|自由式+流水线|无|参数生效|
|4-8|高级参数|Extended Choice/Active Choices/Date|联动+Groovy 脚本|三插件|联动取值|
|4-9|Kaniko|executor/debug、`--cache-copy`/`--cache-repo`|`docker run` 挂 workspace 与 config.json|镜像仓库凭据|缓存构建并 push|
|4-10|小结|—|—|—|描述模糊|
|5-1|实战概述|SonarQube、MeterSphere|提纲|无|描述模糊|
|5-2|测试流水线+飞书|共享库、ansiColor、docker run、kubectl、飞书 webhook|拉码→构建→sed 改镜像→apply→报警|代理机有 kubeconfig|部署+飞书通知|
|5-3|部署 SonarQube|compose、postgres、9000、vm.max_map_count|改内核参数、挂配置、汉化包|Docker、内存|admin/admin 登录|
|5-4|SQ 接 LDAP|`sonar.properties` LDAP 段|改配置→重启|LDAP|test 可登录|
|5-5|门禁/权限/令牌|新代码周期、quality gate、全局分析令牌|建 token→Jenkins 凭据|SonarQube|令牌可扫描|
|5-6|Jenkins 集成扫描|SonarQube Scanner 插件、scanner-cli 镜像|服务配置+扫描参数+`waitForQualityGate`|5-4/5-5|门禁失败即终止|
|5-7|部署 MeterSphere|docker 在线安装、CentOS7 4C8G/50G|一键脚本|公网|可登录|
|5-8|定义接口测试|LDAP、AK/SK、空间/项目/环境、测试计划|建接口+断言+计划|MeterSphere|手工执行通过|
|5-9|Jenkins 集成 MS|手工上传 `.hpi`、片段生成器|上传→生成 DSL→贴入|MS 的 AK/SK|构建跑接口测试+通知|
|5-10|静态代理实战|共享库+docker.sock+kubectl+SQ+MS|6 阶段全链|4-6/5-6/5-9|部署+扫描+接口测试|
|5-11|K8s 动态实战|Pod 多容器、Kaniko debug、PVC 缓存|`agent{kubernetes{yamlFile}}`|K8s+密钥|Pod 内全链|
|5-12|总结|—|—|—|描述模糊|

## 2. 技术栈与版本线索

| 项 | 原文片语(行) | 推断 | 状态 |
|---|---|---|---|
|Jenkins|"jenkins。lts稳定版本"(47) | `jenkins/jenkins:lts`，具体版本未提 | 明确/版本无法确认 |
|JDK|"我这边装了JAVA 11版本"(388,490)；"八版本的JAVA…没有办法运行"(490) | 讲师用 JDK11，JDK8 跑 agent.jar 失败 | 明确(讲师环境) |
|K8s|"k一点二八的版本"(549) | 插件连接测试返回 1.28 | 推断(高) |
|K8s|"黑白史一点二四版本开始…不需要再使用docker了"(664) | 指 1.24 移除 dockershim | 明确(观点)，表述不严谨 |
|Helm|"help命令添加存储库"(36) | helm 3 `repo add`/`-f values` | 推断 |
|StorageClass|"storm class…nfs杠c"(32)、"nf 4杠clid"(46) | nfs-client / 名为 nfs-c | 推断(中) |
|端口|8080→81(21)、"五万端口"(21)、31000(47,485) | agent 端口被改为 31000 | 明确 |
|SonarQube|"说了"(726)、9000(731)、admin/admin(731) | Community+postgres，版本无法确认 | 推断/版本？ |
|内核参数|"二六二幺四四"(727) | `vm.max_map_count=262144` | 明确 |
|MeterSphere|"mr sphere"(796)、"渗透o17…四核…8g…50个g"(796) | CentOS7 单机 docker 安装 | 明确 |
|Kaniko|"看一口"(665)、"拿test版本"(669) | latest，版本无法确认；debug 镜像需 `/busybox` | 无法确认 |
|golang 镜像|"勾烂的一点二二点一"(529) | golang:1.22.1 | 推断(高) |
|alpine 镜像|"阿尔法三点一四的版本"(520) | alpine:3.14 | 推断(高) |
|镜像仓库|"杭州阿里云的镜像仓库"(525) | 阿里云 ACR | 明确 |
|OS|"渗透OS"(479)、"渗透oc"(483) | CentOS / CentOS7 | 推断(高) |
|插件组|LDAP(58)、Role-based(107)、Blue Ocean(305)、GitLab(395)、Generic Webhook(416)、Docker Pipeline(504)、Kubernetes(538)、SonarQube Scanner(774)、MeterSphere(843)、Extended Choice(628)、Active Choices(631)、Date(637)、build user vars(263)、ansiColor(703) | 名称明确，版本全未记 | 明确/版本？ |

## 3. ASR 术语对照表

| 术语 | 可能含义 | 判断依据 | 置信度 |
|---|---|---|---|
|k八十/开八十/k80/k fs/kobe net ties|K8s、kubectl、kubernetes|上下文均为集群操作(32,46,538) | 高 |
|真皮实/正题十/金提子/精品词/静力时/zink is/drinks/js|Jenkins|"整体是页面上"(137)、"真题时版本"(79) | 高 |
|拍拍赖/啪啪line/破理|Pipeline；`parallel`(303) |"流水线脚本"(135) | 高 |
|勾语/购物/grovvy/公笔|Groovy|"勾笔脚本"(579) | 高 |
|a井块/安利|`agent`/`agent any`|"不需要h块默认any"(156) | 高 |
|storm class/strong clid|StorageClass|"持久化存储…创建pv以及PVC"(32) | 高 |
|ops in|`options`|"配置全局行为"(168) | 高 |
|蓝海项目|Blue Ocean|"安装这个插件…UI"(305) | 高 |
|妹分支/魅分支/me|`main` 分支|"主分支是妹，而不是master"(516) | 高 |
|pi值/pie分支|`pre`（预发）分支|"两个分支…一个妹分支，一个pie"(447,450) | 中 |
|预发|pre-production|"测试，预发，生产"(88) | 高 |
|飞书/飞速|Feishu/Lark 告警|"发送到飞书里面去"(711) | 高 |
|Metershpere/mr sphere/misfire/me色sphere|MeterSphere|"持续测试平台"(796) | 高 |
|收纳/说了/sola/双拉q|SonarQube|"代码质量…开源平台"(726) | 高 |
|慕课/木刻|课程品牌占位域名(DC=慕课,CN)|"DC是慕课"(60)、"慕课网"(816) | 高 |
|perla way|`parallelsAlwaysFailFast()`|"有一个失败则整个退出"(314) | 高 |
|Poke n / poke n|`token`(webhook 校验)|"poke n需要匹配"(426) | 高 |
|轱辘/oe=user|`ou=group`、`ou=user`|"ou等于轱辘"(62) | 高 |
|贝斯电视杠w0|`base64 -w0`|"不让它换行，再编码"(890) | 中 |
|收了杠开始杠PVC|`sonar-cache-pvc`|"挂载的扫描缓存"(891) | 中 |
|架文件/价包/外包|`agent.jar` / jar 包|"JAVA命令把这个架文件运行"(482) | 高 |
|e store点hh脚本|一个 `install_*.sh` 安装脚本|"执行这个脚本"(20) | 低 |
|真汽车|Jenkins(同音)|"真汽车的环境变量"(209) | 中 |

## 4. 问题清单（含行号）

| 行 | 类型 | 问题 |
|---|---|---|
|21,869|不安全|`/var/run/docker.sock` 直接挂入容器，等价 root 宿主机权限；5-11 改用 Kaniko，前后自相矛盾 |
|26,731|不安全|弱口令 `慕课六六六`、`admin/admin`，且未提改密策略/HTTPS |
|23,47|缺失|未固定 Jenkins/插件版本，装"推荐插件"；无兼容性矩阵（K8s 插件↔K8s 1.28） |
|22,731|缺失|无反向代理/TLS、无备份、无 JCasC，配置全在 UI |
|32-35|缺失|Helm 方式 `serviceAccount.create=false` 却未说明已有 SA/ClusterRole 来源；3-5 反手给 SA 绑管理员角色，RBAC 前后不一致、非最小权限 |
|32,46|环境假设|强依赖 NFS StorageClass `nfs-c`；无 SC 则 PVC Pending |
|38,483|环境假设|课程假设的双节点集群(7.100/7.101)与 7.30 静态代理机，IP 硬编码 |
|60-63|环境假设|LDAP `DC=慕课,DC=CN`、389 明文、`ou=user/group`，需自建目录 |
|291-295|事实错误|cron 说"每隔十分钟"，写作 `0-29/10` 实际只 3 次；`H/15` 与"第一位是每隔15分钟"表述混乱 |
|170,706|事实错误|`disableConcurrentBuilds` 被说成"终止旧构建"，无 `abortPrevious` 时行为相反 |
|407-409|事实错误|声称必须注释 `skipDefaultCheckout` 才能回传 GitLab 状态，实际取决于 `gitlabCommitStatus` 调用位置与 checkout |
|225-229|需核实|称 `_USR` 明文、`_PSW` 加密；实际两者均为凭据绑定变量，掩码规则需实测 |
|422|描述模糊|称片段生成器生成的 `GenericTrigger` 缺小括号、需手工补，未给出可复现凭据 |
|274|无法确认|3-24 "postbuild"插件名与 `addBadge` 用法均未听清 |
|416-425|缺失|webhook 依赖公网可达+关 CSRF/SSL 校验；未讲 secret 校验、重放、分支过滤安全 |
|710,871|缺失|部署仅 `sed` 改镜像+`apply`，无健康检查/就绪探针/回滚(`rollout undo`)，无 imagePullSecret |
|764,765|缺失|Sonar 令牌"永不过期"；未讲轮换 |
|796-801|环境假设|MeterSphere 需公网、4C8G/50G，离线场景仅一句带过 |
|843|环境假设|插件需从 GitHub 下 `.hpi` 手工上传，企业网不通则失败 |
|113-117|风险操作|演示中先删 admin 角色导致自锁，靠"先别删 admin"口头提醒，无恢复路径 |
|549,547|不精确|K8s API `6443` 与 kubeconfig 凭据用法正确，但未讲 namespace/RBAC 隔离与 Pod 资源限制 |

## 5. 实验依赖关系

| 小节 | 依赖 |
|---|---|
|3-3/3-4/3-5|三选一即可产出"可用 Jenkins"，后续全部依赖其中一种 |
|3-6→3-9|LDAP 用户必须先存在，RBAC 才有对象可分配 |
|3-7→3-16/3-25/3-28|凭据 ID 是后续 withCredentials、SCM、GitLab 的前置 |
|3-11→4-2/4-3|静态节点标签机制先懂，才有 Slave/Docker 流水线 |
|3-14→4-5/4-6/5-2|Groovy 沙盒与 Script Approval 是共享库报错的首要原因 |
|3-22→5-2|`parallel`+failFast 在实战中被复用 |
|3-25/3-26→3-28/3-29/3-30|Jenkinsfile 入仓是 SCM 触发与多分支的前提 |
|4-4→5-11|K8s cloud/Pod 模板先通，动态实战才可跑 |
|4-9→5-11|Kaniko 参数与 debug 镜像用法直接复用 |
|4-6→5-2/5-10|共享库 `vars/`+`src/org` 是两条实战脚本的骨架 |
|5-3/5-4/5-5→5-6→5-10/5-11|SQ 部署→LDAP→令牌→扫描→实战 严格串行 |
|5-7/5-8→5-9→5-10/5-11|MS 部署→AK/SK+测试计划→插件集成→实战 严格串行 |

## 6. 可信度与处置建议

| 小节 | 可信度 | 建议 | 理由 |
|---|---|---|---|
|3-1/3-2/3-31/4-1/4-10/5-1/5-12|C|不纳入|纯概述/总结，无操作信息|
|3-3/3-4/3-5|B|改造后采用|部署路径可参考，但版本、存储、RBAC、TLS 全部要重做|
|3-6|B|改造后采用|LDAP 流程完整；缺 TLS/组映射/权限联动|
|3-7/3-8|A|直接采用|凭据与视图/文件夹规范与版本无关|
|3-9|A|改造后采用|RBAC 思路正确，pattern 与自锁风险需补|
|3-10~3-18|A|直接采用|声明式基础语法长期稳定|
|3-19/3-20|B|改造后采用|依赖插件与 UI 路径，变量名以官方文档为准|
|3-21|B|改造后采用|cron 讲解有错，仅取 `H` 思路|
|3-22/3-23|A|直接采用|parallel/when/input 语法稳定|
|3-24|C|不纳入|插件与 API 均无法确认|
|3-25/3-26/3-27|A|改造后采用|存储策略正确；CLI 用 API token 替代 `-auth 用户:密码`|
|3-28/3-29/3-30|B|改造后采用|机制正确，公网/CSRF/secret 假设需替换|
|4-2|B|不纳入|JNLP 静态代理已过时，改 Kubernetes/SSH 云代理|
|4-3|B|改造后采用|Docker agent 思路可用，但需去掉 docker.sock|
|4-4|A|改造后采用|K8s 插件 + `yamlFile` 是主流做法，需补 RBAC/资源限制|
|4-5/4-6|A|直接采用|Groovy 与共享库结构通用|
|4-7/4-8|B|改造后采用|基础参数可直接用；Active Choices 脚本需重写并加沙盒|
|4-9|A|改造后采用|Kaniko 参数正确，建议换 BuildKit/Buildah 并锁版本|
|5-2|B|改造后采用|全链示范价值高，含 docker.sock 与硬编码 IP|
|5-3/5-4/5-5/5-6|B|改造后采用|流程完整；需补备份、令牌轮换、compose 版本锁定|
|5-7/5-8/5-9|B|仅作对比|MeterSphere 绑定特定平台，接口测试可用其它方案替代|
|5-10|C|不纳入|docker.sock + ClusterRole + kubectl 属反模式|
|5-11|A|改造后采用|Pod 多容器+Kaniko 是正确方向，需补 Secret/PVC/超时|

## 7. 对现代工程的迁移提示（2026 视角）

1. **配置即代码**：用 JCasC 管理凭据/节点/安全域，替代 3-6/3-9 的 UI 点击；配 Configuration as Code 校验插件。
2. **版本固定**：Jenkins LTS 镜像、全部插件、Kaniko/golang/alpine 基础镜像一律锁 digest 或精确 tag（当前 3-3/3-5/4-9 全为 `lts`/`latest`）。
3. **代理模型**：放弃 4-2 的 JNLP 静态节点，用 Kubernetes plugin 的 ephemeral Pod（`yamlFile` + `containerTemplate`）或 SSH 云；静态代理只留给特殊硬件。
4. **构建镜像**：不在容器里挂 docker.sock；用 Kaniko（需 `/busybox`、`--cache-repo`）或 BuildKit rootless / Buildah。5-10 的 docker.sock 工艺应整段废弃。
5. **最小权限**：Jenkins 的 SA 用命名空间级 Role（仅 pods/exec/logs），禁止 ClusterRoleBinding；Sonar/MS 令牌按项目、设过期、可轮换。
6. **密钥管理**：镜像仓库 `.dockerconfigjson` 用 Secret + imagePullSecrets；kubeconfig、飞书 webhook、LDAP bind 密码入 External Secrets/Vault，而非挂载明文文件。
7. **交付安全**：部署阶段改为 Helm/Kustomize + `rollout status`/就绪探针 + 自动回滚；`sed` 改 YAML 不可审计（710）。
8. **触发链**：webhook 改为带签名校验的 SCM 触发（GitLab token + 分支过滤），不要关闭 CSRF/SSL 校验；`poll scm` 仅兜底。
9. **质量门禁**：SonarQube 的 `waitForQualityGate` 保留，但门禁阈值入仓（Quality Gate as code），并补 SAST/依赖扫描。
10. **可观测与恢复**：Jenkins home 备份、构建日志外置、审计插件；课程全程未涉及。

## 8. 可直接复用的配置片段

| 片段 | 行 | 说明 |
|---|---|---|
|`pipeline{ agent any; stages{ stage('x'){ steps{ ... }}}}`|137-139,147-149|声明式骨架，`stage` 名必填、括号必须成对|
|`agent{ node{ label 'xxx' }}` / `agent none`|156-159|按标签调度；`none` 用于全局不指定|
|`options{ retry(3); timeout(time:1,unit:'HOURS'); timestamps(); disableConcurrentBuilds(); buildDiscarder(logRotator(numToKeepStr:'10')); skipDefaultCheckout() }`|168-171,175-180|3-12 全部选项，注意 `abortPrevious` 语义|
|`environment{ CC='x' }` / `withEnv([...])` / `env.X=`|209-210|全局/局部/块内三级|
|`withCredentials([usernamePassword(credentialsId:'id',usernameVariable:'U',passwordVariable:'P')])`|225-229|配合 `_USR/_PSW` 需实测掩码|
|`post{ always{} success{} failure{} aborted{} }`|236-238|全局与 stage 级不要同时配|
|`cleanWs()`|249-250|置于首个 stage，优于 `deleteDir()`|
|`triggers{ cron('H/15 * * * *') }`|291-296|用 `H` 分散负载，勿照抄 `0-29/10`|
|`parallel a: {...}, b: {...}` + `parallelsAlwaysFailFast()`|303-304,312-314|失败即全部终止|
|`when{ anyOf{ expression{ params.X=='pre' }; expression{ env.BUILD_NUMBER as int >= 1 } } }`|325-326|多条件或|
|`input message:'发布新版本', ok:'确认点我', parameters:[string(...)]`|334-336|人工卡点+参数回填|
|`@Library('name@main') _`；`vars/log.groovy`、`src/org/test.groovy`|594-600|全局共享库结构，`vars/` 直接调用、`src/` 需 `new`|
|`agent{ docker{ image 'golang:1.22.1'; label 'slave'; args '-v /root/.m2:/root/.m2' }}`|504-509,515|局部镜像优于全局|
|`docker.withRegistry('https://registry','credId'){ docker.image(x).push(tag) }`|510-512|配 `BUILD_TAG`/`GIT_COMMIT` 打 tag(526-528)|
|Kaniko：`--cache-copy-layers --cache=true --cache-repo --dockerfile --destination`；debug 镜像 `--entrypoint`|665-669,671-672|挂 workspace 与 `config.json`|
|`agent{ kubernetes{ yamlFile 'pod.yaml'; retries 2 }}`|885-886|多容器 Pod：maven/groovy/kaniko-debug，`tty:true`|
|`checkout scm` 与 `skipDefaultCheckout()` 组合|179,376-378|分离配置仓/业务仓时手动拉|
|`gitlabCommitStatus(name:'build'){...}`|396-401|放在 checkout 之后|
|`GenericTrigger(... token: 'x', genericVariables: [[key:'ref',value:'$.ref']])`|420-424|token 与 GitLab 侧必须一致|
|`waitForQualityGate()` 判 `status=='OK'`|776-778|门禁失败即 `error` 终止|
|`kubectl -n ns set image` 或 `sed` + `kubectl apply -f`|710-711|仅作参考，建议改 Helm|

> 说明：第 8 节为"可复用要点"清单，非完整脚本；所有片段均需按 2026 版本重新验证（尤其插件 DSL 与 K8s API 版本）。
