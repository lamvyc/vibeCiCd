# 运行手册（Runbook）

> 本手册对应 2026-10-20 的实际运行环境。所有服务均为本地/隔离环境，不暴露公网。

## 1. 运行位置与端口

| 组件 | 位置 | 地址/端口 |
|---|---|---|
| Gitea 28.2.0 | Colima VM 内 Docker（host network） | 宿主 `http://127.0.0.1:3000/`（SSH local forward） |
| Jenkins 2.580.1 | Colima VM 内 Docker（官方镜像派生工具镜像，host network） | `http://127.0.0.1:8081/`（SSH local forward → VM `8081`）；旧 WAR 可选保留 |
| Zot 2.1.22 | Colima VM 内 Docker | `127.0.0.1:5001`（VM 与宿主） |
| k3s v1.35.0+k3s1 | Colima VM 内进程 | API `https://127.0.0.1:16443`（SSH tunnel） |
| Argo CD 3.5.5 | k3s `argocd` namespace | `kubectl -n argocd port-forward svc/argocd-server 8443:443` |
| 应用 dev | k3s `lowcode-dev` | `kubectl -n lowcode-dev port-forward svc/lowcode-web 18081:80` |
| Prometheus 3.8.0 | k3s `monitoring` | `kubectl -n monitoring port-forward svc/prometheus 19090:9090` |
| CI 桥 | macOS 宿主进程 | 轮询 Gitea，触发 Jenkins（webhook 回退） |

凭据：`.env.local`（mode 600，gitignored）。`kubectl` 配置：`.runtime/kubeconfig`。Docker socket：`.runtime/colima/default/docker.sock`。

## 1.1 首次初始化（仅全新数据目录时）

Gitea 的用户/仓库/token 需要先初始化；当前运行形态是 VM 容器，首次可用宿主原生 Gitea 初始化数据，再迁移到容器：

```bash
# 仅首次；会占用宿主 3000
./scripts/bootstrap/10-gitea.sh
kill "$(cat .runtime/gitea/gitea.pid)" 2>/dev/null || true
./scripts/bootstrap/15-gitea-container.sh
./scripts/bootstrap/20-repos.sh     # 推送应用/平台仓库
./scripts/bootstrap/30-wire.sh      # webhook（受限制）+ 分支保护
```

已有 `.runtime/gitea` 数据时跳过本节。

## 2. 一键启动（推荐）

```bash
cd /Users/unravel/vibeCiCd
./scripts/bootstrap/90-start-all.sh
```

顺序：Colima → Zot → k3s/API 隧道 → Gitea → Jenkins 宿主访问（转发）→ Jenkins → Argo CD → Prometheus → CI 桥。
若 Colima 已停止，脚本会重建 VM 连接；k3s 数据、Gitea/Zot 数据、Argo CD/K8s 状态均在 VM 磁盘持久化。

Jenkins 运行形态由 `JENKINS_RUNTIME` 选择（默认 `container`）：

```bash
./scripts/bootstrap/90-start-all.sh                    # 容器（官方镜像），默认
JENKINS_RUNTIME=war ./scripts/bootstrap/90-start-all.sh # 回滚到宿主 WAR
```

两种形态各自使用独立 JENKINS_HOME：容器用 `.runtime/jenkins-container`（WAR 数据的副本），
WAR 用 `.runtime/jenkins`。脚本在切换时会停掉另一种形态并交换 8081 的 SSH 转发，
数据与 `.tools/jenkins.war` 始终保留。详见 `docs/verification/jenkins-container.md`。

## 3. 手动启动顺序（排错用）

```bash
source scripts/lib/common.sh
source versions.env

# 1. VM
colima start --cpu 6 --memory 8 --disk 60

# 2. DNS（若 /etc/resolv.conf 缺失）
colima ssh -- sudo sh -c 'rm -f /etc/resolv.conf; printf "nameserver 114.114.114.114\nnameserver 8.8.8.8\n" > /etc/resolv.conf'

# 3. registry
./scripts/bootstrap/40-registry.sh

# 4. k3s + SSH tunnel 16443
./scripts/bootstrap/50-k8s.sh

# 5. Gitea 容器 + host local forward 3000
./scripts/bootstrap/15-gitea-container.sh

# 6. Jenkins（容器；含 JCasC、KUBECONFIG、DOCKER_HOST、代理变量）
JENKINS_CONTAINER_PORT=8081 ./scripts/bootstrap/21-jenkins-container.sh start
#   回滚到 WAR 时改为：./scripts/bootstrap/20-jenkins.sh

# 7. Argo CD 与 Prometheus
./scripts/bootstrap/70-argocd.sh
./scripts/bootstrap/80-prometheus.sh

# 8. CI 桥
./scripts/bootstrap/60-bridge.sh start
```

## 4. 验证命令

```bash
# 服务
curl -fsS http://127.0.0.1:3000/api/v1/version
curl -fsS -u "$JENKINS_ADMIN_USER:$JENKINS_ADMIN_PASSWORD" http://127.0.0.1:8081/api/json
curl -fsS -u "$REGISTRY_USER:$REGISTRY_PASSWORD" http://127.0.0.1:5001/v2/_catalog

# K8s / Argo CD
export KUBECONFIG=$PWD/.runtime/kubeconfig
kubectl get nodes
kubectl -n argocd get applications
kubectl -n lowcode-dev get deploy,pods

# 部署业务验证
./scripts/deploy/verify-deploy.sh dev <full-sha> <tag>

# Prometheus
kubectl -n monitoring port-forward svc/prometheus 19090:9090
curl -s 'http://127.0.0.1:19090/api/v1/query?query=up'
```

## 5. 触发构建

- 正常：向 `lowcode-platform` 的 `main`/feature/PR 推送提交；CI 桥在 ≤8s 内触发。
- 手动：

```bash
jenkins_cli build lowcode-platform \
  -p APP_REF=refs/heads/main \
  -p APP_SHA=<full-sha> \
  -p PUBLISH_IMAGE=true -p GITOPS_ENABLED=true -p DEPLOY_ENABLED=true
```

> 手动触发必须提供完整 40 位 `APP_SHA`。缺省时 Jenkins 不会导出空的
> `APP_SHA_RESOLVED`，Jenkinsfile 的 `set -u` 会在 Go 阶段报 `parameter not set`。
> 这是迁移前既有行为（webhook 触发总会带 `PAYLOAD_AFTER`）。

- Webhook 端点仍保留：`/generic-webhook-trigger/invoke`，Bearer token 在 `.env.local`。当前沙箱 egress 策略阻断 Gitea→Jenkins，详见 `docs/verification/environment-limitations.md`。

## 6. 回滚

```bash
# 默认 dev；脚本会 revert 最后一个 chore(gitops) 提交、push、刷新 Argo CD、验证
./scripts/deploy/rollback.sh dev
```

紧急情况下也可在 Argo CD UI/CLI 使用历史回滚，但必须再用 Git revert 对齐，避免 selfHeal 把状态拉回错误版本。

## 7. 常见故障

| 现象 | 处理 |
|---|---|
| Docker 拉取报 `lookup ... [::1]:53` | 修复 VM `/etc/resolv.conf`（见上） |
| `colima ssh` 卡住 / Docker socket 拒绝 | `colima stop --force` 后 `90-start-all.sh`；数据保留 |
| `kubectl` 连接 16443 拒绝 | 重新执行 `50-k8s.sh` 建立 SSH 隧道 |
| Gitea 宿主 3000 不可达 | 重新执行 `15-gitea-container.sh`；检查 `lsof -iTCP:3000` |
| Argo CD `ComparisonError` | `kustomize build gitops/overlays/dev` 本地复现；修正后 commit/push，`kubectl annotate ... refresh=normal` |
| Argo CD 长时间不刷新 | 默认 3 分钟轮询；执行 `kubectl -n argocd annotate app lowcode-dev argocd.argoproj.io/refresh=normal --overwrite` |
| 镜像拉取 `ImagePullBackOff` | 检查 `regcred`、镜像 digest、Zot 认证；`kubectl -n lowcode-dev describe pod` |
| `kubectl logs` EOF | 使用 `./scripts/deploy/logs.sh dev`（读取 VM 内 pod 日志文件） |
| Jenkins 启动后又退出 | 查看 `.runtime/logs/jenkins.log`（WAR）或 `docker logs vibe-jenkins`（容器）；删除 `.runtime/jenkins/jenkins.pid` 后重启 |
| Jenkins 容器起不来 / 8081 无响应 | `./scripts/bootstrap/21-jenkins-container.sh status`；确认没有 WAR 占用宿主 8081（`JENKINS_RUNTIME=war` 会切换形态）；`docker logs -f vibe-jenkins` |
| 容器内 `docker` 报 `Cannot connect ... unix:///Users/...` | 挂载的 `config.json` 带 `currentContext: colima`（宿主路径）；确认容器带 `DOCKER_HOST=unix:///var/run/docker.sock`（`21-jenkins-container.sh` 已设置） |
| 容器内 `kubectl` 连不上 API | 必须是 `.runtime/kubeconfig-container`（`server: https://127.0.0.1:6443`），不是宿主的 16443 隧道 |
| 构建时 `APP_SHA_RESOLVED: parameter not set` | 手动触发未传 `APP_SHA`；传完整 40 位 SHA（见 §5） |
| 插件安装/更新中心 404 或超时 | VM 内 8899 未启动；重跑 `21-jenkins-container.sh`（脚本会拉起 VM 本地 update center） |
| 桥重复触发 | 确认只有一个 `gitea-jenkins-bridge.py` 进程；`pkill -f gitea-jenkins-bridge.py` 后重启桥 |

## 8. 停止与清理

```bash
./scripts/bootstrap/60-bridge.sh stop
# 停 Jenkins
./scripts/bootstrap/21-jenkins-container.sh stop     # 容器形态（默认）
# 或 WAR 形态：
# kill "$(cat .runtime/jenkins/jenkins.pid)" 2>/dev/null || true
# 停 Colima（保留数据）
colima stop
# 彻底清理（危险：删除 VM/数据/镜像；需人工确认后执行）
# colima delete --force
```

`gitops/` 与 K8s 状态在 VM 磁盘；`.runtime/` 不进入 Git。清理 `.runtime` 会导致 Jenkins/Gitea/K8s 数据丢失。
