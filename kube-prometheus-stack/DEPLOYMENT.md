# kube-prometheus-stack 배포 안내

이 문서는 현재 저장소 상태를 기준으로, k3s 클러스터에 `kube-prometheus-stack`을 ArgoCD로 배포하기 전에 무엇을 준비해야 하는지 정리한 안내서입니다.

## 먼저 결론

`monitoring` 네임스페이스만 만든다고 바로 정상 배포되지는 않습니다.

최소한 아래 3가지는 필요합니다.

1. ArgoCD가 `kube-prometheus-stack` 차트에 `values/values-k3s.yaml`을 적용하도록 설정
2. Grafana 관리자 Secret 생성
3. ArgoCD `Application`에 `ServerSideApply=true` 추가

추가 기능을 쓰려면 아래가 더 필요합니다.

- 외부 metrics endpoint 수집: 외부 scrape Secret + `values/values-k3s-external-targets.yaml`
- Discord 알림: Alertmanager Secret + `values/values-k3s-alertmanager-existing-secret.yaml`

## 현재 차트 구성

- 기본 차트 경로: `kube-prometheus-stack`
- 기본 values: `kube-prometheus-stack/values/values-k3s.yaml`
- 외부 타겟 오버레이: `kube-prometheus-stack/values/values-k3s-external-targets.yaml`
- Alertmanager existing Secret 오버레이: `kube-prometheus-stack/values/values-k3s-alertmanager-existing-secret.yaml`
- Grafana 서브도메인 fallback 오버레이: `kube-prometheus-stack/values/values-k3s-grafana-subdomain.yaml`
- 시크릿 예시: `kube-prometheus-stack/secret.example.yaml`

## 현재 기본 배포값 요약

- Prometheus: `type=high-perf`, `local-path`, `retention=14d`, `retentionSize=220GiB`, PVC `300Gi`
- Grafana: `type=vm`, `local-path`, 기본 URL `https://homelab.robinjoon.xyz/grafana`
- Alertmanager: `type=vm`, 소형 `local-path` PVC
- k3s 특성 반영: `kubeEtcd`, `kubeControllerManager`, `kubeScheduler`, `kubeProxy` 비활성화

## 추천 배포 순서

처음에는 기능을 한 번에 다 켜지 말고 아래 순서로 가는 것을 권장합니다.

1. 기본 스택 배포
2. Grafana 접속 및 Prometheus/Alertmanager/Exporter 정상 기동 확인
3. 외부 타겟 scrape 활성화
4. Discord 알림 활성화

## 1. 네임스페이스 준비

둘 중 하나를 선택하면 됩니다.

### 방법 A - 미리 생성

```bash
kubectl create namespace monitoring
```

### 방법 B - ArgoCD가 생성

ArgoCD `Application`에 아래 sync option을 넣습니다.

```yaml
syncPolicy:
  automated:
    prune: true
    selfHeal: true
  syncOptions:
    - CreateNamespace=true
    - ServerSideApply=true
    - SkipDryRunOnMissingResource=true
```

## 2. Secret 준비

가장 간단한 방법은 예시 파일을 복사해서 실제 값으로 채우는 것입니다.

```bash
cp kube-prometheus-stack/secret.example.yaml kube-prometheus-stack/secret.yaml
```

그 다음 `kube-prometheus-stack/secret.yaml`을 수정합니다.

### 꼭 필요한 Secret

기본 배포만 하더라도 아래 Secret은 필요합니다.

- `kube-prometheus-stack-grafana-admin`

수정할 값:

- `admin-user`
- `admin-password`

### 외부 타겟 scrape를 켤 때 필요한 Secret

- `kube-prometheus-stack-additional-scrape-configs`

수정할 값:

- `targets`
- `basic_auth.username`
- `basic_auth.password`
- 필요 시 `job_name`, `labels`

현재 전제:

- 외부 endpoint는 `https`
- 인증서는 공인 CA
- basic auth 사용

### Discord 알림을 켤 때 필요한 Secret

- `alertmanager-kube-prometheus-stack-alertmanager`

수정할 값:

- `discord_configs[].webhook_url`

주의:

- Discord webhook을 아직 준비하지 않았다면 이 Secret은 만들어두기만 하거나, Alertmanager 오버레이를 나중에 적용하세요.
- Discord 알림을 켜지 않을 때는 기본 values의 `null` receiver가 유지됩니다.

### Secret 적용

```bash
kubectl apply -f kube-prometheus-stack/secret.yaml
```

## 3. ArgoCD Application 설정

이 차트는 Prometheus Operator CRD가 크기 때문에, ArgoCD 기본 client-side apply로는 `metadata.annotations: Too long` 오류가 날 수 있습니다.

그래서 아래 sync option을 함께 넣는 것을 권장합니다.

- `ServerSideApply=true`
- `SkipDryRunOnMissingResource=true`
- `CreateNamespace=true`

아래는 권장 예시입니다.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kube-prometheus-stack
  namespace: argocd
spec:
  project: default
  source:
    repoURL: <YOUR_GIT_REPO_URL>
    targetRevision: main
    path: kube-prometheus-stack
    helm:
      valueFiles:
        - values/values-k3s.yaml
        # 외부 타겟 scrape 활성화 시 추가
        # - values/values-k3s-external-targets.yaml
        # Discord Alertmanager existing Secret 사용 시 추가
        # - values/values-k3s-alertmanager-existing-secret.yaml
        # /grafana 경로 대신 서브도메인으로 바꿀 때 추가
        # - values/values-k3s-grafana-subdomain.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
      - SkipDryRunOnMissingResource=true
```

같은 예시는 `kube-prometheus-stack/argocd-application.example.yaml`에도 추가되어 있습니다.

## 4. 배포 시나리오별 valueFiles 조합

### 시나리오 A - 가장 먼저 해볼 기본 배포

목적:

- Prometheus, Alertmanager, Grafana, node-exporter, kube-state-metrics 정상 기동 확인

필요한 것:

- `values/values-k3s.yaml`
- Grafana admin Secret

ArgoCD valueFiles:

```yaml
valueFiles:
  - values/values-k3s.yaml
```

### 시나리오 B - 외부 metrics endpoint까지 포함

필요한 것:

- `values/values-k3s.yaml`
- `values/values-k3s-external-targets.yaml`
- Grafana admin Secret
- additional scrape configs Secret

ArgoCD valueFiles:

```yaml
valueFiles:
  - values/values-k3s.yaml
  - values/values-k3s-external-targets.yaml
```

### 시나리오 C - Discord 알림까지 포함

필요한 것:

- `values/values-k3s.yaml`
- `values/values-k3s-alertmanager-existing-secret.yaml`
- Grafana admin Secret
- Alertmanager Secret

ArgoCD valueFiles:

```yaml
valueFiles:
  - values/values-k3s.yaml
  - values/values-k3s-alertmanager-existing-secret.yaml
```

### 시나리오 D - 외부 scrape + Discord 둘 다 포함

필요한 것:

- `values/values-k3s.yaml`
- `values/values-k3s-external-targets.yaml`
- `values/values-k3s-alertmanager-existing-secret.yaml`
- Grafana admin Secret
- additional scrape configs Secret
- Alertmanager Secret

ArgoCD valueFiles:

```yaml
valueFiles:
  - values/values-k3s.yaml
  - values/values-k3s-alertmanager-existing-secret.yaml
  - values/values-k3s-external-targets.yaml
```

## 5. Grafana Ingress 관련 선택

기본은 경로 기반입니다.

- 기본 URL: `https://homelab.robinjoon.xyz/grafana`

만약 Traefik 환경에서 `/grafana` 경로 방식이 불안정하면 fallback으로 아래 오버레이를 추가하세요.

- `values/values-k3s-grafana-subdomain.yaml`

이 경우 URL은 아래로 바뀝니다.

- `https://grafana.homelab.robinjoon.xyz`

## 6. 배포 후 확인 항목

### Pod 상태

```bash
kubectl -n monitoring get pods
```

정상 기대 대상:

- Prometheus Operator
- Prometheus StatefulSet
- Alertmanager StatefulSet
- Grafana
- kube-state-metrics
- prometheus-node-exporter DaemonSet

### PVC 상태

```bash
kubectl -n monitoring get pvc
```

정상 기대 대상:

- Prometheus PVC `300Gi`
- Grafana PVC `5Gi`
- Alertmanager PVC `2Gi`

### Ingress 상태

```bash
kubectl -n monitoring get ingress
```

확인 포인트:

- `homelab.robinjoon.xyz` 호스트가 생성되었는지
- TLS secret이 정상 연결되었는지

### Prometheus 타겟 상태 확인

가장 간단한 방법은 port-forward입니다.

```bash
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090
```

그 다음 브라우저에서 아래를 확인합니다.

- `http://127.0.0.1:9090/targets`

### Grafana 접속

기본 경로 기반이면:

- `https://homelab.robinjoon.xyz/grafana`

fallback 서브도메인이면:

- `https://grafana.homelab.robinjoon.xyz`

## 7. 문제 발생 시 우선 확인 포인트

### Grafana Pod가 안 뜨는 경우

가장 먼저 확인할 것:

- `kube-prometheus-stack-grafana-admin` Secret이 존재하는지
- `monitoring` 네임스페이스에 생성되었는지

### 외부 타겟이 Prometheus에 안 보이는 경우

가장 먼저 확인할 것:

- `values/values-k3s-external-targets.yaml`이 ArgoCD에 포함되었는지
- `kube-prometheus-stack-additional-scrape-configs` Secret 이름이 일치하는지
- endpoint 주소와 basic auth 값이 맞는지

### Discord 알림이 안 가는 경우

가장 먼저 확인할 것:

- `values/values-k3s-alertmanager-existing-secret.yaml`이 적용되었는지
- `alertmanager-kube-prometheus-stack-alertmanager` Secret이 존재하는지
- Discord webhook URL이 실제 값인지

### `/grafana` 접근이 깨지는 경우

다음 순서로 대응:

1. Ingress와 TLS 상태 확인
2. Grafana `root_url`/`serve_from_sub_path` 설정 확인
3. 해결이 번거로우면 `values/values-k3s-grafana-subdomain.yaml`로 전환

### ArgoCD에서 `metadata.annotations: Too long`가 뜨는 경우

원인:

- Prometheus Operator CRD가 커서 ArgoCD 기본 apply 방식의 annotation 크기 제한에 걸림

대응:

1. `Application.spec.syncPolicy.syncOptions`에 `ServerSideApply=true` 추가
2. 같이 `SkipDryRunOnMissingResource=true` 추가
3. 다시 sync 수행

관련 증상:

- `CustomResourceDefinition ... metadata.annotations: Too long`
- `no matches for kind "Prometheus" in version "monitoring.coreos.com/v1" ensure CRDs are installed first`

두 번째 에러는 첫 번째 CRD 적용 실패의 연쇄 증상인 경우가 많습니다.

## 8. 추천 첫 배포안

가장 무난한 첫 단계는 아래입니다.

1. `monitoring` 네임스페이스 준비
2. Grafana admin Secret만 먼저 준비
3. ArgoCD에서 `values/values-k3s.yaml`만 적용
4. Pod/PVC/Ingress/Prometheus targets 확인
5. 이후 외부 scrape 오버레이 추가
6. 마지막으로 Discord Alertmanager 오버레이 추가

이 순서로 가면 문제를 좁혀가며 배포할 수 있습니다.
