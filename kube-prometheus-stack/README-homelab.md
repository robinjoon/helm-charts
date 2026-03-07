# kube-prometheus-stack homelab setup

이 디렉터리는 upstream `kube-prometheus-stack` 차트를 그대로 가져온 뒤, 홈 k3s 환경용 오버레이 값 파일만 추가한 구성입니다.

## 파일 구성

- `values/values-k3s.yaml`: 기본 k3s 홈랩 배포값
- `values/values-k3s-external-targets.yaml`: 외부 metrics endpoint 수집 활성화 오버레이
- `values/values-k3s-alertmanager-existing-secret.yaml`: Discord 등 사용자 Alertmanager Secret 사용 오버레이
- `values/values-k3s-grafana-subdomain.yaml`: `/grafana` 경로 기반 Ingress가 불안정할 때 쓰는 fallback 오버레이
- `secret.example.yaml`: Grafana 관리자 계정, Alertmanager, 외부 scrape 설정 예시 Secret

## 설치 순서

```bash
kubectl create namespace monitoring

cd kube-prometheus-stack
cp secret.example.yaml secret.yaml
# secret.yaml 수정
kubectl apply -f secret.yaml

helm upgrade --install kube-prometheus-stack . \
  -n monitoring \
  -f values/values-k3s.yaml
```

Discord용 Alertmanager Secret도 같이 쓰려면:

```bash
helm upgrade --install kube-prometheus-stack . \
  -n monitoring \
  -f values/values-k3s.yaml \
  -f values/values-k3s-alertmanager-existing-secret.yaml
```

외부 시스템 수집도 함께 켜려면:

```bash
helm upgrade --install kube-prometheus-stack . \
  -n monitoring \
  -f values/values-k3s.yaml \
  -f values/values-k3s-alertmanager-existing-secret.yaml \
  -f values/values-k3s-external-targets.yaml
```

Grafana를 서브도메인으로 바꾸려면:

```bash
helm upgrade --install kube-prometheus-stack . \
  -n monitoring \
  -f values/values-k3s.yaml \
  -f values/values-k3s-grafana-subdomain.yaml
```

## 현재 기본값

- Prometheus: `type=high-perf`, `local-path`, `14d`, PVC `300Gi`
- Grafana: `type=vm`, `local-path`, `https://homelab.robinjoon.xyz/grafana`
- Alertmanager: `type=vm`, 소형 `local-path` PVC
- 외부 scrape: Secret 기반 `additionalScrapeConfigsSecret` 오버레이로 활성화
- Alert 채널: 기본 values는 `null` receiver, Discord는 existing Secret 오버레이로 전환

## 메모

- k3s datastore가 embedded SQLite라서 `kubeEtcd` 관련 수집/룰은 비활성화했습니다.
- `kubeControllerManager`, `kubeScheduler`, `kubeProxy`도 k3s 기본 환경 기준으로 비활성화했습니다.
- `/grafana` 경로 기반 접근이 어렵다면 `values/values-k3s-grafana-subdomain.yaml`을 사용하세요.
