# 实施验收记录

> 日期：2026-10-20。所有结论来自本机实际执行；未验证项在「状态」列明确标注。
> 原始日志保留在 `.runtime/logs/`、`.runtime/deployments/`（不入 Git）。

## 1. 状态总览

| 任务要求 | 状态 | 证据 |
|---|---|---|
| Git 仓库、分支、PR、状态回传 | **已实现且已验证** | Gitea 28.2.0 容器；PR #1；`ci/jenkins` success；`main` 保护要求该状态 |
| Webhook 触发 | **已实现，受环境限制** | Hook 已配置；Gitea 日志显示 egress policy 阻断（下方）；轮询桥已替代并验证 |
| 自动构建触发回退 | **已实现且已验证** | `gitea-jenkins-bridge.py` 触发 build #7/#8/#9/#11/#12 |
| CI：检查/测试/构建 | **已实现且已验证** | build #11 全阶段 SUCCESS；#12 在 Test 失败 |
| 测试失败不发布 | **已实现且已验证** | #12 Test FAILED；registry 无 `sha-2c1dc0788184`（manifest 404） |
| Docker 镜像构建 | **已实现且已验证** | #11 Docker build / smoke SUCCESS |
| 镜像仓库推送与鉴权 | **已实现且已验证** | Zot 2.1.22；`docker login`；tags `sha-51de…`、`sha-3e9…` |
| 镜像拉取与启动 | **已实现且已验证** | Pod 事件 `Successfully pulled image … in 90ms`；2/2 Running |
| K8s 部署 | **已实现且已验证** | k3s v1.35.0+k3s1；dev Deployment 2/2 |
| Argo CD GitOps | **已实现且已验证** | Application `lowcode-dev` Synced/Healthy；revision 与 Git 一致 |
| 部署后健康/接口验证 | **已实现且已验证** | `.runtime/deployments/dev-sha-3e9cb2f34287.json`；`/api/version` commit 匹配 |
| 漂移检测/自愈 | **已实现且已验证** | `kubectl scale --replicas=5` → Argo 恢复 2；Synced/Healthy |
| 同步失败识别 | **已实现且已验证** | 错误 Kustomization → `ComparisonError`（下方） |
| 回滚 | **已实现且已验证** | `rollback.sh dev` 执行 git revert；恢复 3e9 并通过接口验证 |
| 质量门禁 | **已实现且已验证** | typecheck + 538 tests + build + Go tests；失败即阻断 |
| Prometheus 指标 | **已实现且已验证** | `up{job="lowcode-web"} = 1`；target healthy；规则已加载 |
| 日志/排查 | **部分实现** | 应用 JSON 日志、Jenkins 控制台、K8s events 可用；`kubectl logs` 受节点 IP 限制，见限制文档 |
| Webhook 直连（不依赖桥） | **受环境限制** | egress policy；不伪造为已验证 |
| Jenkins 运行形态迁移（WAR→官方镜像容器，保留数据与回滚） | **已实现且已验证** | build #14 在容器内全阶段 SUCCESS；控制器自检 build #4；切换后 8081 正常；详见 `docs/verification/jenkins-container.md` |

## 2. 关键构建与版本

| 项 | 值 |
|---|---|
| 应用仓库 main | `dde1a56ff5b901e525a729cd252dd2200a4fcc0f`（PR #2 merge；此前 `3e9cb2f34287…`） |
| 最终镜像 | `localhost:5001/lowcode-platform:sha-dde1a56ff5b9@sha256:6c60811e97e497a5685b6351b49a3a12478cb4de0c2b572b3ed62dc4084e36e7` |
| Jenkins | 2.580.1，Java 21.0.12，77 个插件；运行形态为官方镜像容器（`vibe-cicd/jenkins:2.580.1-tools-1`），WAR 形态保留可回滚 |
| CI | build #14 `SUCCESS`（容器化控制器，手动指定 SHA，全 17 阶段/含 GitOps/Deploy verify）；build #17 `SUCCESS`（Gitea push → 桥 → 容器控制器，全 18 阶段） |
| 失败演练 | build #12 `FAILURE`，Test 阶段 |
| Argo CD | v3.5.5（Helm chart 10.10.5） |
| K8s | k3s v1.35.0+k3s1，单节点 `colima` Ready |
| registry | Zot 2.1.22，htpasswd 认证 |
| Prometheus | v3.8.0，`up=1` |

## 3. 关键证据摘录

### 3.1 正常主分支构建（build #11）

```text
Checkout app: SUCCESS   Typecheck: SUCCESS   Test: SUCCESS
Build frontend: SUCCESS Quality gate: SUCCESS
Server test and build: SUCCESS
Docker build: SUCCESS   Image smoke test: SUCCESS   Push image: SUCCESS
GitOps update: SUCCESS  Deploy verify: SUCCESS
Finished: SUCCESS
```

### 3.2 部署验证

`scripts/deploy/verify-deploy.sh dev 3e9cb2f34287b92c3a2d12ab422a35c874d0664b sha-3e9cb2f34287`：

```json
{
  "sync": "Synced",
  "health": "Healthy",
  "image": "localhost:5001/lowcode-platform:sha-3e9cb2f34287@sha256:cd4ee6d44b181c007596eea66dd2e796f516d38849dfd9418238f66b88d6a1c6",
  "commit": "3e9cb2f34287b92c3a2d12ab422a35c874d0664b",
  "healthz": "{\"env\":\"dev\",\"status\":\"ok\"}",
  "readyz": "{\"env\":\"dev\",\"status\":\"ready\"}",
  "version": {"version":"sha-3e9cb2f34287","commit":"3e9cb2f34287b92c3a2d12ab422a35c874d0664b","env":"dev","goVersion":"go1.27.2"}
}
```

### 3.3 测试失败门禁（build #12）

分支 `feature/ci-fail`，commit `2c1dc0788184b95b0f696ad44486ace211cc4685`：

```text
Typecheck: SUCCESS
Test: FAILED
Build frontend: FAILED (skipped by earlier failure)
...
Push image: FAILED (skipped)
GitOps update: FAILED (skipped)
```

Registry 校验：

```json
{"name":"lowcode-platform","tags":["sha-3e9cb2f34287","sha-51de0d5e2bff"]}
GET .../manifests/sha-2c1dc0788184 -> 404
```

### 3.4 漂移自愈

```text
kubectl -n lowcode-dev scale deployment/lowcode-web --replicas=5
after-scale=2/5
after-selfheal=2
Application: Synced / Healthy
```

### 3.5 GitOps 同步失败与回滚

错误 commit `152e1f9` 使 `images` 列表缺少 `-`，Argo CD 报：

```text
ComparisonError: failed to generate manifest ... invalid Kustomization:
json: cannot unmarshal object into Go struct field Kustomization.images of type []types.Image
```

回滚：

```text
reverting 152e1f9
rollback pushed: 9428f581b44e981d5e2826107ee1d3dafce154cc
waiting for Argo CD application lowcode-dev (Synced/Healthy)
deployment "lowcode-web" successfully rolled out
deployment verified: .runtime/deployments/dev-sha-3e9cb2f34287.json
```

### 3.6 Prometheus

```text
query up{job="lowcode-web"} -> value "1"
target lowcode-web up (no lastError)
```

## 4. 状态语义

- `已实现且已验证`：有实际命令输出/状态/接口响应，且与预期一致。
- `受环境限制`：代码与配置已存在，但当前沙箱网络策略使其无法完成；原因与补充条件见 `environment-limitations.md`。
- 未列出的能力（SonarQube、Argo Rollouts、Istio、LDAP、MeterSphere、飞书）为**暂缓**，见 ADR-005。
