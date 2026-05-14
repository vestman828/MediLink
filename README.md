# 💊 MediLink

> 노인 환자를 위한 복약 관리 플랫폼 — 환자/보호자 이중 모드 지원

![Flutter](https://img.shields.io/badge/Flutter-02569B?style=flat&logo=flutter&logoColor=white)
![Node.js](https://img.shields.io/badge/Node.js-339933?style=flat&logo=node.js&logoColor=white)
![MySQL](https://img.shields.io/badge/MySQL-4479A1?style=flat&logo=mysql&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-2496ED?style=flat&logo=docker&logoColor=white)
![Firebase](https://img.shields.io/badge/Firebase-FFCA28?style=flat&logo=firebase&logoColor=black)

---

## 📋 프로젝트 개요

MediLink는 노인 환자의 복약 관리를 돕고, 보호자가 원격으로 복약 현황을 모니터링할 수 있는 모바일 앱입니다.

- **환자 모드**: 오늘 먹을 약 확인, 복약 체크(사진 인증 포함), 달력 기록 조회, 일일 컨디션 메모, 통계, 약 정보 조회
- **보호자 모드**: 담당 환자 복약 현황 대시보드, FCM 미복약 알림, 환자별 달력 조회, 통계

---

## ✅ 현재 구현된 기능

### 공통
- [x] 회원가입 / 로그인 (JWT 인증)
- [x] 환자 / 보호자 역할 분리
- [x] 회원정보 수정 (이름 변경, 비밀번호 변경)
- [x] 로그아웃
- [x] **FCM 푸시 알림** — 앱 꺼져 있어도 알림 수신 (Firebase Cloud Messaging)

### 환자 모드
- [x] **오늘 복약 스케줄** 조회 (아침/점심/저녁/취침 시간대별)
- [x] **복약 체크** — 버튼 체크 또는 사진 인증 (Base64)
- [x] **복약 취소** — 잘못 체크한 기록 삭제
- [x] **복약 기록** — 달력 뷰 / 목록 뷰 전환, 날짜별 상세 조회
- [x] **복약 통계** — 7일 / 30일 복약률 막대 그래프, 포인트/등급
- [x] **약 관리** — 등록 / 스케줄 수정 / 복용 중단 / 복용 재개 / 완전 삭제
- [x] **복용 종료일 설정** — 종료일 지나면 서버 스케줄러가 자동 비활성화
- [x] **일일 메모** — 날짜별 컨디션 점수(1~5) + 메모 기록 및 달력에서 조회
- [x] **약 검색** — DB(4,700여 건) + 식품의약품안전처 e약은요 API 실시간 병행 검색
- [x] **약 상세 정보** — 효능·효과, 사용법, 주의사항, 부작용, 보관법 조회 (e약은요 API)
- [x] **복약 알림 시간 커스텀** — 아침/점심/저녁/취침 알림 시각 직접 설정 (내 정보 탭)
- [x] **FCM 복약 알림** — 앱 꺼져 있어도 복약 시간 알림 + 30분 후 재알림

### 보호자 모드
- [x] **보호자 대시보드** — 연동 환자 목록 및 오늘 복약 현황
- [x] **FCM 미복약 알림** — 복용 시간 2시간 후에도 미복약 시 보호자에게 FCM 알림
- [x] **환자 달력** — 환자별 월별 복약 기록(초록) + 메모(주황) 달력, 날짜 선택 시 상세 조회
- [x] **복약 통계** — 7일(일별) / 30일(주별 `M/d~d` 형식) 탭, 포인트/등급
- [x] **사진 확인** — 환자가 찍은 복약 인증 사진 보기
- [x] **가족 연동 (승인 방식)** — 전화번호로 요청 → 환자가 FCM 알림 받고 수락/거절
- [x] **가족 연동 취소** — 연동된 환자 카드 길게 눌러 연동 해제
- [x] 여러 환자 관리 (드롭다운으로 환자 전환)

### 백엔드 자동화
- [x] **FCM 복약 알림 전송** — 매 1분마다 시간 체크 후 해당 슬롯 환자에게 FCM 전송
- [x] **복용 종료일 자동 비활성화** — 매일 자정 실행
- [x] **미복약 보호자 FCM 알림** — 매 1시간마다 미복약 체크 후 보호자에게 FCM 전송
- [x] **오래된 알림 자동 삭제** — 3일 지난 알림 매일 정리

---

## 🏗️ 아키텍처

```
MediLink-main/
├── services/api/          # Node.js/Express REST API
│   ├── src/
│   │   ├── server.js              # 진입점 + 자동화 스케줄러 + FCM 알림
│   │   ├── app.js                 # Express 설정, 라우트 마운트
│   │   ├── config/
│   │   │   ├── db.js              # mysql2/promise 커넥션 풀 (utf8mb4)
│   │   │   └── firebase.js        # Firebase Admin SDK 초기화 + FCM 전송
│   │   ├── middleware/
│   │   │   ├── auth.js            # JWT 검증 → req.user
│   │   │   └── role.js            # RBAC (현재 미적용)
│   │   └── modules/
│   │       ├── auth/              # 회원가입 · 로그인
│   │       ├── medicines/         # 약 검색(DB+e약은요API) · 등록 · 상세조회
│   │       ├── patient-medicines/ # 환자별 복용약 CRUD
│   │       ├── schedules/         # 복약 스케줄 생성 · 수정
│   │       ├── intake-logs/       # 복약 기록 체크 · 사진 · 취소
│   │       ├── guardian/          # 보호자 대시보드
│   │       ├── statistics/        # 복약 통계 7일/30일
│   │       ├── family-map/        # 보호자-환자 연동 · 연동취소
│   │       ├── family-requests/   # 보호자 연동 요청 · 수락 · 거절
│   │       ├── users/             # 회원정보 수정 · FCM 토큰 저장
│   │       ├── daily-notes/       # 일일 메모/컨디션
│   │       └── guardian-alerts/   # 보호자 미복약 알림
│   └── .env.example
├── apps/mobile/           # Flutter 앱 (Android)
│   └── lib/
│       ├── main.dart
│       ├── core/
│       │   ├── theme.dart                 # AppTheme (#1E6FD9)
│       │   ├── storage.dart               # SharedPreferences (알림시간 포함)
│       │   ├── notification_service.dart  # 로컬 푸시 알림
│       │   ├── fcm_service.dart           # FCM 토큰 관리 · 포그라운드 알림
│       │   └── guardian_alert_service.dart # 보호자 미복약 알림 체크
│       ├── data/
│       │   ├── api_client.dart            # HTTP 클라이언트 ⚠️ IP 설정 필요
│       │   └── auth_repository.dart
│       └── features/
│           ├── auth/                  # 로그인 · 회원가입 · 프로필(알림시간설정)
│           ├── home/                  # 역할별 라우팅
│           ├── patient/               # 환자 모드 (홈/약관리/기록달력/통계/메모/약상세/연동요청수락)
│           └── guardian/              # 보호자 모드 (홈/통계/달력/가족연동)
└── infra/sql/             # DB 스키마 SQL (001~007 순서 실행)
```

---

## 🗄️ DB 스키마 파일 순서

| 파일 | 내용 |
|------|------|
| `001_init.sql` | users, medicines 기본 테이블 |
| `002_tables.sql` | patient_medicines, schedules, intake_logs |
| `003_feature_tables.sql` | family_map, points_badges |
| `004_daily_notes.sql` | 일일 메모/컨디션 테이블 |
| `005_guardian_alerts.sql` | 보호자 미복약 알림 테이블 |
| `006_fcm.sql` | users에 fcm_token 컬럼 추가, family_requests 테이블 |
| `007_medicines_data.sql` | 약 데이터 4,759건 초기 데이터 |

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

SQL 초기화 스크립트는 `infra/sql/` 폴더의 `001~006` 파일을 순서대로 실행합니다.

```powershell
# PowerShell 예시 (001~006 순서대로)
docker cp "infra\sql\006_fcm.sql" medilink-mysql:/006_fcm.sql
docker exec medilink-mysql mysql -u root -proot medilink -e "source /006_fcm.sql"
```

약 데이터(007) import:
```powershell
docker cp "infra\sql\007_medicines_data.sql" medilink-mysql:/007_medicines_data.sql
docker exec medilink-mysql mysql --default-character-set=utf8mb4 -u root -proot medilink -e "source /007_medicines_data.sql"
```

> ⚠️ **Windows에서 로컬 MySQL 충돌 시**
> ```powershell
> Get-Service | Where-Object {$_.Name -like "*mysql*"}
> net stop MySQL80
> ```

### 3. Firebase 설정

FCM 푸시 알림을 위해 Firebase 서비스 계정 키가 필요합니다.

1. [Firebase Console](https://console.firebase.google.com) → 프로젝트 설정 → 서비스 계정
2. "새 비공개 키 생성" → JSON 다운로드
3. `services/api/firebase-adminsdk.json` 으로 저장 (`.gitignore`에 포함되어 있으므로 직접 배치 필요)

### 4. 백엔드 실행
```bash
cd services/api
cp .env.example .env   # .env 파일 생성 후 필요시 수정
npm install
npm run dev
```

서버가 `http://localhost:4000` 에서 실행됩니다.

### 5. Flutter 실행

**⚠️ 반드시 먼저 API 주소를 설정해야 합니다**

`apps/mobile/lib/data/api_client.dart` 의 `_baseUrl` 수정:

```dart
// 안드로이드 에뮬레이터
static const String _baseUrl = 'http://10.0.2.2:4000/api';

// 실기기 (USB/Wi-Fi) → 본인 PC 로컬 IP로 변경
static const String _baseUrl = 'http://192.168.x.x:4000/api';
// Windows: ipconfig → IPv4 주소 확인
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
| GET | `/api/users/me` | 내 정보 조회 |
| PATCH | `/api/users/me/name` | 이름 변경 |
| PATCH | `/api/users/me/password` | 비밀번호 변경 |
| PATCH | `/api/users/me/fcm-token` | FCM 토큰 저장 |
| GET | `/api/medicines/search?q=` | 약 검색 (DB + e약은요 API) |
| GET | `/api/medicines/detail?name=` | 약 상세 정보 (e약은요 API) |
| POST | `/api/medicines` | 약 등록 |
| GET | `/api/patient-medicines/:patient_id` | 복용약 목록 |
| POST | `/api/patient-medicines` | 복용약 추가 |
| PATCH | `/api/patient-medicines/:id/deactivate` | 복용 중단 |
| PATCH | `/api/patient-medicines/:id/reactivate` | 복용 재개 |
| DELETE | `/api/patient-medicines/:id` | 복용약 삭제 |
| GET | `/api/schedules/today` | 오늘 스케줄 |
| GET | `/api/schedules/by-medicine/:id` | 약별 스케줄 조회 |
| PUT | `/api/schedules/by-medicine/:id` | 스케줄 수정 |
| POST | `/api/intake-logs` | 복약 체크 |
| GET | `/api/intake-logs/history` | 복약 기록 (환자 본인) |
| GET | `/api/intake-logs/patient-history` | 복약 기록 (보호자용 월별) |
| DELETE | `/api/intake-logs/:id` | 복약 취소 |
| GET | `/api/guardian/dashboard` | 보호자 대시보드 |
| GET | `/api/statistics/adherence` | 복약 통계 |
| GET | `/api/family-map/:id/patients` | 연동 환자 목록 |
| POST | `/api/family-map` | 가족 연동 (직접) |
| DELETE | `/api/family-map/patients/:patient_id` | 가족 연동 취소 |
| POST | `/api/family-requests/send` | 보호자 연동 요청 전송 |
| GET | `/api/family-requests/pending` | 환자 수신 연동 요청 목록 |
| POST | `/api/family-requests/respond` | 연동 요청 수락/거절 |
| GET | `/api/daily-notes` | 메모 조회 (특정 날짜) |
| GET | `/api/daily-notes/monthly` | 메모 월별 조회 (본인) |
| GET | `/api/daily-notes/patient-monthly` | 메모 월별 조회 (보호자용) |
| POST | `/api/daily-notes` | 메모 저장/수정 (upsert) |
| GET | `/api/guardian-alerts` | 보호자 미복약 알림 조회 |
| POST | `/api/guardian-alerts/read-all` | 알림 읽음 처리 |

---

## ⚙️ 환경변수 (.env)

```env
PORT=4000
DB_HOST=localhost
DB_PORT=3306
DB_USER=medilink
DB_PASSWORD=medilink123
DB_NAME=medilink
JWT_SECRET=your_jwt_secret_here
JWT_EXPIRES_IN=7d
DRUG_API_KEY=your_drug_api_key_here
```

> `DRUG_API_KEY`는 [공공데이터포털](https://www.data.go.kr)에서 **e약은요 API** 신청 후 발급

---

## 📝 개발 참고사항

| 항목 | 내용 |
|------|------|
| **시간대** | DB는 UTC 저장, 백엔드에서 `DATE_ADD(+9H)` 로 KST 변환 후 응답 |
| **사진 인증** | Base64 인코딩 → DB MEDIUMTEXT 저장 (실서비스 전 S3 교체 권장) |
| **상태관리** | Flutter `setState` 기반 (규모 커지면 Riverpod/Bloc 도입 고려) |
| **ORM** | 없음 — 모든 DB 쿼리는 raw `mysql2/promise` |
| **스케줄러** | `server.js`에서 1분마다 FCM 복약 알림, 1시간마다 미복약 체크, 24시간마다 비활성화/정리 |
| **약 데이터** | 자체 DB 4,759건 + 식약처 e약은요 API 실시간 병행 검색 |
| **FCM** | Firebase Cloud Messaging — 앱 꺼져도 복약알림/보호자알림/연동요청 알림 전송 |
| **언어** | 주석 및 사용자 메시지는 한국어 |

---

## 🛠️ 기술 스택

| 영역 | 기술 |
|------|------|
| Frontend | Flutter (Dart) |
| Backend | Node.js + Express |
| Database | MySQL 8.0 (utf8mb4) |
| 인프라 | Docker Compose |
| 인증 | JWT |
| 푸시 알림 | Firebase Cloud Messaging (FCM) |
| 약 정보 | 식품의약품안전처 e약은요 API |
| HTTP 통신 | http 패키지 (Flutter), mysql2/promise (Node.js) |
