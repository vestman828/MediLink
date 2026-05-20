# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

MediLink is a medication management platform for elderly patients with caregiver/guardian oversight.
- **Backend**: Node.js/Express REST API (fully implemented: auth, medicines, schedules, intake-logs, guardian, statistics, family-map)
- **Frontend**: Flutter mobile app (Android, patient/guardian dual mode)
- **DB**: MySQL 8.0 via Docker

## 팀원 개발환경 셋업 (처음 클론 시)

### 1. DB 실행
```bash
docker compose up -d
```

### 2. 백엔드 실행
```bash
cd services/api
cp .env.example .env   # .env 파일 생성 후 필요시 수정
npm install
npm run dev
```

### 3. Flutter 실행
```bash
cd apps/mobile
flutter pub get
flutter run
```

> ⚠️ **실기기(핸드폰) 연결 시 반드시** `apps/mobile/lib/data/api_client.dart`의 `_baseUrl`을
> 본인 PC의 로컬 IP로 변경해야 합니다.
> - Windows: `ipconfig` 실행 후 IPv4 주소 확인
> - Mac/Linux: `ifconfig | grep inet`
> - 안드로이드 에뮬레이터는 `10.0.2.2:4000` 그대로 사용

### 4. Windows에서 MySQL 충돌 시
로컬에 MySQL이 설치되어 있으면 3306 포트 충돌 발생. 해결:
```powershell
Get-Service | Where-Object {$_.Name -like "*mysql*"}
net stop <서비스명>   # 예: net stop MySQL80
```

## Commands

### Backend API (`services/api/`)
```bash
npm install        # 의존성 설치
npm run dev        # 개발 (nodemon 핫리로드)
npm start          # 프로덕션
```

### Database
```bash
docker compose up -d    # MySQL 시작
docker compose down     # MySQL 중지
```
SQL 초기화 스크립트: `infra/sql/` (001~003 순서대로 자동 실행)

### Flutter Mobile (`apps/mobile/`)
```bash
flutter pub get
flutter run -d <device_id>   # flutter devices 로 기기 ID 확인
```

## Architecture

```
MediLink-main/
├── services/api/       # Node.js/Express REST API
│   └── src/
│       ├── server.js           # 진입점
│       ├── app.js              # Express 설정, 라우트 마운트
│       ├── config/db.js        # mysql2/promise 커넥션 풀
│       ├── middleware/
│       │   ├── auth.js         # JWT 검증 → req.user
│       │   └── role.js         # RBAC (현재 미적용)
│       └── modules/
│           ├── auth/           # 회원가입 · 로그인
│           ├── medicines/      # 약 검색 · 등록
│           ├── patient-medicines/  # 환자별 복용약 (CRUD)
│           ├── schedules/      # 복약 스케줄 (생성 · 수정)
│           ├── intake-logs/    # 복약 기록 (체크 · 사진 · 취소)
│           ├── guardian/       # 보호자 대시보드
│           ├── statistics/     # 복약 통계 (7일/30일)
│           └── family-map/     # 보호자-환자 연동
├── apps/mobile/        # Flutter 앱
│   └── lib/
│       ├── main.dart
│       ├── core/
│       │   ├── theme.dart          # AppTheme (#1E6FD9)
│       │   ├── storage.dart        # SharedPreferences
│       │   └── notification_service.dart  # 로컬 푸시 알림
│       ├── data/
│       │   ├── api_client.dart     # HTTP 클라이언트 ⚠️ IP 수정 필요
│       │   └── auth_repository.dart
│       └── features/
│           ├── auth/               # 로그인 · 회원가입
│           ├── home/               # 역할별 라우팅
│           ├── patient/            # 환자 모드 (홈, 약관리, 기록, 통계)
│           └── guardian/           # 보호자 모드 (홈, 통계, 가족연동)
└── infra/sql/          # DB 스키마 (001~003)
```

## API 엔드포인트 요약

| Method | Path | 설명 |
|--------|------|------|
| POST | /api/auth/signup | 회원가입 |
| POST | /api/auth/login | 로그인 |
| GET | /api/medicines/search?q= | 약 검색 |
| POST | /api/medicines | 약 등록 |
| GET | /api/patient-medicines/:patient_id | 복용약 목록 |
| POST | /api/patient-medicines | 복용약 추가 |
| PATCH | /api/patient-medicines/:id/deactivate | 복용 중단 |
| PATCH | /api/patient-medicines/:id/reactivate | 복용 재개 |
| DELETE | /api/patient-medicines/:id | 복용약 삭제 |
| GET | /api/schedules/today | 오늘 스케줄 |
| GET | /api/schedules/by-medicine/:id | 약별 스케줄 조회 |
| PUT | /api/schedules/by-medicine/:id | 스케줄 수정 |
| POST | /api/intake-logs | 복약 체크 |
| GET | /api/intake-logs/history | 복약 기록 |
| DELETE | /api/intake-logs/:id | 복약 취소 |
| GET | /api/guardian/dashboard | 보호자 대시보드 |
| GET | /api/statistics/adherence | 복약 통계 |
| GET | /api/family-map/:id/patients | 연동 환자 목록 |
| POST | /api/family-map | 가족 연동 |

## Known Issues / Notes

**Flutter API base URL:** `api_client.dart`의 `_baseUrl`은 각자 개발 환경에 맞게 수정 필요.

**시간대:** DB는 UTC 저장, 백엔드에서 `DATE_ADD(+9 HOUR)`로 KST 변환 후 응답.

**사진 인증:** Base64로 인코딩해서 DB에 저장 (MEDIUMTEXT). 실서비스 전 S3 등 파일 서버로 교체 권장.

**Flutter 상태관리:** 현재 `setState` 기반. 규모 커지면 Riverpod/Bloc 도입 고려.

**No ORM:** 모든 DB 쿼리는 raw `mysql2/promise`.

**Language:** 주석 및 사용자 메시지는 한국어.
