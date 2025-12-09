# Matter Temperature Sensor Helm Chart

Matter 프로토콜을 사용하는 가상 IoT 온도 센서를 Kubernetes에 배포하기 위한 Helm Chart입니다.

## 개요

이 Helm Chart는 Matter.js를 사용하여 구현된 가상 온도 센서를 배포합니다. 현재는 고정값 10°C를 반환하며, 향후 날씨 API와 연동할 수 있도록 설계되었습니다.

## 특징

- ✅ Matter 프로토콜 지원
- ✅ 온도 센서 디바이스 타입 구현
- ✅ 블루투스 지원 노드에 자동 배포 (high-perf)
- ✅ 데이터 영구 저장 (PVC)
- ✅ Host 네트워크 모드 지원 (mDNS 검색용)
- ✅ Node.js 22 및 matter.js 라이브러리 사용

## 전제 조건

- Kubernetes 1.19+
- Helm 3.0+
- 블루투스 기능이 있는 노드 (label: `kubernetes.io/hostname: high-perf`)
- PersistentVolume 프로비저너 (기본: local-path)

## 설치

### Docker 이미지 빌드

먼저 Docker 이미지를 빌드하고 레지스트리에 푸시해야 합니다:

```bash
# 이미지 빌드
docker build -t matter-temperature-sensor:latest ./app

# (선택) 이미지를 레지스트리에 푸시
# docker tag matter-temperature-sensor:latest your-registry/matter-temperature-sensor:latest
# docker push your-registry/matter-temperature-sensor:latest
```

### Helm Chart 설치

```bash
# 기본 설정으로 설치
helm install matter-sensor ./matter-temperature-sensor

# 네임스페이스 지정하여 설치
helm install matter-sensor ./matter-temperature-sensor -n iot --create-namespace

# 커스텀 values 파일 사용
helm install matter-sensor ./matter-temperature-sensor -f custom-values.yaml
```

## 설정

주요 설정 옵션은 `values.yaml`에서 확인할 수 있습니다:

### 이미지 설정

```yaml
image:
  repository: matter-temperature-sensor
  pullPolicy: IfNotPresent
  tag: "latest"
```

### 노드 선택기 (필수)

블루투스 기능이 있는 high-perf 노드에 배포하도록 설정:

```yaml
nodeSelector:
  kubernetes.io/hostname: high-perf
```

### 리소스 설정

```yaml
resources:
  limits:
    cpu: 500m
    memory: 512Mi
  requests:
    cpu: 100m
    memory: 128Mi
```

### 스토리지 설정

```yaml
persistence:
  enabled: true
  storageClass: "local-path"
  accessMode: ReadWriteOnce
  size: 1Gi
```

### 네트워크 설정

Matter 프로토콜의 mDNS 검색을 위해 Host 네트워크 사용:

```yaml
hostNetwork: true
dnsPolicy: ClusterFirstWithHostNet
```

## 사용 방법

### 1. Pod 상태 확인

```bash
kubectl get pods -l app.kubernetes.io/name=matter-temperature-sensor
```

### 2. 로그 확인

```bash
kubectl logs -l app.kubernetes.io/name=matter-temperature-sensor -f
```

### 3. Matter 디바이스 페어링

- Apple Home, Google Home, SmartThings 등 Matter 호환 앱 실행
- 새 디바이스 추가
- Matter 디바이스 검색
- 화면의 지시에 따라 페어링 진행

### 4. 온도 확인

페어링 후 Matter 컨트롤러 앱에서 온도 센서의 현재 값(10°C)을 확인할 수 있습니다.

## 제거

```bash
helm uninstall matter-sensor
```

PVC도 함께 삭제하려면:

```bash
kubectl delete pvc -l app.kubernetes.io/name=matter-temperature-sensor
```

## 향후 개발 계획

- [ ] 날씨 API 연동 (실시간 온도 데이터)
- [ ] 추가 센서 타입 지원 (습도, 기압 등)
- [ ] 환경 변수를 통한 센서 값 설정
- [ ] Prometheus 메트릭 노출

## 문제 해결

### Pod가 시작되지 않음

1. 노드 레이블 확인:
   ```bash
   kubectl get nodes --show-labels | grep high-perf
   ```

2. 이미지가 노드에서 접근 가능한지 확인

### Matter 디바이스가 검색되지 않음

1. hostNetwork가 활성화되어 있는지 확인
2. 블루투스가 노드에서 활성화되어 있는지 확인
3. 파드 로그에서 에러 메시지 확인

## 참고 자료

- [Matter.js GitHub](https://github.com/matter-js/matter.js)
- [Matter 프로토콜 공식 사이트](https://buildwithmatter.com)
- [@matter.js/examples](https://www.npmjs.com/package/@matter.js/examples)

## 라이선스

This project uses Matter.js which is Apache-2.0 licensed.
