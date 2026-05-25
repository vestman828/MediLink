require('dotenv').config();
const fs = require('fs');
const http = require('http');
const https = require('https');
const path = require('path');
const app = require('./app');
const pool = require('./config/db');
const { sendFcmNotification } = require('./config/firebase');
const { runMedicineSyncIfDue } = require('./modules/medicines/medicine-sync.service');
const { deleteUploadedImageByUrl } = require('./utils/image-storage');

const PORT = process.env.PORT || 4000;
const HTTPS_ENABLED =
  String(process.env.HTTPS_ENABLED || '').toLowerCase() === 'true' ||
  process.env.HTTPS_ENABLED === '1';

const intakeLogRetentionDays = Number(process.env.INTAKE_LOG_RETENTION_DAYS || 180);
const INTAKE_LOG_RETENTION_DAYS =
  Number.isFinite(intakeLogRetentionDays) && intakeLogRetentionDays > 0
    ? Math.min(Math.floor(intakeLogRetentionDays), 3650)
    : 180;

const SLOT_TIMES = {
  morning: { hour: 8, minute: 0, label: '아침' },
  lunch: { hour: 12, minute: 0, label: '점심' },
  dinner: { hour: 18, minute: 0, label: '저녁' },
  bedtime: { hour: 22, minute: 0, label: '취침' },
};

const SLOT_CUTOFF = {
  morning: { hour: 10, minute: 0 },
  lunch: { hour: 14, minute: 0 },
  dinner: { hour: 20, minute: 0 },
  bedtime: { hour: 0, minute: 0 },
};

function resolvePath(filePath) {
  return path.isAbsolute(filePath) ? filePath : path.resolve(process.cwd(), filePath);
}

function createServer() {
  if (!HTTPS_ENABLED) return http.createServer(app);

  const pfxPath = process.env.HTTPS_PFX_PATH;
  const pfxPassword = process.env.HTTPS_PFX_PASSWORD || '';
  if (pfxPath) {
    const pfx = fs.readFileSync(resolvePath(pfxPath));
    return https.createServer({ pfx, passphrase: pfxPassword }, app);
  }

  const certPath = process.env.HTTPS_CERT_PATH;
  const keyPath = process.env.HTTPS_KEY_PATH;
  if (!certPath || !keyPath) {
    throw new Error(
      'HTTPS_ENABLED is true, but HTTPS_PFX_PATH or HTTPS_CERT_PATH/HTTPS_KEY_PATH is missing.'
    );
  }

  const cert = fs.readFileSync(resolvePath(certPath));
  const key = fs.readFileSync(resolvePath(keyPath));
  return https.createServer({ cert, key }, app);
}

function getKstDateString(base = new Date()) {
  return new Date(base.getTime() + 9 * 60 * 60 * 1000)
    .toISOString()
    .slice(0, 10);
}

function getKstHourMinute(base = new Date()) {
  return {
    hour: (base.getUTCHours() + 9) % 24,
    minute: base.getUTCMinutes(),
  };
}

function startScheduler() {
  const sentMedicationAlerts = new Set();

  const runMedicationAlerts = async () => {
    try {
      const now = new Date();
      const { hour: kstHour, minute: kstMinute } = getKstHourMinute(now);
      const kstDate = getKstDateString(now);

      for (const [slot, time] of Object.entries(SLOT_TIMES)) {
        const reminderHour = (time.hour + Math.floor((time.minute + 30) / 60)) % 24;
        const reminderMinute = (time.minute + 30) % 60;

        const isMainTime = kstHour === time.hour && kstMinute === time.minute;
        const isReminderTime = kstHour === reminderHour && kstMinute === reminderMinute;

        const mainKey = `${slot}_main_${kstDate}`;
        const reminderKey = `${slot}_reminder_${kstDate}`;

        if (isMainTime && !sentMedicationAlerts.has(mainKey)) {
          sentMedicationAlerts.add(mainKey);

          const [patients] = await pool.query(
            `SELECT DISTINCT u.fcm_token
             FROM schedules s
             JOIN patient_medicines pm ON s.patient_medicine_id = pm.patient_medicine_id
             JOIN users u ON pm.patient_id = u.user_id
             WHERE pm.is_active = 1
               AND s.time_slot = ?
               AND s.day_of_week = WEEKDAY(DATE_ADD(UTC_TIMESTAMP(), INTERVAL 9 HOUR))
               AND u.fcm_token IS NOT NULL`,
            [slot]
          );

          for (const p of patients) {
            await sendFcmNotification(
              p.fcm_token,
              '복약 시간입니다',
              `${time.label} 복약 시간을 확인해주세요.`
            );
          }

          if (patients.length > 0) {
            console.log(`[FCM] ${time.label} 복약 알림 ${patients.length}명 전송`);
          }
        }

        if (isReminderTime && !sentMedicationAlerts.has(reminderKey)) {
          sentMedicationAlerts.add(reminderKey);

          const [patients] = await pool.query(
            `SELECT DISTINCT u.fcm_token
             FROM schedules s
             JOIN patient_medicines pm ON s.patient_medicine_id = pm.patient_medicine_id
             JOIN users u ON pm.patient_id = u.user_id
             WHERE pm.is_active = 1
               AND s.time_slot = ?
               AND s.day_of_week = WEEKDAY(DATE_ADD(UTC_TIMESTAMP(), INTERVAL 9 HOUR))
               AND u.fcm_token IS NOT NULL
               AND NOT EXISTS (
                 SELECT 1
                 FROM intake_logs il
                 WHERE il.schedule_id = s.schedule_id
                   AND il.patient_id = pm.patient_id
                   AND DATE(DATE_ADD(il.taken_at, INTERVAL 9 HOUR)) = DATE(DATE_ADD(UTC_TIMESTAMP(), INTERVAL 9 HOUR))
               )`,
            [slot]
          );

          for (const p of patients) {
            await sendFcmNotification(
              p.fcm_token,
              '아직 복약하지 않았나요?',
              `${time.label} 약을 아직 복용하지 않았습니다.`
            );
          }

          if (patients.length > 0) {
            console.log(`[FCM] ${time.label} 30분 재알림 ${patients.length}명 전송`);
          }
        }
      }
    } catch (err) {
      console.error('[스케줄러] FCM 복약 알림 오류:', err);
    }
  };

  const runDeactivation = async () => {
    try {
      const [result] = await pool.query(
        `UPDATE patient_medicines
         SET is_active = 0
         WHERE is_active = 1
           AND end_date IS NOT NULL
           AND end_date < DATE(DATE_ADD(UTC_TIMESTAMP(), INTERVAL 9 HOUR))`
      );

      if (result.affectedRows > 0) {
        console.log(`[스케줄러] 복용 종료 약 ${result.affectedRows}건 자동 비활성화`);
      }
    } catch (err) {
      console.error('[스케줄러] 자동 비활성화 오류:', err);
    }
  };

  const runMissedCheck = async () => {
    try {
      const now = new Date();
      const { hour: kstHour, minute: kstMinute } = getKstHourMinute(now);

      const nowMinutes = kstHour * 60 + kstMinute;
      const slotsToCheck = Object.entries(SLOT_CUTOFF)
        .filter(([slot, cutoff]) => {
          const cutoffMinutes = cutoff.hour * 60 + cutoff.minute;
          const slotMinutes = SLOT_TIMES[slot].hour * 60 + SLOT_TIMES[slot].minute;
          // 커트오프가 슬롯 시간보다 작으면 자정을 넘어가는 케이스(취침 22:00 → 커트오프 00:00).
          // 이 경우 현재 시각이 슬롯 예정 시간을 지난 경우에만 미복약으로 판단한다.
          if (cutoffMinutes < slotMinutes) return nowMinutes >= slotMinutes;
          return nowMinutes >= cutoffMinutes;
        })
        .map(([slot]) => slot);

      if (slotsToCheck.length === 0) return;

      for (const slot of slotsToCheck) {
        const [missedPatients] = await pool.query(
          `SELECT DISTINCT
             pm.patient_id,
             u.name AS patient_name,
             fm.guardian_id
           FROM schedules s
           JOIN patient_medicines pm ON s.patient_medicine_id = pm.patient_medicine_id
           JOIN users u ON pm.patient_id = u.user_id
           JOIN family_map fm ON fm.patient_id = pm.patient_id
           WHERE pm.is_active = 1
             AND s.time_slot = ?
             AND s.day_of_week = WEEKDAY(DATE_ADD(UTC_TIMESTAMP(), INTERVAL 9 HOUR))
             AND NOT EXISTS (
               SELECT 1
               FROM intake_logs il
               WHERE il.schedule_id = s.schedule_id
                 AND il.patient_id = pm.patient_id
                 AND DATE(DATE_ADD(il.taken_at, INTERVAL 9 HOUR)) = DATE(DATE_ADD(UTC_TIMESTAMP(), INTERVAL 9 HOUR))
             )`,
          [slot]
        );

        for (const row of missedPatients) {
          const [insertResult] = await pool.query(
            `INSERT IGNORE INTO guardian_alerts
               (guardian_id, patient_id, patient_name, time_slot, alert_date)
             VALUES (?, ?, ?, ?, DATE(DATE_ADD(UTC_TIMESTAMP(), INTERVAL 9 HOUR)))`,
            [row.guardian_id, row.patient_id, row.patient_name, slot]
          );

          if (insertResult.affectedRows > 0) {
            const slotLabel = SLOT_TIMES[slot]?.label || slot;
            const [guardians] = await pool.query(
              `SELECT fcm_token
               FROM users
               WHERE user_id = ?
               LIMIT 1`,
              [row.guardian_id]
            );

            if (guardians[0]?.fcm_token) {
              await sendFcmNotification(
                guardians[0].fcm_token,
                '미복약 알림',
                `${row.patient_name} 환자가 ${slotLabel} 약을 복용하지 않았습니다.`
              );
            }
          }
        }

        if (missedPatients.length > 0) {
          console.log(`[스케줄러] 미복약 알림 생성: ${slot} - ${missedPatients.length}건`);
        }
      }
    } catch (err) {
      console.error('[스케줄러] 미복약 체크 오류:', err);
    }
  };

  const runAlertCleanup = async () => {
    try {
      await pool.query(
        `DELETE FROM guardian_alerts
         WHERE alert_date < DATE_SUB(DATE(DATE_ADD(UTC_TIMESTAMP(), INTERVAL 9 HOUR)), INTERVAL 3 DAY)`
      );
    } catch (err) {
      console.error('[스케줄러] 알림 정리 오류:', err);
    }
  };

  const runIntakeLogCleanup = async () => {
    try {
      const [expiredLogs] = await pool.query(
        `SELECT log_id, photo_url
         FROM intake_logs
         WHERE DATE(DATE_ADD(taken_at, INTERVAL 9 HOUR)) <
               DATE_SUB(DATE(DATE_ADD(UTC_TIMESTAMP(), INTERVAL 9 HOUR)), INTERVAL ${INTAKE_LOG_RETENTION_DAYS} DAY)`
      );

      if (expiredLogs.length === 0) return;

      const [result] = await pool.query(
        `DELETE FROM intake_logs
         WHERE log_id IN (?)`,
        [expiredLogs.map((log) => log.log_id)]
      );

      await Promise.all(
        expiredLogs.map((log) => deleteUploadedImageByUrl(log.photo_url))
      );

      if (result.affectedRows > 0) {
        console.log(
          `[스케줄러] 오래된 복약 기록 ${result.affectedRows}건 삭제 (보관 ${INTAKE_LOG_RETENTION_DAYS}일)`
        );
      }
    } catch (err) {
      console.error('[스케줄러] 복약 기록 정리 오류:', err);
    }
  };

  const runMedicineSync = async () => {
    try {
      const result = await runMedicineSyncIfDue();
      if (result.executed) {
        console.log(
          `[스케줄러] 의약품 동기화 완료: 수집 ${result.scannedItems}건, 신규 ${result.insertedCount}건`
        );
        return;
      }
      if (result.reason === 'no_api_key') {
        console.log('[스케줄러] 의약품 동기화 건너뜀: DRUG_API_KEY 미설정');
      }
    } catch (err) {
      console.error('[스케줄러] 의약품 동기화 오류:', err);
    }
  };

  runMedicationAlerts();
  setInterval(runMedicationAlerts, 60 * 1000);

  runDeactivation();
  setInterval(runDeactivation, 24 * 60 * 60 * 1000);

  runMissedCheck();
  setInterval(runMissedCheck, 60 * 60 * 1000);

  runAlertCleanup();
  setInterval(runAlertCleanup, 24 * 60 * 60 * 1000);

  runIntakeLogCleanup();
  setInterval(runIntakeLogCleanup, 24 * 60 * 60 * 1000);

  runMedicineSync();
  setInterval(runMedicineSync, 24 * 60 * 60 * 1000);
}

const server = createServer();
server.listen(PORT, () => {
  const protocol = HTTPS_ENABLED ? 'https' : 'http';
  console.log(`Server listening on ${protocol}://localhost:${PORT}`);
  startScheduler();
});

server.on('error', (err) => {
  console.error('Server error:', err);
});

process.on('uncaughtException', (err) => {
  console.error('Uncaught Exception:', err);
});

process.on('unhandledRejection', (reason) => {
  console.error('Unhandled Rejection:', reason);
});
