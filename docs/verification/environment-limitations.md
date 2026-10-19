# 环境限制与应对记录

> 这些是实测限制，不是推测。它们决定了哪些能力已验证、哪些只能标注受限。
> 复测日期：2026-10-20。

## 1. Docker Hub 不可达

- `registry-1.docker.io`、`auth.docker.io`、`hub.docker.com` 在 IPv4/IPv6 下均被连接重置。
- 影响：不能使用 `jenkins/jenkins`、`registry:2`、`nginx`、`node` 等 Docker Hub 基础镜像。
- 应对：
  - Jenkins 使用 WAR + 本机 Java 21；
  - 应用镜像 `FROM scratch`（Go 静态服务器 + 前端 dist）；
  - Zot 来自 ghcr.io；Argo CD 来自 quay.io；Redis 来自 ECR Public；
  - k3s 使用从官方 `ghcr.io/k3s-io/k3s` 镜像提取的二进制 + Rancher 镜像的 airgap 包；
  - 未使用 `latest`；所有关键镜像记录 tag/digest。

## 2. Gitea webhook 被 egress 策略阻断（关键限制）

Hook 配置为 `http://127.0.0.1:8081/generic-webhook-trigger/invoke`（也尝试过
`http://192.168.5.1:8081`）。Gitea 日志：

```text
Unable to deliver webhook task[...] in http://127.0.0.1:8081/...:
dial tcp 127.0.0.1:8081: denied by egress policy:
127.0.0.1(127.0.0.1) needs an explicit IP allow entry (non-public address)
```

换成 VM 自身 IP 后：

```text
dial tcp 192.168.5.1:8081: denied by egress policy:
192.168.5.1(192.168.5.1) needs an explicit IP allow entry (non-public address)
```

- 结论：**webhook 代码/配置已实现，但该沙箱禁止 Gitea 出站到任何非公网地址**；即使 Gitea 放进 Colima VM，策略仍在。
- 应对：实现 `scripts/ci/gitea-jenkins-bridge.py`，轮询 Gitea API 的分支/PR head，调用 Jenkins `buildWithParameters`；build #7/#8/#9/#11/#12 均由桥触发。
- 补充条件：若在允许私网 egress 的环境，禁用桥并保留 hook 即可；Hook 的 `Authorization: Bearer` 与 Jenkins GenericTrigger 已配置。

## 3. Lima 用户态网络：宿主 ↔ VM 无直接 TCP

- 宿主无法直连 VM 的 6443/3000；VM 也无法直连宿主端口。
- 应对：
  - k3s API：`ssh -L 127.0.0.1:16443:127.0.0.1:6443`，kubeconfig 的 server 改为 `https://127.0.0.1:16443`；
  - Gitea：VM host network + `ssh -L 127.0.0.1:3000:127.0.0.1:3000`（宿主 Jenkins 使用）；
  - Jenkins：`ssh -R 0.0.0.0:8081:127.0.0.1:8081`（仅用于 webhook 尝试；被 egress 阻断）；
  - Zot：运行在 VM Docker 并发布到 VM `127.0.0.1:5001`，k3s containerd 与宿主 Jenkins 分别通过 VM localhost / Colima 端口转发访问。
- 这些转发在 Colima 重启后需重建；`50-k8s.sh`、`15-gitea-container.sh` 已包含建立逻辑。

## 4. VM DNS 配置缺失

- 首次启动后 `/etc/resolv.conf` 是指向不存在的 `systemd-resolved` stub 的悬空链接，Docker 报 `lookup ... on [::1]:53: connection refused`。
- 应对：`/etc/resolv.conf` 写成 `nameserver 114.114.114.114` + `8.8.8.8`；`90-start-all.sh` 会检测修复。

## 5. Colima 镜像下载慢且校验值实为 SHA512

- colima-core GitHub release asset 单连接约 30 KB/s，332 MB 镜像不可接受。
- 应对：并行分段下载 + 缺块补传；校验值长度 128 位，是 **SHA512** 而非 SHA256；最终 `gzip -t` 与 SHA512 均通过。
- 记录：`COLIMA_IMAGE_SHA512` 在 `versions.env`；`scripts/lib/parallel-download.py` 支持 SHA256/SHA512。

## 6. k3s 官方镜像的二进制缺少 CNI / kubectl 子命令

- 从 `ghcr.io/k3s-io/k3s:v1.35.0-k3s1` 提取的 `/bin/k3s` 为 182 MB；直接启动报 `failed to find host-local`，且 `k3s kubectl` 不可用。
- 应对：
  - 从同一镜像提取 `/bin/cni` 并为 `bridge/host-local/loopback/flannel/portmap/firewall` 建符号链接到 `/opt/cni/bin`；
  - 安装 `conntrack/ethtool/ebtables`；
  - k3s 启动 PATH 含 `/opt/cni/bin` 与 `/usr/sbin`；
  - 宿主使用 kubectl 1.35.9 通过 SSH 隧道访问。
- 这不是上游 release 二进制的等价物；已在 `versions.env` 记录镜像 digest。若需 release 二进制，可用 Rancher 镜像的 `k3s-airgap-images` + 官方 release（当前网络未取到 arm64 release）。

## 7. `kubectl logs` 受节点 IP 限制

- API server 通过 `192.168.5.1:10250` 读取 kubelet 日志，VM 内自环/hairpin 超时，报 `EOF`。
- 应用镜像为 scratch，不能 `kubectl exec`。
- 替代：`colima ssh -- sudo tail -n 100 /var/log/pods/lowcode-dev_<pod>_<uid>/web/0.log`；或 `kubectl describe`/events。
- 影响：验收中的日志定位使用 Jenkins 控制台、K8s events、Pod 日志文件；未把 `kubectl logs` 当作已验证能力。

## 8. Argo CD 轮询与刷新

- 默认 3 分钟轮询；Jenkins GitOps 更新后主动 `kubectl annotate ... refresh=normal`，否则 Deploy verify 的 180 秒窗口可能不够。
- Gitea → Argo CD 的 webhook 同样被 egress 阻断；本地依赖轮询/主动刷新。

## 9. 单机 / 本地安全边界

- 单节点 k3s；无 HA、无多集群。
- 本地 HTTP：Gitea、Jenkins、Zot、Argo CD UI port-forward；无公网入口、无 TLS。
- 生产差距：TLS/Ingress、SSO、Vault/External Secrets、NetworkPolicy 实施、镜像签名/扫描、rootless BuildKit/Kaniko、备份与审计，均未实现，不应声称完成。

## 10. 其他

- 端口 8080/5000 被宿主占用，使用 8081/3000/5001/9090/16443。
- Colima VM 重启后 k3s 需手动启动（本方案未注册为 VM 服务）；`90-start-all.sh` 负责恢复。
- Jenkins 首次启动的 admin 密码来自 `secrets/initialAdminPassword`，已写入 `.env.local`（不打印）。
