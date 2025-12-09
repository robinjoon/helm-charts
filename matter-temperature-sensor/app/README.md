# Matter Temperature Sensor

가상 Matter 프로토콜 온도 센서 IoT 기기입니다.

## 기능

- Matter 프로토콜을 사용하는 가상 온도 센서
- 현재 고정값 10°C를 반환
- 향후 날씨 API 연동 가능하도록 설계됨
- Node.js 22+ 및 matter.js 라이브러리 사용

## 로컬 개발

### 필수 요구사항

- Node.js 22 이상
- npm

### 설치 및 실행

```bash
cd app
npm install
npm start
```

## Docker 빌드

```bash
docker build -t matter-temperature-sensor:latest ./app
```

## 환경 변수

- `STORAGE_PATH`: Matter 데이터 저장 경로 (기본값: `/data`)

## 페어링

Matter 컨트롤러(예: Apple Home, Google Home, SmartThings 등)에서 이 기기를 페어링할 수 있습니다.

## 향후 계획

- 날씨 API를 통한 실제 온도 데이터 연동
- 추가 센서 타입 지원 (습도, 기압 등)
