# kube-prometheus-stack 기반 홈 k3s 모니터링 구축 작업 계획

## 1. 목표

- 홈 k3s 클러스터 내부 리소스와 워크로드를 `kube-prometheus-stack`으로 관측한다.
- 같은 Prometheus에서 k3s 클러스터 외부 시스템의 Prometheus metrics endpoint도 함께 수집한다.
- Grafana 대시보드, Alertmanager 알림, 기본 경보 규칙을 운영 가능한 수준으로 정리한다.
- 저장소는 쓰기 부하가 큰 실시간 데이터와 백업/장기 보관 데이터를 분리하는 방향으로 설계한다.

## 2. 기본 설계 방향

### 권장 아키텍처

- 배포 네임스페이스: `monitoring`
- Helm chart: `prometheus-community/kube-prometheus-stack`
- 기본 구성요소:
  - Prometheus Operator
  - Prometheus
  - Alertmanager
  - Grafana
  - kube-state-metrics
  - node-exporter
- 외부 시스템 수집 방식:
  - 정적 대상은 `ScrapeConfig` 또는 `additionalScrapeConfigs` 기반으로 관리
  - 인증/TLS가 필요한 엔드포인트는 별도 Secret로 분리

### k3s 특이사항 반영

`kube-prometheus-stack` 기본값은 일반 Kubernetes 배포를 기준으로 해서, k3s에서는 일부 기본 모니터링 대상이 그대로 맞지 않을 수 있다. 따라서 아래 항목은 실제 클러스터 구성 확인 후 비활성화 또는 별도 조정한다.

- `kubeEtcd`
- `kubeScheduler`
- `kubeControllerManager`
- `kubeProxy`
- 기본 규칙 중 실제로 메트릭이 나오지 않는 항목

이 단계를 먼저 하지 않으면 설치 직후부터 `down` 상태 타겟과 불필요한 경보가 많이 발생할 수 있다.

현재 k3s datastore가 embedded SQLite이므로 `kubeEtcd` 관련 수집과 규칙은 기본적으로 비활성화하는 전제로 설계한다.

### 현재 환경 반영

- 현재 확인된 노드 토폴로지는 `type=high-perf` 1대, `type=vm` 1대다.
- `robinjoon-k3s-high-node-mini-pc`(`type=high-perf`, worker)는 16 vCPU / 약 20Gi memory이며 Prometheus TSDB처럼 쓰기량과 저장 용량이 큰 워크로드의 1차 배치 대상으로 사용한다.
- `robinjoon-truenas-k3s-1`(`type=vm`, control-plane)은 5 vCPU / 약 24Gi memory이며 디스크 여유가 적으므로 Grafana, Prometheus Operator, kube-state-metrics 같은 보조 성격 워크로드를 우선 배치한다.
- 모든 노드에서 `local-path` StorageClass를 사용할 수 있으므로, 우선 실시간 저장소는 `local-path`를 사용하고 `nfs-csi`는 백업/보조 용도로 제한하는 방향이 가장 적절하다.
- `local-path`는 노드 로컬 스토리지 성격이 강하므로, PVC만 설정하지 말고 `nodeSelector` 또는 `affinity`를 함께 써서 원하는 노드 클래스에 Stateful workload가 붙도록 설계한다.
- `local-path` provisioner 경로는 `/var/lib/rancher/k3s/storage`이며, high-perf 노드에서는 `/` 파일시스템 아래의 1.9TB NVMe SSD(`SOLIDIGM SSDPFKKW020X7`)에 위치한다.
- 현재 high-perf 노드의 해당 경로 기준 여유 공간은 약 1.8TB이므로, Prometheus 14일 retention과 백업 snapshot 운영을 시작하기에 충분하다.

## 3. 저장소 전략

### 권장안

실시간 쓰기가 많은 Prometheus TSDB는 `nfs-csi`를 기본 저장소로 쓰지 않는 것을 권장한다. Prometheus는 디스크 지연시간과 fsync 특성에 민감해서, NFS 기반 스토리지는 성능 저하나 장애 분석 난이도를 크게 높일 수 있다.

권장 분리 방식은 아래와 같다.

| 데이터 종류 | 권장 저장 위치 | `nfs-csi` 사용 여부 |
| --- | --- | --- |
| Prometheus 실시간 TSDB | 로컬/블록 계열 `RWO` 스토리지 (`local-path`, Longhorn 등) | 비권장 |
| Alertmanager 상태(silence 등) | 소형 `RWO` PVC | 가능하면 비NFS |
| Grafana 데이터 | 소형 PVC 또는 프로비저닝 기반 최소화 | 선택 |
| Prometheus 스냅샷/백업 | `nfs-csi` | 권장 |
| 장기 보관 데이터 | 추후 Thanos/VictoriaMetrics/Mimir 등 | 필요 시 사용 |

### 운영 원칙

- 1차 운영안:
  - Prometheus 보관 기간은 14일로 시작
  - 실시간 데이터는 `type=high-perf` 노드의 `local-path` 사용
  - 정기 스냅샷/백업만 `nfs-csi`로 전송
- 2차 확장안:
  - 30일 이상 장기 보관이 필요하면 Prometheus 단독 보관보다 장기 저장 백엔드를 추가 검토
  - 이 경우 `nfs-csi`는 직접 TSDB를 담기보다 백업 저장소나 장기 저장 계층의 보조 용도로 사용

### 현재 정보 기준 권장 배치

| 구성요소 | 저장소 | 권장 노드 |
| --- | --- | --- |
| Prometheus | `local-path` PVC | `type=high-perf` |
| Alertmanager | 소형 `local-path` PVC | 일반 노드 또는 `type=vm` |
| Grafana | 소형 `local-path` PVC 또는 최소 상태 저장 | `type=vm` |
| Prometheus Operator / kube-state-metrics | 영속 저장소 불필요 | `type=vm` |
| 백업 Job 및 snapshot 보관 | `nfs-csi` | 백업 전용 |

참고:

- 현재 `type=high-perf` 노드가 1대이므로, Prometheus는 우선 단일 replica로 설계한다.
- 향후 `type=high-perf` 노드가 2대 이상이 되면 Prometheus HA 또는 장기 저장 백엔드 연계를 검토한다.
- `kubectl describe node`의 `ephemeral-storage` 수치보다 `local-path` 실제 경로의 파일시스템 여유 공간이 더 중요하므로, PVC 산정은 `/var/lib/rancher/k3s/storage` 기준으로 판단한다.

### 차선책

가용한 영속 스토리지가 `nfs-csi`뿐이라면 일단 구축은 가능하지만, 아래 제약을 감수해야 한다.

- Prometheus 쓰기 성능 저하 가능성
- compaction/WAL 처리 지연 가능성
- 장애 시 원인 분석 복잡도 증가

이 경우에는 retention과 수집 범위를 보수적으로 잡고, 운영 안정화 후 저장소 구조를 재검토한다.

## 4. 단계별 작업 계획

### 0단계 - 사전 정보 수집

- k3s 노드 수, 노드 역할, 각 노드 디스크 여유 공간 확인
- 현재 StorageClass 목록과 기본 StorageClass 확인
- `nfs-csi` 외에 사용할 수 있는 로컬/블록형 영속 스토리지 유무 확인
- k3s가 embedded etcd인지, 외부 DB/sqlite인지 확인
- 외부 모니터링 대상은 2~3개, 인증은 `https + basicAuth` 기준으로 설계
- Grafana는 Ingress로 외부 노출하며 1순위는 `https://homelab.robinjoon.xyz/grafana`, 2순위 fallback은 `https://grafana.homelab.robinjoon.xyz`
- TLS는 `traefik.ingress.kubernetes.io/router.entrypoints: websecure`, `cert-manager.io/cluster-issuer: letsencrypt-prod` 어노테이션 기준으로 설계
- 알림 채널은 Discord 기준으로 설계하되 webhook URL은 추후 Secret로 주입
- `local-path` provisioner는 `/var/lib/rancher/k3s/storage`를 사용하며 high-perf 노드의 1.9TB NVMe SSD에 위치함을 확인

### 1단계 - 초기 배포 설계

- `monitoring` 네임스페이스 설계
- Helm release 이름과 버전 pinning 정책 결정
- 기본 values 파일 초안 작성
- k3s에 맞지 않는 기본 ServiceMonitor/Rules 비활성화
- `type=high-perf`/`type=vm` 라벨 기준의 노드 배치 정책 정의
- Prometheus/Alertmanager/Grafana 리소스 요청치의 초기값 정의
- Grafana Ingress 호스트명, 경로(`/grafana`), TLS 어노테이션, ingress class 정의
- Discord receiver와 라우팅 기본 정책 정의
- 외부 타겟 입력 방식을 Secret 또는 별도 values 파일로 정의

예상 산출물:

- `values-k3s.yaml`
- `values-k3s-storage.yaml`
- `values-k3s-ingress.yaml` 또는 접근 정책 문서

### 2단계 - 저장소 및 보관 정책 적용

- Prometheus PVC를 `local-path` + `type=high-perf` 고정으로 설정
- Alertmanager는 소형 PVC 적용 여부 결정
- Grafana는 아래 둘 중 하나로 결정
  - 소형 PVC 사용
  - 대시보드/데이터소스/관리자 설정을 코드화해서 무상태에 가깝게 운영
- Prometheus retention 14일과 예상 디스크 사용량 계산
- `local-path` 실제 저장 경로가 1.9TB NVMe SSD임이 확인되었으므로 PVC 크기와 `retentionSize` 초기값 확정
- Prometheus snapshot 백업 CronJob을 설계하고 백업 목적지로 `nfs-csi`를 연결

예상 산출물:

- Prometheus persistence 설정
- 백업 CronJob 또는 수동 백업 절차 문서
- 백업 보관 주기/삭제 정책 문서

### 3단계 - 외부 시스템 모니터링 연동

- 외부 시스템을 성격별로 scrape job 분리
  - 홈 서버/VM
  - 네트워크 장비 또는 NAS
  - 별도 애플리케이션 서버
- 대상 정의 방식은 우선 Secret 기반 `additionalScrapeConfigsSecret` 또는 별도 Secret 참조 방식으로 설계
- 2~3개의 고정 외부 타겟은 `static_configs`로 관리
- `https`, 서버 인증서 검증, `basic_auth` 접속 정책 반영
- 외부 인증서는 공인 CA 기준이므로 기본 TLS 검증을 유지하고 별도 CA Secret은 기본적으로 생략
- 외부 타겟용 공통 라벨(`site`, `env`, `role`, `owner`) 설계

예상 산출물:

- 외부 타겟 scrape 설정 파일
- 인증 Secret 템플릿
- 타겟 분류 기준 문서

### 4단계 - 시각화 및 알림 구성

- Grafana 관리자 계정과 Secret 관리 방식 결정
- Grafana Ingress와 TLS 적용
- 기본 대시보드 외에 홈랩 운영용 대시보드 추가
- Alertmanager Discord receiver 및 라우팅 정책 구성
- 테스트용 경보를 발생시켜 알림 전달 검증

예상 산출물:

- Alertmanager 설정
- Grafana 접근 설정
- 운영 대시보드 목록

### 5단계 - 검증 및 운영 안정화

- Prometheus target 상태 확인
- 기본 경보 중 오탐/불필요 경보 정리
- 실제 스토리지 사용량, WAL 증가 속도, retention 적정성 검토
- 백업 생성/복구 리허설 수행
- 재부팅/노드 장애 시 복구 동작 확인

완료 기준:

- 클러스터 내부 핵심 타겟이 정상 수집됨
- 외부 시스템 타겟이 정상 수집됨
- Grafana에서 핵심 대시보드 확인 가능
- Alertmanager 테스트 알림이 정상 전달됨
- 백업 파일이 `nfs-csi`에 정상 저장되고 복구 절차가 문서화됨

## 5. 구현 우선순위

1. k3s 환경에 맞는 기본 수집 항목 정리
2. Prometheus 실시간 저장소를 `nfs-csi`와 분리
3. 외부 시스템 scrape 설정 체계 확정
4. Grafana/Alertmanager 접근 보안 구성
5. 백업 자동화와 복구 검증

## 6. 추천 초기 운영안

복잡도를 너무 빨리 올리지 않기 위해 첫 배포는 아래처럼 시작하는 것을 권장한다.

- Prometheus: 단일 replica, 짧은 retention, `type=high-perf` + `local-path`
- Alertmanager: 단일 replica, 소형 `local-path` PVC 또는 필요 최소 persistence
- Grafana: 단일 replica, `type=vm` 우선 배치, 소형 PVC 또는 최소 상태 저장
- 외부 타겟: 2~3개 정적 타겟을 `https + basicAuth`로 우선 연결
- 백업: Prometheus snapshot을 `nfs-csi`로 주기 백업
- 장기 저장: 운영 안정화 후 필요성이 확인되면 2단계로 추가

## 7. 현재 정보 기준 구현 메모

- Prometheus:
  - `replicas: 1`
  - `retention: 14d`
  - `nodeSelector.type=high-perf`
  - `storageClassName: local-path`
  - 초기 PVC 제안: `100Gi` ~ `150Gi`
  - 초기 `retentionSize` 제안: `80GiB` ~ `120GiB`
- Grafana:
  - `nodeSelector.type=vm` 또는 `preferredDuringScheduling`으로 `type=vm` 선호
  - Ingress 외부 노출
  - 1순위 URL: `https://homelab.robinjoon.xyz/grafana`
  - 필요 설정: `grafana.ini.server.root_url`, `grafana.ini.server.serve_from_sub_path=true`
  - 경로 기반 Ingress가 불안정하면 fallback으로 `https://grafana.homelab.robinjoon.xyz` 사용
  - 관리자 계정은 Secret 사용
- Alertmanager:
  - 단일 replica
  - Discord `discord_configs` 사용
  - webhook URL은 Secret로 분리
  - 준비 전에는 기본 `null` receiver 유지 또는 Discord receiver만 템플릿으로 준비
- 외부 scrape:
  - `additionalScrapeConfigsSecret` 사용 권장
  - 타겟 2~3개를 `static_configs`로 선언
  - `basic_auth` 자격증명은 별도 Secret로 관리
  - 현재는 공인 CA이므로 기본 TLS 검증 사용
  - 엔드포인트와 계정 정보는 Secret 또는 별도 private values 파일로 관리
- 백업:
  - Prometheus snapshot CronJob
  - 백업 대상 PVC는 `nfs-csi`
  - 보관 정책은 14일 retention과 별도로 운영
  - snapshot 보관 주기 예시: 1일 1회 + 7~14개 보관

- k3s 제약:
  - datastore는 embedded SQLite
  - `kubeEtcd.enabled=false` 방향으로 values 구성

## 8. 추가로 필요한 정보

아래 정보가 있으면 실제 values 설계와 설치 절차를 바로 구체화할 수 있다.

1. Discord webhook URL 준비 여부
2. 외부 모니터링 대상의 실제 엔드포인트 주소

이 정보가 정리되면 다음 단계로 실제 `values.yaml` 세트와 설치/백업 리소스 초안을 만들 수 있다.
