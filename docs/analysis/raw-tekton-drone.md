# 第 6–7 章（Tekton / Drone）原文稿可行性索引

> 对象：`docs/course-materials/tekton-drone.md`（749 行，ASR 口播稿）。
> 标记：【原文】= 可按行号核对；【推断】= 由上下文补全；【存疑】= 与官方语义可能冲突、须实测。
> 主项目用 Jenkins，本两章定位为 **候选 CI 对比/选型证据**，不作为实施手册。

## 1. 章节清单

### 第 6 章 Tekton（6-1～6-18）

| 小节 | 主题 | 工具/技术 | 关键操作/配置 | 前置 | 预期结果 |
|---|---|---|---|---|---|
| 6-1 | 本章概述 | — | 列路线：概念→部署→Pipeline→Workspace→Trigger→部署 | 无 | 知范围（L3–9） |
| 6-2 | 夯实基础 | Task/TaskRun/Pipeline/PipelineRun | step=容器；Task 内顺序、Task 间可并行 | 懂 K8s | 懂执行模型（L13–32） |
| 6-3 | 部署到 K8s | Pipelines、Dashboard、tkn、Triggers | 四块安装；Dashboard 开读写；NodePort 32012 | K8s+可出网 | 控制台可触发（L36–50） |
| 6-4 | 定义 Task 运行 | Task、TaskRun（v1beta1） | 三种运行方式；TaskRun 名唯一 | 已装 Pipelines | TaskRun Succeeded（L54–75） |
| 6-5 | Pipeline 克隆代码 | Pipeline/PipelineRun/Secret | 无 runAfter 即并行；git clone 进 workspace | 6-4 | 代码落地共享卷（L79–109） |
| 6-6 | 标题为 taskRef/taskSpec/pipelineRef/pipelineSpec | — | **正文实为触发器介绍，与 6-14 几乎逐句重复，四种引用写法全缺** | — | **描述模糊·内容错位**（L113–123） |
| 6-7 | Task 执行方式 | when/retries/timeout/runAfter/finally | 逐项改 YAML 演示 | 6-5 | 条件跳过/超时/重试生效（L127–152） |
| 6-8 | Task 参数 | params、tkn start -p | 参数默认值；传 git URL 与分支 | 6-4 | 克隆成功（L156–171） |
| 6-9 | Pipeline 参数 | Pipeline/PipelineRun params | 三级声明—引用—同名传递 | 6-8 | 参数贯通（L175–193） |
| 6-10 | Workspace VCT | workspace、VolumeClaimTemplate | PVC/Secret/EmptyDir/ConfigMap 四类；SC=nfs-cli；请求 12M | StorageClass | 跨 Task 共享代码（L197–223） |
| 6-11 | Workspace Secret | Secret workspace + kaniko | 挂 `/kaniko/.docker`；推阿里云 ACR | 镜像仓库凭据 | push 成功（L227–242） |
| 6-12 | Volume 持久化 | PVC + NFS | 挂 `/usr/local/node` 缓存 | NFS/PV/PVC | 二次构建命中缓存（L246–259） |
| 6-13 | Results | results、`$(tasks.x.results.y)` | 时间戳作 tag 传给下游 | 6-12 | 跨 Task 传值（L264–278） |
| 6-14 | 触发器介绍与部署 | Tekton Triggers | 讲 EL/TB/TT；单独部署 triggers | 已装 Pipelines | 页面出现 Trigger 资源（L282–292，内容同 6-6） |
| 6-15 | 触发器 YAML | SA/EL/TriggerBinding/TriggerTemplate/Ingress/Secret | 8 步；SA 绑 cluster-admin | ingress+域名 | EventListener 可被调用（L296–319） |
| 6-16 | 触发器实战 | GitLab Webhook | 填 URL/token/分支，关 SSL 校验 | 6-15 | push 自动触发（L324–338） |
| 6-17 | 项目部署 | + kubectl/sed/awk/finally | 去 http 前缀、awk 取分支、替换 image 后 apply | 6-16 | 部署更新（L343–369） |
| 6-18 | 课程总结 | — | 四对象+执行方式+触发器 | — | 复习（L374–378） |

### 第 7 章 Drone（7-1～7-24）

| 小节 | 主题 | 工具/技术 | 关键操作/配置 | 前置 | 预期结果 |
|---|---|---|---|---|---|
| 7-1 | 概述 | — | 路线：部署→管道→插件→实战 | 无 | 知范围（L385–389） |
| 7-2 | Drone 介绍 | Drone | 容器化、声明式、继承 GitLab 权限 | — | 认知（L394–403） |
| 7-3 | 部署接 GitLab | drone server + OAuth | Client ID/Secret、RPC_SECRET、admin、端口 82/443 | GitLab | 页面登录成功（L408–426） |
| 7-4 | 权限管理（一） | GitLab 组/角色 | **仅一级组仓库可同步**；激活需仓库管理员 | 7-3 | 同步/激活（L431–449） |
| 7-5 | 权限配置（二） | 项目设置 | Protect/Trusted/自动取消/超时/可见性 | 7-4 | 审核与并发控制（L454–466） |
| 7-6 | Docker runner | drone-runner-docker | RPC host/secret、挂 docker.sock、capacity | 7-3 | runner 注册成功（L471–477） |
| 7-7 | K8s runner | drone-runner-k8s + RBAC | SA 授 create pods / pods/log | K8s | 构建跑成 Pod（L482–487） |
| 7-8 | 克隆（一） | `.drone.yml` | kind=pipeline、type=kubernetes、clone depth=1 | 仓库 | 浅克隆（L492–507） |
| 7-9 | 步骤/插件/空间 | steps、plugins | `/drone/src` 同 Pipeline 内共享 | 7-8 | 步骤间共享文件（L512–520） |
| 7-10 | 触发器与 when | trigger、when | 分支+事件类型；status 成功/失败 | 7-8 | 按分支与结果执行（L525–541） |
| 7-11 | 镜像拉取 | pull、image_pull_secrets | if-not-exists/always/never；私有仓库 | 凭据 | 私有镜像可拉（L546–556） |
| 7-12 | 并行执行 | depends_on、node_selector | 同层并行；**缩进必须对齐** | 7-9 | 并行加速（L561–570） |
| 7-13 | 卷 | host path/secret/PVC | host 需 Trusted；PVC 名错会静默卡在 clone | NFS+PVC | 数据持久化（L575–590） |
| 7-14 | Secret 配置 | drone CLI、orgsecret | add/update/rm；DRONE_TOKEN | CLI | 终端管理密钥（L595–619） |
| 7-15 | 内置变量 | `DRONE_*` | echo 取值 | 7-8 | 取分支/编号/事件（L624–630） |
| 7-16 | Sonar 扫描 | sonar 插件 + 质量门 API | curl+awk 判 OK，否则退出 | SonarQube | 门禁阻断（L635–643） |
| 7-17 | Kaniko/Docker 插件 | kaniko、docker | docker 插件需 daemon；作者推荐 kaniko | registry | 构建并推送（L648–656） |
| 7-18 | Jenkins 调用 | jenkins 插件 | URL/user/token/job | Jenkins | 触发接口测试（L662–669） |
| 7-19 | Deploy 插件 | k8s deployment 插件 | api server+token+deployment+container | SA token | 滚动换镜像（L674–685） |
| 7-20 | SSH/SCP/S3 | 三个插件 | host/port/密码；S3 仅 AWS | 目标机 | 产物传输（L690–699） |
| 7-21 | 钉钉/Webhook | 插件 | token、URL、debug | 机器人 | 构建通知（L704–710） |
| 7-22 | 项目部署 | 七步串联 | 克隆→扫描→门禁→构建→部署→测试→通知 | 前述全部 | 端到端（L715–725） |
| 7-23 | CI 工具对比 | Jenkins/Tekton/Drone | 定性比较，无数据 | — | 选型依据（主观，L730–736） |
| 7-24 | 总结 | — | 重点：CLI/trigger/when/volume | — | 复习（L741–747） |

## 2. 技术栈与版本线索

| 项 | 原文表述（行号） | 推断 | 判定 |
|---|---|---|---|
| Tekton API | "deck n 点 tvv 1 beta 1"（L59） | `tekton.dev/v1beta1` | 明确（现已过时） |
| Tekton/Triggers/Dashboard/tkn 版本 | 全文未出现 | — | **无法确认** |
| 基础镜像 | "阿尔法镜像"（L20/60/72） | `alpine` | 明确 |
| 镜像 tag | "hello 阿尔法三点一六"（L63–64） | alpine:3.16 或 echo 文本 3.16 | 推断 |
| Node 镜像 | "十六点一五"（L253）、"十六点一八点一"（L638） | node:16.15 / 16.18.1 | 推断 |
| Nginx | "n 点一九点幺"（L682） | nginx:1.19.1 | 推断 |
| Kaniko | "看一口 / can nico"（L234/651） | kaniko executor（版本无） | 明确+版本未知 |
| Drone | "重/种/众"（第 7 章全篇） | Drone OSS 2.x 时代（版本无） | **无法确认** |
| K8s | "k80 / k 八十" | 未给版本；含 NodePort、StorageClass | **无法确认** |
| 存储 | SC `nfs-cli`、`nfs-cloud`；NFS 10.0.7.11:/nfs/npm-cache（L205–208/232/252） | 自建 NFS provisioner | 推断 |
| 端口 | Dashboard 32012、EL 8080、Drone 82/443、runner 3000（L44/317/420/477） | 实验拓扑固定值 | 明确 |
| 其它 | 阿里云 ACR、SonarQube、GitLab、ingress-nginx、Jenkins（L231/638/310/317/666） | — | 明确 |

## 3. ASR 术语对照表

| 词 | 可能含义 | 依据 | 置信度 |
|---|---|---|---|
| 特克顿/泰克顿/的肯/退款/天玻璃器 | Tekton | L2/16/735/289 | 高 |
| 重/种/众/中/join/兆/做 | Drone | L383/394/712 | 高 |
| k80/k 八十/KO be na tt ice | Kubernetes | L16/497 | 高 |
| 出口/出格/解发器/触发器 | Trigger(s) | L282/290/309 | 高 |
| 窝克斯贝斯/沃克斯贝/波克斯贝/我个时配 | Workspace | L200/203/518 | 高 |
| VCT / vct | VolumeClaimTemplate | L197–215 | 高 |
| 拍拍赖/啪啪赖/泡泡/公开 line | Pipeline | L22/82/131 | 高 |
| 踏实/他是/它是/touch/塔 | Task | L18/21/58 | 高 |
| 斑点/帮顶/波顶/bundy | TriggerBinding | L302/311/348 | 高 |
| 因为里程/一问一审庭/even listen | EventListener | L116/285/308 | 高 |
| 是肯/视频/斯肯/sek/shipping | Secret | L95/232/463 | 高 |
| 样文件 | `.yaml` 文件 | L59/84 | 高 |
| 看一口/CON nico | Kaniko | L234/680 | 高 |
| 魅/妹/内 分支 | main 分支（也可能"每个分支"） | L101/329/531 | 中 |
| 妹点购/魅点购 | `main.go` | L653/696 | 高 |
| 勾一脚本 | Groovy 脚本（Jenkins） | L399 | 中 |
| 真皮石/正品时 | Jenkins | L7/401 | 高 |
| deform | default 命名空间 | L679/683 | 高 |
| 云延伸 | 云原生 | L16/18 | 高 |
| 五杠 8p、12M | 命名空间名、12Mi 存储 | L236/208 | 低（模糊） |
| 妹分支/pi 值 | 分支 / PR | L191/744 | 低（模糊） |

## 4. 问题清单

**事实性错误 / 名实不符**
- 6-6 标题与正文完全错位，且与 6-14 重复，taskRef/taskSpec/pipelineRef/pipelineSpec 从未讲（L113–123 vs L282–292）——本课程最严重缺陷。
- "Tekton 权限控制官网没有做"（L48）为夸大：6-15 自己就创建 SA 并绑角色（L309）。
- "EmptyDir 不能跨 Task 共享，只能同 Task 内 step 共享"（L221）【存疑】，与 PipelineRun 级 emptyDir 通常全 PipelineRun 共享的语义可能冲突，须实测。
- Drone "Protect = 验证 yaml 签名"（L457–458）混淆了 Protect（需人工批准）与签名校验两个机制。
- 6-2 称 Tekton "要装多个插件、多处配置，比较麻烦"（L17–18），与前一句"声明式简洁"自相矛盾。

**过时内容**
- `v1beta1`（L59）：Tekton 已升 v1，v1beta1 处于弃用迁移期（[官方迁移说明](https://tekton.dev/vault/pipelines-v1.3.x-lts/migrating-v1beta1-to-v1/)）。
- Dashboard 官方默认只读、需改安装参数才能点运行（L41–42），属旧版行为。
- 第 7 章整体建立在 Drone OSS 上；Drone 已被 Harness 收购并基本进入维护状态（[背景](https://web.archive.org/web/20260911004855/https://soulteary.com/2023/11/20/the-final-chapter-of-silicon-valleys-open-source-startup-drone-ci-part-1.html)）【外部推断】。

**缺失步骤**
- 无 K8s/Tekton/Triggers/tkn/Drone 任何版本要求与兼容矩阵；无资源 requests/limits、无并发与清理策略。
- 安装仅在"我已装过"的口播中带过，无可复制命令（L42–43/121/290）。
- 无 ingress-controller 安装、无 DNS/证书、无 NetworkPolicy；6-15 直接用域名+8080（L317）。
- 无 webhook 连通性排查章节（回调不可达、token 不匹配、502 只字未提）。
- 无 RBAC 最小权限设计；无密钥轮换、无 Vault/SOPS 等外部密钥方案。
- registry 认证只演示"拷 docker config 进 Secret"（L230/234/554），无长期凭据方案。
- 无健康检查/就绪探针、无 `kubectl rollout status`、**无回滚**（6-17 只有 sed+apply，L362–366）。
- Drone 侧缺 server 数据库/持久化卷、备份、升级、多 Git 源说明。

**不安全实践**
- Trigger SA 绑 `cluster-admin`（L309）。
- GitLab webhook 关闭 SSL 校验（L329）。
- 凭据明文进 git URL 与日志：`http://user:pass@...`（L102/358）、`echo` 出密码（L100）；base64 被称作"加密"（L96–98）。
- kubeconfig 直接挂载并自述"打进镜像很危险"（L362–363）。
- runner 挂 `/var/run/docker.sock`（L475）、开特权容器（L457–459）。
- 仓库可见性设为 public（L460–461）。

**环境假设**
单节点 K8s（node IP 10.0.7.101）、固定 NodePort 32012、NFS 10.0.7.11、阿里云 ACR、私有 GitLab（一级组结构）、ingress-nginx+自有域名、**需科学上网拉 gcr.io 镜像**（L42–43）、Jenkins 兼作接口测试执行器（L666）。以上均为单机实验拓扑，换环境即失效。

## 5. 实验依赖关系

- Tekton：K8s + StorageClass + ingress → Pipelines → Dashboard/tkn → Triggers →（GitLab OAuth 应用 + webhook + SA/Secret）→ EventListener → TriggerBinding/Template → Pipeline/PipelineRun →（NFS PV/PVC、ACR 凭据、kubeconfig Secret）→ 部署。
- Drone：GitLab OAuth 应用 → drone server（RPC secret）→ runner（docker 或 k8s+RBAC）→ 仓库激活 → `.drone.yml` → 插件（kaniko/sonar/k8s/ssh）→ PVC/NFS → 通知。
- 章内强序：6-4→6-5→6-7/6-8→6-9→6-10→6-11/6-12→6-13→6-14/6-15→6-16→6-17；7-3→7-4→7-6/7-7→7-8→7-9→7-10/7-11/7-12/7-13→7-16/7-17/7-19→7-22。6-6 无独立依赖（内容无效）。

## 6. 可信度与处置

| 范围 | 级别 | 建议 |
|---|---|---|
| 6-2、6-7、6-13 | A− | 概念/执行方式可直接采用为对比说明 |
| 6-3、6-4、6-5、6-8、6-9 | B | 改造后采用（版本升级到 v1、补 RBAC/Secret） |
| 6-10、6-11、6-12、6-16、6-17 | B− | 仅作流程示意，命令不可照抄（cluster-admin、明文凭据） |
| 6-1、6-18 | B | 仅作目录参考 |
| **6-6** | C | **不纳入**（错标+重复）；6-6 应更名为"触发器介绍" |
| 6-14、6-15 | B | 与 6-6 去重后作 Triggers 参考 |
| 7-2、7-23 | C | 主观论断，仅作观点引用 |
| 7-4、7-5、7-10、7-13、7-17 | B+ | 有真实坑点（子组不同步、PVC 名错卡住、docker 插件失败），可作对比证据 |
| 其余 7-x | B− | 仅作对比，不纳入实施 |
| 全章 | — | **定位：选型对比素材，非教学/实施依据** |

## 7. 选型对比要点

**原文明确表达（【原文】）**
- Tekton："与 k8s 紧密集成""声明式流水线""可扩展、社区活跃""一般结合 Argo CD，Tekton 构建、CD 部署"（L17–18）；缺点："要装多个插件、多处配置，比较麻烦"（L17）；"资源管控差，做不了审核"（L48）。
- Jenkins：历史悠久、每家公司都在用（L733）；"写了一堆 Groovy 脚本，Pipeline 看起来非常复杂"（L399）。
- Drone："轻量级""内置大量镜像插件、不用自己打镜像""提交即自动构建、不用新建项目、不用配权限"（L397–402）；"比学 Tekton 和 Jenkins 都简单"（L400）。
- Drone 硬限制：不支持 GitLab 子组，项目无法同步（L434–438/735）。
- 选型结论（L733–736）：无 K8s 用 Jenkins；有 K8s 且运维熟可用 Tekton；Drone 最轻。

**缺失（不足以公平比较）**
成熟度与社区数据（star/发版/企业案例，全文无一个数字）；运维成本量化（组件数、升级、备份）；K8s 耦合度（Tekton 强绑定，Drone 可选 docker runner 这一关键差异未点明）；插件生态规模与国内可用性（Drone 插件偏 AWS，L516）；调试体验（日志、重跑、失败定位）；**本地 Mac 可行性**（kind/Docker Desktop 全未提）；许可证与商业化（Harness）；并发/弹性/缓存/多租户/RBAC；成本与迁移代价。

## 8. 对现代工程的迁移提示

1. Tekton：升 v1 API；用 Triggers + Interceptors（CEL/GitLab）替代手写 token 比对；用 Pipelines as Code / Remote Resolvers 管理 YAML；SA 按最小权限、Secret 走 External Secrets。
2. Drone：视为遗留方案，评估迁 Harness CI / GitHub Actions / GitLab CI；若保留，至少 `type: kubernetes` + kaniko + orgsecret。
3. CI 收敛：本课程三工具（Jenkins/Tekton/Drone）能力重叠，主项目已用 Jenkins，建议**单一主 CI + 一层交付工具（Argo CD）**，Tekton/Drone 仅作"若要 K8s 原生"的备选论证。
4. 复现前置：任一方案在 Mac 本地都需 kind/minikube + 本地 registry + 关闭 webhook 外网依赖，原文未覆盖，需另立实验设计。
