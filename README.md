# MediLink

만성질환 노인을 위한 복약 관리 및 보호자 연동 플랫폼

## Repository Structure

```text
medilink/
├─ apps/
│  └─ mobile/            # Flutter app
├─ services/
│  └─ api/               # Node.js + Express API
├─ infra/
│  ├─ docker/
│  └─ sql/
├─ docs/
├─ docker-compose.yml
└─ README.md
```

## Tech Stack

- Mobile: Flutter
- Backend: Node.js + Express
- DB: MySQL 8
- Auth: JWT
- Notification: Firebase Cloud Messaging
- File Upload: Multipart

## Quick Start

### 1. Start MySQL

```bash
docker compose up -d
```

### 2. Backend

```bash
cd services/api
npm install
npm run dev
```

### 3. Flutter app

```bash
cd apps/mobile
flutter pub get
flutter run
```

## Branch Strategy

- `main`: production-safe
- `develop`: integration branch
- `feature/*`: feature branches

## Initial Milestone

1. Auth signup/login
2. Family mapping
3. Today's schedule query
4. Intake log creation
5. Guardian dashboard
