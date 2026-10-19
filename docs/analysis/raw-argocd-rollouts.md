# 第10章 Argo CD + Argo Rollouts — 原文索引与可行性报告

> 来源：`docs/course-materials/argocd-rollouts.md`（353 行，ASR 转写）。**原文事实**=课文明确说过；**推断**=据上下文/常识还原；**无法确认**=证据不足。行号指原文行。全章无任何明确版本号。

## 1. 章节清单

| 节 | 主题 | 工具/技术 | 关键操作 | 前置 | 预期 |
|---|---|---|---|---|---|
|10-1|概述|ArgoCD/Rollouts|课程路线口述|无|建立地图（描述模糊）|
|10-2|ArgoCD 介绍|GitOps、声明式|定位：Git 为源、同步到集群、多集群|无|概念|
|10-3|部署|argocd install.yaml、CLI|建 ns→apply→装 CLI→改 NodePort→取初始密码→登录|K8s 集群|admin 登录页|
|10-4|Application 介绍|Application、Helm|cluster add、repo add、source+destination、多源、外部 values|集群+Git 仓|应用本体|
|10-5|实战|argocd CLI|`--upsert` 加集群、加仓库、apply app、手动 sync|10-3/10-4|guestbook 就绪|
|10-6|ApplicationSet|List generator|列表生成、`{{cluster}}`/`{{url}}`、整组删除|10-5|一次生成 3 应用|
|10-7|同步选项|syncPolicy/syncOptions|ignoreDifferences、automated/prune/selfHeal、6 个 syncOptions、retry、状态|10-5|字段理解|
|10-8|执行|同上|UI/CLI 勾选验证、replicas 忽略实验|10-7|忽略生效|
|10-9|删除/回滚/Webhook|`/api/webhook`|history 回滚、rs 看多 Pod 日志、全局/局部 sync、webhook、delete|10-5、外部可达|推送即同步|
|10-10|横幅与终端|argocd-cm|bannercontent/url/permanent/position、exec 开关|10-3|横幅+终端入口|
|10-11|LDAP|OpenLDAP+Dex|dex.config、密码注入终端、组过滤、重启 Pod|LDAP 服务|能登录但无权限|
|10-12|权限|argocd-rbac-cm|policy.csv 的 p/g、role:readonly/admin、logs/exec、改密|10-11|可 sync 不可 delete|
|10-13|CLI|argocd CLI|login/list/get/delete/sync/prune/self-heal|10-3|命令行操作|
|10-14|Rollouts 介绍|Argo Rollouts|蓝绿/金丝雀/分析/回滚定位|无|概念|
|10-15|蓝绿介绍|—|**内容与 10-13 完全相同**（211-212=197-198）|—|内容缺失（描述模糊）|
|10-16|灰度介绍|canary|金丝雀、传统 5 nginx 对比、stable/canary、80/20|无|概念|
|10-17|蓝绿实战|—|**内容与 10-16 完全相同**（229-234=218-222）|—|无实战（描述模糊）|
|10-18|灰度实战|Rollout canary|5 副本、maxSurge25%/maxUnavailable0、setWeight10→pause60s→20→人工 pause、dashboard|Rollouts 控制器|渐进放量|
|10-19|分析模板+Istio/Prom|Istio/Envoy/Prometheus|curl 装 istioctl、软链、注入标签、istio addons 装 Prom|内存充足|sidecar+指标|
|10-20|模板配置|AnalysisTemplate|metrics/successCondition/provider.prometheus/query/interval/`steps[].analysis`|10-19|指标驱动|
|10-21|蓝绿自动回滚|blueGreen+analysis|忽略 hash 差异、Prom `:9090`、3 次采样、失败回滚|10-19/10-20|自动回滚|
|10-22|灰度自动回滚|canary+analysis|第二步引用 analysis、空值兜底表达式、failureLimit=3|10-21|失败即回滚|
|10-23|获取部署状态|脚本+CLI|60s 轮询 sync/health、超时退出、报警|10-5|报警联动|
|10-24|三工具对比|KubeVela/"耶蒂"/ArgoCD|定性对比（"耶蒂"无法确认）|无|选型|
|10-25|总结|—|三块重点复盘|无|—|

## 2. 技术栈与版本线索

| 技术 | 原文（乱码） | 还原 | 判定 |
|---|---|---|---|
| Argo CD | "arc CD/阿狗CD/阿克CD/阿口CD/accd/roc d"（13、52、190） | Argo CD | 明确 |
| Argo Rollouts | "阿狗落up/阿格罗二/肉outs/low up/阿波罗二"（6、204、340） | Argo Rollouts | 明确 |
| Istio | "institute/19/一四九/issue/e/ever/m代理"（255-257） | Istio + Envoy sidecar | 明确 |
| Istio 版本 | "一点二二点二"（259） | 1.22.2（软链 `/usr/local/istio`、随后执行 istioctl） | **推断**（中） |
| Prometheus | "普罗米修斯/普罗米斯斯"（254、284） | 由 istio addons 装在 `istio-system`，端口 9090 | 明确（部署方式）/版本**无法确认** |
| AnalysisTemplate | "分析模板/密测/指标列表"（267） | AnalysisTemplate + metrics | 明确 |
| CLI | "accd or com update-password/ectl/get point"（190、259） | `argocd account update-password`、`istioctl`、`kubectl get pods` | 明确/推断 |
| Argo CD 版本 | 无 | 多源 Application（45、68）+ ApplicationSet（80）推断 ≥2.6；初始密码来自 Secret（22-23）推断 ≥1.9 | **推断**，不写版本号 |
| K8s/Rollouts/Helm chart 版本 | 无 | — | 无法确认 |

## 3. ASR 术语对照表

| 原文 | 可能含义 | 依据 | 置信度 |
|---|---|---|---|
| 阿哥cd/arc CD/a口CD/阿克CD/阿西街 | Argo CD | 6、13、52、190 | 高 |
| 肉outs/阿狗罗话/阿格罗二/aquila 2/阿波罗二 | Argo Rollouts | 6、204、230、340 | 高 |
| k八十/k8s/k八四/k80/可以把s/kiss | Kubernetes | 13、257、338 | 高 |
| 样文件/压文件/亚文件/加文件/样本线 | YAML 清单 | 20、42、62 | 高 |
| 基库/基本仓库/地板仓库/帝国仓库/keep、gip仓库/第8列 | Git 仓库（repo） | 30-31、55、125 | 高 |
| goffs/第二次 | GitOps | 13、340 | 中（推断） |
| decision | destination（目标集群/ns） | 41-43 | 高 |
| thing/性/胜/肾/线 | sync（同步按钮） | 63、71、119 | 高 |
| 比例/迪丽/delete | delete | 83、189 | 高 |
| 落/乱/漏 | logs | 140、149 | 高 |
| 破/po/剖/炮/坡/报 | Pod | 66、221、245 | 高 |
| 色域/收益 | Service | 65、68 | 中 |
| 触/触发 | true | 157、182 | 高 |
| 波层 | bottom（banner 位置） | 157 | 中 |
| APP location (set)/APP vacation 线 | Application / ApplicationSet | 42、80、144 | 高 |
| 第一叉/第一叉 point config | Dex（`dex.config`） | 167-168 | 高 |
| open ld/lt 用户 | OpenLDAP | 167、171 | 高 |
| 楞/与造林/比造零 | `len(result)` / `isNaN`（空值兜底） | 283、309 | 中（推断） |
| 库比维拉 | KubeVela | 338 | 高 |
| 耶蒂/约定/ID | 某 CI/CD 工具（Jenkins/GitLab CI/Tekton 之一） | 338-339 | **低，无法确认** |
| 课/另/m1 | curl / ln / mv | 20、257 | 中 |

## 4. 问题清单

**事实/编辑错误**
1. 10-15、10-17 整段复制错位：211-212 抄自 197-198，229-234 抄自 218-222 → 蓝绿「介绍」与「实战」实际缺失，只有 10-21 补了蓝绿实战。
2. RBAC 资源名写成 "APP location/Application"（182）；`policy.csv` 第二列应为 `applications/clusters/projects/applicationsets/logs/exec`。
3. 把"同步失败"当 sync status（107-108）；实际 sync status 仅 Synced/OutOfSync/Unknown，Failed 属 operation phase。
4. "终端删除只删 Application、不删 K8s 资源"（143-144）：是否级联取决于 `resources-finalizer` 与 `--cascade`，默认级联删除。
5. "selfHeal 不可开启，否则回滚失效"（97-100）：selfHeal 是与 Git 收敛的设计目标，正确回滚方式是把 Git 回退，而非关 selfHeal。
6. 灰度"最少需要两个副本"（242）无依据；"pause 一个小时"（241）与实操 60 秒（244）自相矛盾；"20% 流量"（241）被讲成累计，`setWeight` 实为绝对权重。
7. 容器终端"默认关闭、加两行即开"（157）：需 `exec.enabled` **且** RBAC `exec` 授权，原文未点明。
8. "部署失败状态要 20–25 分钟才显示"（331）无依据，属环境个例。

**缺失步骤**：repo 凭证安全（`repo-creds`/SSH/TLS，仅 55 行明文用户名密码）；AppProject 的 `sourceRepos/destinations/roles`（只当"分类"提，57、184）；sync waves/同步顺序（完全未讲，103-104 只是 prune 顺序）；自定义 health check；Rollouts 与 Istio VirtualService/DestinationRule 的绑定（10-18 讲流量权重却未说流量由谁切）；`kubectl argo rollouts undo/promote` 未提；image updater 未提；webhook secret 与 ingress/TLS 未提。

**不安全实践**：NodePort 暴露 + "点高级继续"跳过证书告警（23）；初始密码明文展示（22）；弱口令示例 666666（190-191）；脚本内硬编码用户名密码（328-329）；webhook 关闭 SSL 校验（146）；repo 密码直接写命令行（55）。

**环境假设**：必须自建 Istio+Prometheus（19、253）；多节点/大内存；NodePort 直连 `10.0.7.101:31650`（23）；webhook 需外部可达；需可重启的 LDAP 与 argocd Pod（172）。

## 5. 实验依赖关系

`10-3 → {10-4→10-5} → {10-6, 10-7→10-8, 10-9, 10-10, 10-13}`；`10-11 → 10-12`（LDAP 组是 RBAC 主体）；`10-5 → 10-14~10-18`（另需 Rollouts 控制器+dashboard）；`10-19 → 10-20 → {10-21, 10-22}`（强依赖 Istio 注入与 `istio-system` Prometheus）；`10-5 → 10-23`；10-24/10-25 无环境。断点：10-15/10-17 无内容；10-21/10-22 不可在无 Istio 环境复现。

## 6. 可信度与处置建议

| 小节 | 可信度 | 建议 |
|---|---|---|
|10-2、10-14、10-16、10-25|A|直接采用（概念层）|
|10-4、10-7、10-13、10-20|A|直接采用（字段/机制描述基本准确）|
|10-3|B|改造后采用：Ingress+TLS、密码走 Secret|
|10-5、10-8|B|改造后采用：补 repo-creds、去掉手点流程|
|10-6|B|改造后采用：补 `applicationsSync`、cluster/git 生成器|
|10-9|B|改造后采用：补 webhook secret、级联删除说明|
|10-10|B|改造后采用：补 exec RBAC|
|10-12|B|改造后采用：改资源名、最小权限、去弱口令示例|
|10-18|B|改造后采用：修正 pause 时长与 setWeight 语义|
|10-21、10-22|B|改造后采用（本地降级为副本级）|
|10-23|C|改造后采用：改用 token/CI 内调用，勿硬编码|
|10-11|C|**不纳入**（LDAP 成本高、与本项目无关）|
|10-15、10-17|C|**不纳入**（内容缺失，需重录）|
|10-24|C|仅作对比（"耶蒂"不可确认，且缺 Flux/Spinnaker）|

## 7. GitOps 关键机制：原文 vs 真实 Argo CD

| 机制 | 原文说法 | 实际模型 |
|---|---|---|
| Application | source+destination+project 两处必配（41-43），多源（44-45） | 正确；漏 `syncPolicy`、`revisionHistoryLimit`、`finalizers` |
| ApplicationSet | List 生成器 + `{{}}` 变量（80-82）；删单个会被重建（83-84） | 基本正确；漏 cluster/git/matrix 生成器、`applicationsSync`、`preserveResourcesOnDeletion`；删除应改生成器而非只删 YAML |
| AppProject | 仅"分类"（57、184） | 未讲 `sourceRepos`/`destinations`/`namespaceResourceWhitelist`/project role，隔离能力被弱化 |
| syncPolicy | automated/prune/selfHeal 讲清（95-100），结论"selfHeal 别开"偏 | `selfHeal` 生产推荐；回滚应回退 Git；`allowEmpty` 确实应关 |
| sync waves | **完全未提** | `argocd.argoproj.io/sync-wave` + `syncOptions` 才是顺序编排，原文用 prune 顺序代替，属概念缺口 |
| health | Healthy/Degraded/Progressing/Suspended/Missing（108-110） | 正确，漏 Unknown 与自定义 `health.lua` |
| rollback | UI history 按 commit 回滚（139、148） | 正确（revision 指针），但未解释与 selfHeal 冲突的根因 |
| drift | 3 分钟轮询 + diff（62、145） | 正确（默认 3m）；未讲比较算法、`ignoreDifferences` 的 jq/jsonPointer/managedFields 三种写法 |
| webhook | `/api/webhook`（142） | 路径正确；漏 secret、事件类型、需公网可达 |
| RBAC | `p`/`g` 行、`role:readonly`/`role:admin`（182-188） | 模型正确，资源名错（见问题 2） |

## 8. 单机 Mac + kind/k3d 可行性

| 项 | 结论 | 说明 |
|---|---|---|
| Argo CD | **可以** | k3d 单节点即可；约 5 个 Pod、~1–1.5 GiB，repo-server 最吃内存；可去掉 dex |
| Argo Rollouts | **可以** | controller+dashboard 两 Deployment，轻量；但无 Istio 时 `setWeight` 只按副本比例，**不是真实流量比例**，报告中必须写明 |
| Istio+Prometheus 分析 | **可以但重** | istiod+ingressgateway+Prometheus ≈1.5–2 GiB，kind 需 extraPortMappings；建议 `profile=minimal` + addons |
| 资源成本 | 全量约 4–5 GiB/4 vCPU | 8 GiB Docker VM 可跑，需先关 Docker 其他负载 |
| 建议延后 | Istio/Prometheus 分析、LDAP、HA/ingress | Phase-0 只做 Argo CD + Rollouts（副本级金丝雀/蓝绿）+ `kubectl argo rollouts get rollout -w`；分析模板先用 Job/HTTP 探针替代 |
| 明确不复刻 | NodePort `10.0.7.101:31650`、多节点、公网 webhook | 换 `kubectl port-forward` |

## 9. 可复用清单要点

- **Application**：`metadata.{name,namespace}`、`spec.project`、`source.{repoURL,path,targetRevision}`、`destination.{server,namespace}`、`sources[]`（多源，45、68）、`source.helm.valueFiles`（46）、`ignoreDifferences`（93）、`syncPolicy.automated.{prune,selfHeal}`、`syncOptions`（127）。
- **syncOptions 取值**：`Validate`、`CreateNamespace`、`PruneLast`、`ApplyOutOfSyncOnly`、`ServerSideApply`、`RespectIgnoreDifferences`、`PrunePropagationPolicy=foreground`（101-105，原文逐条描述但未给字面值——字面值为推断）。
- **Rollout**：`spec.replicas`（5）、`strategy.canary.{maxSurge:25%,maxUnavailable:0}`、`steps[].setWeight`、`steps[].pause{}`（人工）/`pause.seconds`（241-243）、`stableService/canaryService`；蓝绿用 `strategy.blueGreen`。
- **AnalysisTemplate**：`spec.metrics[].{name,interval,failureLimit,successCondition,provider.prometheus.{address,query}}`（267-272）、`args[].{name,value}`、Rollout 侧 `steps[].analysis.templates[]+args[]`（272）。
- **兜底表达式**（282-283）：空结果/NaN 视为通过 —— `len(result)==0 || isNaN(result[0]) || result[0] > 0.95`（原文 `楞/与造林` 的还原为推断）。
