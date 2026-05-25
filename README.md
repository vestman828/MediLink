# MediLink

고령 환자의 복약 관리를 돕고, 보호자가 상태를 모니터링할 수 있는 모바일+API 프로젝트입니다.

## 프로젝트 구조

- `apps/mobile`: Flutter 앱 (환자/보호자)
- `services/api`: Node.js + Express API
- `infra/sql`: MySQL 스키마/초기 데이터 SQL

## 주요 기능

- 휴대폰 OTP 기반 회원가입/로그인
- 환자: 약 추가, 복용 스케줄 관리, 복약 체크(일반/사진), 일일 메모, 통계
- 보호자: 환자 연동, 대시보드, 미복약 알림(FCM), 통계 조회
- 서버 스케줄러: 미복약 체크, 알림 정리, 복용 종료 약 비활성화

## 요구사항

- Node.js 18+
- Flutter SDK
- Docker Desktop
- Android Studio (에뮬레이터 사용 시)

## 로컬 실행

### 1) DB 실행

```bash
docker compose up -d
```

### 2) DB 스키마 적용

필수 SQL:

- `infra/sql/001_init.sql`
- `infra/sql/002_tables.sql`
- `infra/sql/003_feature_tables.sql`
- `infra/sql/004_daily_notes.sql`
- `infra/sql/005_guardian_alerts.sql`
- `infra/sql/006_fcm.sql`
- `infra/sql/007_medicines_data.sql`
- `infra/sql/008_phone_verifications.sql`
- `infra/sql/009_medicine_sync.sql`

예시(Windows + Docker):

```powershell
docker cp "infra\\sql\\001_init.sql" medilink-mysql:/001_init.sql
docker exec medilink-mysql mysql --default-character-set=utf8mb4 -u root -proot medilink -e "source /001_init.sql"
```

의약품 데이터(`007_medicines_data.sql`)는 한글 포함 대용량이므로 반드시 `utf8mb4`로 로드하세요.

```powershell
docker cp "infra\\sql\\007_medicines_data.sql" medilink-mysql:/007_medicines_data.sql
docker exec medilink-mysql mysql --default-character-set=utf8mb4 -u root -proot medilink -e "source /007_medicines_data.sql"
```

### 3) API 실행

```bash
cd services/api
cp .env.example .env
npm install
npm run dev
```

### 4) 모바일 실행

```bash
cd apps/mobile
flutter pub get
flutter run -d emulator-5554 --dart-define=MEDILINK_API_BASE_URL=https://10.0.2.2:4000/api
```

## 환경변수 (`services/api/.env`)

```env
PORT=4000
HTTPS_ENABLED=false
HTTPS_PFX_PATH=
HTTPS_PFX_PASSWORD=
HTTPS_CERT_PATH=
HTTPS_KEY_PATH=
DB_HOST=localhost
DB_PORT=3306
DB_USER=medilink
DB_PASSWORD=medilink123
DB_NAME=medilink
JWT_SECRET=your_jwt_secret_here
JWT_EXPIRES_IN=7d
DRUG_API_KEY=
SOLAPI_API_KEY=
SOLAPI_API_SECRET=
SOLAPI_SENDER=
EXPOSE_OTP_CODE=true
INTAKE_LOG_RETENTION_DAYS=180
```

- `DRUG_API_KEY`: 설정 시 서버가 하루 1회 동기화 조건을 확인하고, 7일에 1회만 공공데이터 의약품을 `medicines`에 반영(신규/빈 설명 보강)
- `SOLAPI_*`: 실제 SMS OTP 발송 사용 시 필요
- `EXPOSE_OTP_CODE=true`: 개발 모드 OTP 코드 노출
- `INTAKE_LOG_RETENTION_DAYS`: 오래된 복약 기록 자동 삭제 보관일(기본 180일)

## 인코딩(문자 깨짐) 주의

이 프로젝트 텍스트 파일은 UTF-8 기준입니다.

- VS Code: 우측 하단 인코딩을 `UTF-8`로 열기
- PowerShell에서 파일 확인 시:

```powershell
Get-Content .\README.md -Encoding utf8
```

PowerShell 콘솔 자체가 깨지면 다음도 함께 사용하세요:

```powershell
chcp 65001
```

## 폴더 복사 시 "파일 경로가 너무 깁니다" 해결

긴 경로의 대부분은 Flutter 빌드 산출물(`apps/mobile/build`)에서 발생합니다.
복사 전 아래 스크립트로 정리하세요.

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\prepare-copy.ps1
```

`node_modules`까지 지우고 최소 크기로 복사하려면:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\prepare-copy.ps1 -IncludeNodeModules
```

추가로 Windows 정책에서 긴 경로를 허용하면 복사 실패를 줄일 수 있습니다.

```powershell
reg query "HKLM\SYSTEM\CurrentControlSet\Control\FileSystem" /v LongPathsEnabled
```

값이 `0x1`이 아니면 관리자 권한에서 활성화가 필요합니다.

## 참고

- API 헬스체크: `GET /health`
- 모바일에서 에뮬레이터 사용 시 API 호스트는 `10.0.2.2`
- 실기기 테스트 시 `MEDILINK_API_BASE_URL`을 PC의 로컬 IP로 변경
