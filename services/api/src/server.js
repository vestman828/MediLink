require('dotenv').config();
const app = require('./app');
const pool = require('./config/db');
const { sendFcmNotification } = require('./config/firebase');

const PORT = process.env.PORT || 4000;

const server = app.listen(PORT, () => {
  console.log(`Server listening on port ${PORT}`);
  startScheduler();
});

// 슬롯별 복약 시각 (KST)
const SLOT_TIMES = {
  morning: { hour: 8,  minute: 0,  label: '아침' },
  lunch:   { hour: 12, minute: 0,  label: '점심' },
  dinner:  { hour: 18, minute: 0,  label: '저녁' },
  bedtime: { hour: 22, minute: 0,  label: '취침' },
};

// 슬롯별 기준 시각 (KST) - 복용 시간 + 2시간 이후에도 미복약이면 알림
const SLOT_CUTOFF = {
  morning:  { hour: 10, minute: 0 },
  lunch:    { hour: 14, minute: 0 },
  dinner:   { hour: 20, minute: 0 },
  bedtime:  { hour: 0,  minute: 0 },
};

function startScheduler() {

  // ── 0. FCM 복약 알림 (매 분마다 시간 체크) ──
  const sentMedicationAlerts = new Set(); // 중복 방지

  const runMedicationAlerts = async () => {
    try {
      const now = new Date();
      const kstHour = (now.getUTCHours() + 9) % 24;
      const kstMinute = now.getUTCMinutes();

      for (const [slot, time] of Object.entries(SLOT_TIMES)) {
        const isMainTime = kstHour === time.hour && kstMinute === time.minute;
        const isReminderTime = kstHour === time.hour + Math.floor((time.minute + 30) / 60)
          && kstMinute === (time.minute + 30) % 60;

        const dateKey = now.toISOString().slice(0, 10);
        const mainKey = `${slot}_main_${dateKey}`;
        const reminderKey = `${slot}_reminder_${dateKey}`;

        // 1차 알림: 복약 시간
        if (isMainTime && !sentMedicationAlerts.has(mainKey)) {
          sentMedicationAlerts.add(mainKey);
          const [patients] = await pool.query(
            `SELECT DISTINCT u.fcm_token
             FROM schedules s
             JOIN patient_medicines pm ON s.patient_medicine_id = pm.patient_medicine_id
             JOIN users u ON pm.patient_id = u.user_id
             WHERE pm.is_active = 1
               AND s.time_slot = ?
               AND s.day_of_week = WEEKDAY(NOW())
               AND u.fcm_token IS NOT NULL`,
            [slot]
          );
          for (const p of patients) {
            await sendFcmNotification(p.fcm_token, '💊 복약 시간이에요!', `${time.label} 복약을 잊지 마세요`);
          }
          if (patients.length > 0) console.log(`[FCM] ${time.label} 복약 알림 ${patients.length}명 전송`);
        }

        // 2차 알림: 30분 후 재알림 (아직 미복약인 경우만)
        if (isReminderTime && !sentMedicationAlerts.has(reminderKey)) {
          sentMedicationAlerts.add(reminderKey);
          const [patients] = await pool.query(
            `SELECT DISTINCT u.fcm_token
             FROM schedules s
             JOIN patient_medicines pm ON s.patient_medicine_id = pm.patient_medicine_id
             JOIN users u ON pm.patient_id = u.user_id
             WHERE pm.is_active = 1
               AND s.time_slot = ?
               AND s.day_of_week = WEEKDAY(NOW())
               AND u.fcm_token IS NOT NULL
               AND NOT EXISTS (
                 SELECT 1 FROM intake_logs il
                 WHERE il.schedule_id = s.schedule_id
                   AND il.patient_id = pm.patient_id
                   AND DATE(DATE_ADD(il.taken_at, INTERVAL 9 HOUR)) = CURDATE()
               )`,
            [slot]
          );
          for (const p of patients) {
            await sendFcmNotification(p.fcm_token, '⚠️ 아직 복약 안 하셨나요?', `${time.label} 약을 아직 드시지 않으셨어요!`);
          }
          if (patients.length > 0) console.log(`[FCM] ${time.label} 재알림 ${patients.length}명 전송`);
        }
      }
    } catch (err) {
      console.error('[스케줄러] FCM 복약 알림 오류:', err);
    }
  };

  // ── 1. end_date 지난 약 자동 비활성화 (매일) ──
  const runDeactivation = async () => {
    try {
      const [result] = await pool.query(
        `UPDATE patient_medicines
         SET is_active = 0
         WHERE is_active = 1
           AND end_date IS NOT NULL
           AND end_date < CURDATE()`
      );
      if (result.affectedRows > 0) {
        console.log(`[스케줄러] 복용 종료일 지난 약 ${result.affectedRows}건 자동 비활성화`);
      }
    } catch (err) {
      console.error('[스케줄러] 자동 비활성화 오류:', err);
    }
  };

  // ── 2. 미복약 보호자 알림 생성 (매 시간) ──
  const runMissedCheck = async () => {
    try {
      const now = new Date();
      // KST = UTC+9
      const kstHour = (now.getUTCHours() + 9) % 24;
      const kstMinute = now.getUTCMinutes();

      // 현재 KST 시각이 지난 슬롯만 체크
      const slotsToCheck = Object.entries(SLOT_CUTOFF).filter(([, cutoff]) => {
        const cutoffMinutes = cutoff.hour * 60 + cutoff.minute;
        const nowMinutes = kstHour * 60 + kstMinute;
        return nowMinutes >= cutoffMinutes;
      }).map(([slot]) => slot);

      if (slotsToCheck.length === 0) return;

      for (const slot of slotsToCheck) {
        // 오늘 해당 슬롯 스케줄이 있는데 복약 기록 없는 환자 조회
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
             AND s.day_of_week = WEEKDAY(NOW())
             AND NOT EXISTS (
               SELECT 1 FROM intake_logs il
               WHERE il.schedule_id = s.schedule_id
                 AND il.patient_id = pm.patient_id
                 AND DATE(DATE_ADD(il.taken_at, INTERVAL 9 HOUR)) = CURDATE()
             )`,
          [slot]
        );

        for (const row of missedPatients) {
          // upsert - 같은 날 같은 슬롯 알림은 중복 생성 안 함
          const [insertResult] = await pool.query(
            `INSERT IGNORE INTO guardian_alerts
               (guardian_id, patient_id, patient_name, time_slot, alert_date)
             VALUES (?, ?, ?, ?, CURDATE())`,
            [row.guardian_id, row.patient_id, row.patient_name, slot]
          );

          // 새로 생성된 알림만 FCM 전송
          if (insertResult.affectedRows > 0) {
            const slotLabel = SLOT_TIMES[slot]?.label ?? slot;
            const [guardians] = await pool.query(
              `SELECT fcm_token FROM users WHERE user_id = ?`,
              [row.guardian_id]
            );
            if (guardians[0]?.fcm_token) {
              await sendFcmNotification(
                guardians[0].fcm_token,
                '💊 미복약 알림',
                `${row.patient_name}님이 ${slotLabel} 약을 아직 드시지 않으셨어요!`
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

  // ── 3. 오래된 알림 자동 삭제 (매일 자정, 3일 지난 알림 삭제) ──
  const runAlertCleanup = async () => {
    try {
      await pool.query(
        `DELETE FROM guardian_alerts WHERE alert_date < DATE_SUB(CURDATE(), INTERVAL 3 DAY)`
      );
    } catch (err) {
      console.error('[스케줄러] 알림 정리 오류:', err);
    }
  };

  runMedicationAlerts();
  setInterval(runMedicationAlerts, 60 * 1000); // 매 1분마다 시간 체크

  runDeactivation();
  setInterval(runDeactivation, 24 * 60 * 60 * 1000);

  runMissedCheck();
  setInterval(runMissedCheck, 60 * 60 * 1000); // 매 1시간

  runAlertCleanup();
  setInterval(runAlertCleanup, 24 * 60 * 60 * 1000); // 매 24시간
}

server.on('error', (err) => {
  console.error('Server error:', err);
});

process.on('uncaughtException', (err) => {
  console.error('Uncaught Exception:', err);
});

process.on('unhandledRejection', (reason) => {
  console.error('Unhandled Rejection:', reason);
});
