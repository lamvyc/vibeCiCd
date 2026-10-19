# 第 8–9 章原始素材分析：KubeVela / Zadig（Phase-0 可行性索引）

- 素材：`docs/course-materials/delivery-platforms.md`（777 行，纯语音转写，正文中几乎**没有可复制命令**）
- 标注约定：**【实】**= 原文明确陈述；**【推】**= 依上下文/技术常识推断；**【疑】**= 无法确认。行号均指源文件。

## 1. 章节清单

| 小节 | 主题 | 工具/技术 | 关键操作/配置 | 前置 | 预期结果 |
|---|---|---|---|---|---|
| 8-1 | 概述 | KubeVela / OAM | 资源再抽象一层、多云多集群 | — | 建立概念（无实操） |
| 8-2 | 部署 | vela CLI + velaux | 装 CLI→`vela install`→启用 velaux→NodePort→建 admin | K8s 集群 | vela-system 3 Pod，UI 可登录 |
| 8-3 | 概念 | OAM | 项目/应用/组件/特征/策略/工作流/交付目标；卸载顺序 | 已安装 | 概念清晰、可卸载（命令缺失） |
| 8-4 | 接入 OpenLDAP | ldap + fluxcd + velaux 插件 | 先装依赖→全局配置粘贴 LDAP 串→认证选 LDAP | fluxcd/velaux、OpenLDAP | LDAP 用户登录，按同邮箱继承权限 |
| 8-5 | 项目-环境-交付目标 | velaux | 建 APP 项目→test 环境→交付目标 local/APP-test | 命名空间 | 应用归属项目与环境 |
| 8-6 | 接集群+小案例 | `vela up -f` | 粘贴 kubeconfig 加集群→部署 first-app | kubeconfig | 应用 Running，自动生成 syc- 目标 |
| 8-7 | 项目配置 | velaux | 只读/接管模式、插件、成员角色 | 已有项目 | 成员按角色受限 |
| 8-8 | 容器镜像部署 | web-service 组件 | UI 建 nginx 应用→点"部署" | 镜像 | 2 Pod 滚动 |
| 8-9 | 金丝雀 | rollout 插件 + 工作流 | v1→v2：20%→暂停→50%→暂停→100% | rollout 插件、≥1 副本 | 分批放量，可回滚 |
| 8-10 | Sidecar/Worker | worker 组件 + sidecar 特征 + emptyDir | 双容器共享卷 | — | 单 Pod 两容器 |
| 8-11 | k8s-object+多集群 | k8s-object + topology 策略 | 两集群同名命名空间部署 | 第二集群（实为同一 kubeconfig） | 双份资源 |
| 8-12 | if/timeout/并行 | vela-cli 步骤、if、timeout、step-group | 并行组、条件判断、超时 | — | 步骤跳过或流水线中断（命令缺失） |
| 8-13 | 编排与参数 | dependsOn + input/output | A 完成后 B，output 写 ConfigMap | — | ConfigMap 含 message/IP |
| 8-14 | 资源托管 | `vela adopt` | 纳管已有 Deployment/Service | 已有资源 | vela 可见并可删除 |
| 8-15 | 触发器 | trigger webhook | 建触发器→CI 内 curl 改 image | Jenkins | 镜像变更触发部署 |
| 8-16 | GitOps | 仓库轮询（1 分钟） | 提交改 image→自动部署 | Git 仓库 | 1 分钟内版本更新 |
| 8-17 | 报警 | notification + if | 成功/失败各发飞书 | Webhook | 仅一条通知 |
| 8-18 | 权限 | 平台角色/项目角色 | 建角色→绑成员 | 用户已登录 | 最小权限 |
| 8-19 | 内置组件 | webservice/worker/k8s-object/daemonset/cronjob | `vela show` 查字段 | — | 会查文档 |
| 8-20 | 内置运维特征 | ingress/annotations/hpa/labels/init-container | `vela show` | — | 会配 |
| 8-21 | 内置策略 | override / topology | 标签选集群、覆盖镜像与副本 | 多集群+标签 | 差异化部署 |
| 8-22 | 内置工作流 | deploy/suspend/notification/vela-cli/timeout | 人工暂停 + 超时兜底 | — | 审核或超时继续 |
| 8-23 | CUE 基础 | CUE + Go | 装 Go→装 cue→类型/条件/循环 | Go 环境 | 能读 CUE |
| 8-24 | 自定义 CUE 模板 | vela def init/apply/vet/list/edit/del | YAML→CUE→应用到集群 | 8-23 | 集群出现自定义 definition |
| 8-25 | CUE 实战 | 改 ingress 定义加注解 | 可选参数 + for 循环 | 8-24 | Ingress 带自定义注解 |
| 8-26 | 项目实战 | GitOps+Go+ingress+探针 | 上传 YAML→提交触发 | 8-16、GitLab | 自动部署（删除需删仓库文件） |
| 8-27 | 总结 | — | 重点：内置模块 / CUE / GitOps | — | — |
| 9-1 | 概述 | — | 课程地图 | — | 模糊，无内容 |
| 9-2 | 介绍 | Zadig | 构建+测试+部署一体，替代多平台 | — | 理解定位 |
| 9-3 | 部署 | install-1.18.0 脚本 | 版本校验→compose 起 MySQL/Mongo→mini-pv→环境变量→安装脚本 | K8s 1.16–1.26、MySQL≥5.7、Mongo≥3.4、NFS | zadig 命名空间就绪 |
| 9-4 | LDAP/集群/仓库/系统设置 | OpenLDAP+kubeconfig+阿里云 ACR | 账号系统→集群直连→镜像仓库→系统配置 | LDAP、ACR 账号 | 可登录、集群"正常" |
| 9-5 | 集成/权限/建项目 | Jenkins+GitLab+Sonar+RBAC | 三处集成→建 K8s YAML 项目 | 三者可用 | 项目含 3 环境 3 工作流 |
| 9-6 | 服务管理 | 服务 / 服务编排 | 手工或代码库导入、变量、镜像命名规则、拖拽顺序 | 项目 | 服务可构建部署 |
| 9-7 | 环境 | 环境 | 建环境（英文名）→加服务→调试容器/日志/Ingress/PVC | 服务、命名空间 | 服务 Running |
| 9-8 | 模板 | Dockerfile/构建/YAML/Helm | 建 Dockerfile→构建模板（Ubuntu20.04+软件包）→YAML 模板 | 模板库 | 模板可跨服务复用 |
| 9-9 | 产品工作流 | 产品工作流 | 建工作流→建构建→执行；仓库缺镜像→建仓库 | 9-8 | 构建+部署成功（3m09s+58s） |
| 9-10 | 自定义工作流 | 阶段/任务/审批 | 构建→审批→部署，引用"其他任务输出" | 9-9 | 分阶段可见、可卡点 |
| 9-11 | 构建缓存 | 缓存规则/NFS/StorageClass | 4 种目录规则→集群高级配置→构建挂载 | NFS+SC | 二次构建加速 |
| 9-12 | 持久化实战 | Node + npm store | 挂 PVC→拷代码→npm store→build | 9-11 | 依赖包持久化 |
| 9-13 | 测试与扫描 | pytest + SonarQube | 建测试→报告目录；建扫描→projectKey | Sonar Token | 报告可查；社区版无门禁 |
| 9-14 | 集成 Jenkins 构建 | Jenkins + image 变量 | 建 Jenkins 构建→传 image 变量 | 9-5 | 时间戳 tag 镜像并部署 |
| 9-15 | 项目实战 | 全链路 | 构建→扫描→测试→审批→部署 | 9-8/10/13/14 | 端到端 |
| 9-16 | 小结 | — | 两类工作流/模板/集成 | — | — |

> "描述模糊"集中处：8-1、8-3（卸载命令）、8-12（CLI 名全缺）、8-16（GitOps 实现载体）、8-24（def 子命令残缺）、9-1、9-6（"添加构件"含义）、9-11（缓存规则描述绕）。

## 2. 技术栈与版本线索

| 原文残片（行号） | 推断 | 判定 |
|---|---|---|
| "vela CLI / vela install / 插件 addon"（L16-17） | KubeVela v1.x（版本号原文从未出现） | 【实】有 CLI，版本【疑】 |
| "二点三点四"（L62） | velaux 或 ldap 插件版本 2.3.4 | 【推】 |
| "flag CD / d1插"（L54、L61） | fluxcd addon（ldap 的依赖）、ldap addon | 【推】高置信 |
| "新机械发布的插件"（L154、L157） | rollout（金丝雀/灰度）插件 | 【推】 |
| "一点一八版本"安装脚本（L465、L473） | Zadig v1.18.0 | 【实】 |
| "一点一六到一点二六"（L463） | K8s 1.16–1.26 | 【实】（现已过时） |
| "mongo≥3.4、mysql≥5.7"（L463） | 同上 | 【实】 |
| "mysql 最新版本镜像 / mongo 最新镜像"（L467-468） | 未锁 tag，实际为 latest | 【实】 |
| 集群 1.25 + Zadig 1.18（L466） | 演示环境版本组合 | 【实】 |
| "乌班图二十点零点四"（L609、L707） | Ubuntu 20.04 构建环境 | 【实】 |
| "够点一点一三"（L613） | Go 1.13 软件包 | 【推】 |
| "no 16 / 十六点二零点二"（L707-708） | Node 16.20.2 | 【实】 |
| "JAVA 17/19/1.8.0.20/1.11"（L613） | JDK 软件包列表 | 【实】 |
| "nginx 一点二零"覆盖策略（L338-340） | nginx:1.20 镜像 | 【实】 |
| "in jest / if no person"（L420） | ingress-nginx、imagePullPolicy: IfNotPresent | 【推】高 |
| "star poi"（L421） | startupProbe | 【推】 |
| "43200 秒"暂停超时（L422） | 12 小时 | 【实】 |
| "argo CD 的插件"（L46） | 仅提及 Argo CD 插件存在 | 【实】 |
| "sonarqube 三点零版本"（L730） | 指官网文档 3.0，非产品版本 | 【疑】 |
| "nfs 20G / 100G / 50G"（L470、L692、L703） | PV/PVC 容量 | 【实】 |
| NodePort 32760、10.0.7.101（L472、L488） | Zadig 访问入口 | 【实】 |
| 10.0.7.100 / 10.0.7.30 / 10.0.7.11（L20、L467、L470） | KubeVela 节点 / 数据库+LDAP / NFS | 【实】 |
| "cue"经 `go install`（L361） | CUE 由 Go 安装，无版本 | 【实】命令不完整 |

## 3. ASR 术语对照表

| 转写词 | 可能含义 | 依据（行） | 置信度 |
|---|---|---|---|
| 库贝维拉/酷比维拉/科比维拉/为了 | KubeVela | L6、L16、L54 | 高 |
| 扎迪格/野地/原地/约定/ED/ead/eid | Zadig | L446、L453、L463 | 高 |
| k八十/k8式/可以把/克 | Kubernetes | L7、L18、L45 | 高 |
| 执行/矩形/机型/局形 | 集群 | L36、L91、L201 | 高 |
| 样文件/压文件/点亮/点样 | YAML | L91、L272 | 高 |
| 破/炮 | Pod | L21、L189 | 高 |
| 收尾/收益/设备/外部收益 | Service / webservice | L105、L142、L159 | 高 |
| 执行IP | ClusterIP | L80、L420 | 高 |
| include | Ingress（也混用于 Service 语境） | L18、L594 | 中 |
| 克/课/客 | CUE | L361 | 高 |
| 欧佩克/OEM | OAM | L38 | 高 |
| 基本量/一本lab/杰lab | GitLab | L275、L418 | 高 |
| 真体式/真题式/专题式/专个 | Jenkins | L742、L746 | 高 |
| sola/收纳/搜拉q/说了 | SonarQube | L523、L724 | 高 |
| hl/hell/have 模板 | Helm 模板 | L610、L626 | 高 |
| 多克菲尔/dog fare/doc fire | Dockerfile | L607、L611 | 高 |
| 乌班图 | Ubuntu | L609 | 高 |
| 加副/交互目标 | 交付目标 | L36 | 高 |
| demo 组件 | DaemonSet | L315 | 中 |
| com-touch/com-pass | CronJob | L313 | 中 |
| get way | ingress（或 gateway）运维特征 | L324、L402 | 中 |
| 飞速/丁丁 | 飞书/钉钉 | L288、L353 | 高 |
| 二零/杭州二零/凸巴克 | 阿里云（杭州）、镜像仓库命名空间 | L511、L652 | 低 |

## 4. 问题清单

| 行号 | 类别 | 问题 |
|---|---|---|
| L16-22 | 缺步骤 | vela CLI 下载脚本、`vela install` 参数、addon 版本全部被吞，**无法复现** |
| L19 | 缺步骤 | velaux 外接 MongoDB 只给字段名，无连接串/证书/TLS |
| L54-62 | 依赖错序 | ldap 依赖 fluxcd+velaux 的约束口述混乱；"装不上就换 2.3.4"属试版本而非受控版本 |
| L58-67 | 不安全 | 以"邮箱相同"继承本地管理员权限＝弱身份绑定；"别用同一浏览器测试"暴露无 break-glass 管理员 |
| L80 | 前提缺失 | 交付目标强绑命名空间，未讲 namespace 预创建与权限 |
| L94、L201 | 环境假设 | 复制同一 kubeconfig 冒充第二集群，**多集群从未真正验证** |
| L124 | 缺步骤 | 只读/接管模式未与 RBAC、多租户风险关联 |
| L143、L146 | 缺说明 | 默认 1024Mi/0.5C 未解释来源；未提 requests/limits 实践 |
| L164 | 缺步骤 | 验证仅说"临时起容器、装个 curl"，无 `kubectl run` 与命名空间参数 |
| L172、L215/221 | 不一致 | 超时先后说 30 秒、60 秒；`vela workflow resume` 等命令名缺失 |
| L247-251 | 缺步骤 | `vela adopt` 未提 OwnerReference、后续删除/漂移风险 |
| L259-264 | 不安全 | Webhook 触发器无鉴权、无幂等/重放说明 |
| L274-279 | 不安全 | GitLab 账号密码 base64 写进 YAML（非加密）；1 分钟轮询＝非事件驱动 |
| L338-341 | 事实矛盾 | override 示例 nginx 1.20 与"last/latest"混述 |
| L382-383 | 教学反例 | 生成的 CUE 硬编码镜像并自认"不能复用"，未给参数化正解 |
| L418-425 | 缺步骤 | 删除应用会被 GitOps 重建；未提 prune/finalizer 与回滚策略 |
| L463-465 | 过时 | K8s 1.16–1.26 区间已过时；"1.18 以上都要付费"是过度简化 |
| L467-472 | 不安全 | mysql/mongo 用 latest；NodePort 32760 + 弱口令（mooc6666）暴露公网 IP |
| L483、L508 | 缺说明 | 社区版"生产集群=否"、灰色提供商不可选，未解释能力边界 |
| L512 | 不安全 | ACR 固定密码明文入库，未提 RAM 子账号/临时凭证 |
| L594-597 | 事实约束 | 环境仅支持 Deployment/Service，Ingress/PVC 需单独添加，易误解为全支持 |
| L651-652 | 环境假设 | 私有仓库缺 nginx 镜像导致构建失败，示例强依赖外部镜像仓库 |
| L726、L732 | 能力缺口 | 社区版无质量门禁 → 扫描不阻塞发布，与"企业级实战"标题冲突 |
| L766-767 | 过程瑕疵 | 实战失败后靠删步骤绕过，非受控修复 |

## 5. 实验依赖关系

- **KubeVela 链**：K8s（≥1 集群）→ vela CLI → `vela install` → velaux → NodePort →〔fluxcd → ldap〕→ OpenLDAP → 项目/命名空间 → 交付目标 → first-app →〔rollout〕→ 金丝雀 →〔Git 仓库〕→ GitOps →〔Jenkins〕→ 触发器 →〔Go+cue〕→ 自定义模板 → 8-26 综合实战。
- **Zadig 链**：K8s 1.16–1.26 →〔MySQL+Mongo（独立主机 compose）〕→〔NFS+PV〕→ install 脚本 → NodePort → LDAP/集群/ACR →〔Jenkins+GitLab+Sonar〕→ 项目 → 服务 → 环境 → 模板（9-8）→ 工作流（9-9/9-10）→ 缓存（9-11）→ 持久化（9-12）→ 测试扫描（9-13）→ 9-14 → 9-15。
- 硬依赖：8-11/8-21 需第二集群（原文未真实提供）；8-16/8-26 需可用 Git 服务；9-9 起需可推送的私有仓库；9-12 需 StorageClass。**单机可复现度低。**

## 6. 可信度与处置建议

| 章 | 可信度 | 理由 | 建议 |
|---|---|---|---|
| 8 KubeVela | **B** | 概念体系（OAM/组件/特征/策略/工作流）讲得完整；但命令几乎全丢、版本缺失、多集群未真验 | **改造后采用**：仅取概念与 YAML 结构，命令需按官方文档重写 |
| 9 Zadig | **B-**（实战段 C+） | 流程完整、有失败排查；但版本过时、企业版功能占比高、多处靠删步骤过关 | **改造后采用**（模板/工作流/缓存思路）＋**仅作对比**（部署与商业能力） |

## 7. 选型对比要点

| 维度 | KubeVela | Zadig | Argo CD |
|---|---|---|---|
| 独特价值 | 应用交付抽象（OAM+CUE），组件/特征/策略可编程，多集群交付目标 | CI+CD+测试+环境一体，多服务并发构建、模板化、环境管理 | GitOps 事实标准：声明式同步、diff、一键回滚、App of Apps |
| 工作流 | 内置 deploy/suspend/notification/timeout，弱于专业 CI | 产品工作流（开箱）+ 自定义阶段/审批 | 无 CI；靠 ApplicationSet/Sync Wave 编排 |
| 多集群 | 原生（交付目标=集群+命名空间） | 社区版受限（生产集群=否），企业版才完整 | 原生（多 cluster 注册） |
| 运维成本 | 中高：控制面+插件+CUE 学习曲线 | 高：MySQL+Mongo+NFS+私有仓库，构建机 8G 规格 | 低：单 Deployment，kind 即可 |
| 单 Mac 学习项目适配 | 中（kind + addon 可跑，CUE 门槛高） | 低（组件多、资源重、版本锁 1.18） | **高**（最小成本、生态标准） |

## 8. 对现代工程的迁移提示

- **KubeVela**：已进入 CNCF 孵化，2025 年社区仍有年度总结（[State of KubeVela 2025](https://github.com/kubevela/kubevela.github.io/blob/main/blog/2025-12-20-state-of-kubevela-2025.md)），但热度明显低于 Argo CD；教学应讲"抽象思想"，落地前需核实目标版本与插件维护状态。
- **Zadig**：开源版自 v2.0 起与企业版合并、按 License 解锁（[v2.0 公告](https://koderover.com/blog/zadig-v2.0/)），故"1.18 以上全收费"不准确；企业级能力（质量门禁、生产集群）本就是商业边界。
- **Argo CD**：CNCF 毕业项目，GitOps 默认答案；建议本项目以 Argo CD（+Rollouts 做金丝雀）为主线，KubeVela/Zadig 降为"交付抽象/一体化平台"的对照案例。
- 通用迁移：镜像用 digest 固定、凭据走 Secret/External Secrets、触发器加签名、GitOps 用事件驱动（webhook）替代轮询。
