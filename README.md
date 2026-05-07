# 💊 MediLink

> 노인 환자를 위한 복약 관리 플랫폼 — 환자/보호자 이중 모드 지원

![Flutter](https://img.shields.io/badge/Flutter-02569B?style=flat&logo=flutter&logoColor=white)
![Node.js](https://img.shields.io/badge/Node.js-339933?style=flat&logo=node.js&logoColor=white)
![MySQL](https://img.shields.io/badge/MySQL-4479A1?style=flat&logo=mysql&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-2496ED?style=flat&logo=docker&logoColor=white)

---

## 📋 프로젝트 개요

MediLink는 노인 환자의 복약 관리를 돕고, 보호자가 원격으로 복약 현황을 모니터링할 수 있는 모바일 앱입니다.

- **환자 모드**: 오늘 먹을 약 확인, 복약 체크(사진 인증 포함), 기록 조회, 통계
- **보호자 모드**: 담당 환자 복약 현황 대시보드, 미복약 알림, 사진 확인, 통계

---

## ✅ 현재 구현된 기능

### 공통
- [x] 회원가입 / 로그인 (JWT 인증)
- [x] 환자 / 보호자 역할 분리

### 환자 모드
- [x] **오늘 복약 스케줄** 조회 (시간대별: 아침/점심/저녁/취침)
- [x] **복약 체크** — 사진 인증 포함 (Base64 인코딩)
- [x] **복약 취소** — 잘못 체크한 기록 삭제
- [x] **복약 기록** 조회 (날짜별, KST 변환)
- [x] **복약 통계** (7일 / 30일 복약률 그래프)
- [x] **약 관리** — 등록 / 스케줄 수정 / 복용 중단 / 복용 재개 / 완전 삭제
- [x] 약 검색 (이름 기반)

### 보호자 모드
- [x] **보호자 대시보드** — 연동 환자 목록 및 오늘 복약 현황
- [x] **미복약 알림** — 미복약 항목 빨간 경고 카드
- [x] **사진 확인** — 환자가 찍은 복약 인증 사진 보기
- [x] **복약 통계** — 7일 / 30일 탭, 일별 막대 그래프
- [x] 가족 연동 (환자-보호자 매핑)

---

## 🔮 앞으로 구현할 기능 (로드맵)

| 우선순위 | 기능 | 설명 |
|--------|------|------|
| 🔴 높음 | **푸시 알림** | 복약 시간 알림, 미복약 시 보호자에게 FCM 알림 |
| 🔴 높음 | **복약 알림 개인화** | 시간대별 알림 시각 직접 설정 |
| 🟡 중간 | **포인트 / 배지 시스템** | 연속 복약 달성 시 보상 (DB에 points_badges 테이블 준비됨) |
| 🟡 중간 | **약 정보 외부 연동** | 식품의약품안전처 API 연동으로 약 정보 자동 조회 |
| 🟡 중간 | **보호자 → 환자 메시지** | 복약 독려 메시지 발송 |
| 🟢 낮음 | **사진 저장소 개선** | Base64 DB 저장 → AWS S3 등 파일 서버 교체 |
| 🟢 낮음 | **상태관리 개선** | 현재 setState → Riverpod 또는 Bloc 도입 |
| 🟢 낮음 | **다약제 상호작용 경고** | 복용 중인 약 간 상호작용 위험 안내 |
| 🟢 낮음 | **PDF 복약 리포트** | 월별 복약 기록 PDF 출력 |

---

## 🏗️ 아키텍처

```
MediLink-main/
├── services/api/          # Node.js/Express REST API
│   ├── src/
│   │   ├── server.js              # 진입점
│   │   ├── app.js                 # Express 설정, 라우트 마운트
│   │   ├── config/db.js           # mysql2/promise 커넥션 풀
│   │   ├── middleware/
│   │   │   ├── auth.js            # JWT 검증 → req.user
│   │   │   └── role.js            # RBAC (현재 미적용)
│   │   └── modules/
│   │       ├── auth/              # 회원가입 · 로그인
│   │       ├── medicines/         # 약 검색 · 등록
│   │       ├── patient-medicines/ # 환자별 복용약 CRUD
│   │       ├── schedules/         # 복약 스케줄 생성 · 수정
│   │       ├── intake-logs/       # 복약 기록 체크 · 사진 · 취소
│   │       ├── guardian/          # 보호자 대시보드
│   │       ├── statistics/        # 복약 통계 7일/30일
│   │       └── family-map/        # 보호자-환자 연동
│   └── .env.example               # 환경변수 예시
├── apps/mobile/           # Flutter 앱 (Android)
│   └── lib/
│       ├── main.dart
│       ├── core/
│       │   ├── theme.dart             # AppTheme (#1E6FD9)
│       │   ├── storage.dart           # SharedPreferences
│       │   └── notification_service.dart
│       ├── data/
│       │   ├── api_client.dart        # HTTP 클라이언트 ⚠️ IP 설정 필요
│       │   └── auth_repository.dart
│       └── features/
│           ├── auth/                  # 로그인 · 회원가입
│           ├── home/                  # 역할별 라우팅
│           ├── patient/               # 환자 모드
│           └── guardian/              # 보호자 모드
└── infra/sql/             # DB 스키마 SQL (001~003 순서 자동 실행)
```

---

## 🚀 팀원 개발환경 셋업

### 사전 준비
- [Docker Desktop](https://www.docker.com/products/docker-desktop/) 설치 및 실행
- [Node.js](https://nodejs.org/) 18+ 설치
- [Flutter](https://flutter.dev/docs/get-started/install) 설치 (Android Studio + SDK 포함)

### 1. 저장소 클론
```bash
git clone https://github.com/vestman828/MediLink.git
cd MediLink
```

### 2. DB 실행 (Docker)
```bash
docker compose up -d
```

> ⚠️ **Windows에서 로컬 MySQL이 설치되어 있으면 3306 포트 충돌 발생**
> ```powershell
> Get-Service | Where-Object {$_.Name -like "*mysql*"}
> net stop MySQL80   # 서비스명은 환경에 따라 다를 수 있음
> ```

### 3. 백엔드 실행
```bash
cd services/api
cp .env.example .env   # .env 파일 생성 (필요시 JWT_SECRET 수정)
npm install
npm run dev
```

서버가 `http://localhost:4000` 에서 실행됩니다.

### 4. Flutter 실행

**⚠️ 반드시 먼저 API 주소를 설정해야 합니다**

`apps/mobile/lib/data/api_client.dart` 의 `_baseUrl` 수정:

```dart
// 안드로이드 에뮬레이터 사용 시
static const String _baseUrl = 'http://10.0.2.2:4000/api';

// 실기기(USB/Wi-Fi 핫스팟) 연결 시 → 본인 PC의 로컬 IP로 변경
static const String _baseUrl = 'http://192.168.x.x:4000/api';
// Windows IP 확인: ipconfig → IPv4 주소
// Mac/Linux IP 확인: ifconfig | grep inet
```

```bash
cd apps/mobile
flutter pub get
flutter run
```

---

## 🔌 API 엔드포인트

| Method | Path | 설명 |
|--------|------|------|
| POST | `/api/auth/signup` | 회원가입 |
| POST | `/api/auth/login` | 로그인 |
| GET | `/api/medicines/search?q=` | 약 검색 |
| POST | `/api/medicines` | 약 등록 |
| GET | `/api/patient-medicines/:patient_id` | 복용약 목록 (비활성 포함) |
| POST | `/api/patient-medicines` | 복용약 추가 |
| PATCH | `/api/patient-medicines/:id/deactivate` | 복용 중단 |
| PATCH | `/api/patient-medicines/:id/reactivate` | 복용 재개 |
| DELETE | `/api/patient-medicines/:id` | 복용약 완전 삭제 |
| GET | `/api/schedules/today` | 오늘 스케줄 |
| GET | `/api/schedules/by-medicine/:id` | 약별 스케줄 조회 |
| PUT | `/api/schedules/by-medicine/:id` | 스케줄 수정 |
| POST | `/api/intake-logs` | 복약 체크 |
| GET | `/api/intake-logs/history` | 복약 기록 |
| DELETE | `/api/intake-logs/:id` | 복약 취소 |
| GET | `/api/guardian/dashboard` | 보호자 대시보드 |
| GET | `/api/statistics/adherence` | 복약 통계 |
| GET | `/api/family-map/:id/patients` | 연동 환자 목록 |
| POST | `/api/family-map` | 가족 연동 |

---

## ⚙️ 환경변수 (.env)

`services/api/.env.example` 을 복사해서 `.env` 로 사용:

```env
PORT=4000
DB_HOST=localhost
DB_PORT=3306
DB_USER=medilink
DB_PASSWORD=medilink123
DB_NAME=medilink
JWT_SECRET=your_jwt_secret_here   # 반드시 안전한 값으로 변경!
JWT_EXPIRES_IN=7d
```

---

## 📝 개발 참고사항

| 항목 | 내용 |
|------|------|
| **시간대** | DB는 UTC 저장, 백엔드에서 `DATE_ADD(+9H)` 로 KST 변환 후 응답 |
| **사진 인증** | Base64 인코딩 → DB MEDIUMTEXT 저장 (실서비스 전 S3 교체 권장) |
| **상태관리** | Flutter `setState` 기반 (규모 커지면 Riverpod/Bloc 도입 고려) |
| **ORM** | 없음 — 모든 DB 쿼리는 raw `mysql2/promise` |
| **언어** | 주석 및 사용자 메시지는 한국어 |

---

## 🛠️ 기술 스택

| 영역 | 기술 |
|------|------|
| Frontend | Flutter (Dart) |
| Backend | Node.js + Express |
| Database | MySQL 8.0 |
| 인프라 | Docker Compose |
| 인증 | JWT |
| HTTP 통신 | http 패키지 (Flutter), mysql2/promise (Node.js) |
