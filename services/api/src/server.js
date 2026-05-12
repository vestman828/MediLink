require('dotenv').config();
const app = require('./app');
const pool = require('./config/db');

const PORT = process.env.PORT || 4000;

const server = app.listen(PORT, () => {
  console.log(`Server listening on port ${PORT}`);
  startScheduler();
});

// 슬롯별 기준 시각 (KST) - 복용 시간 + 2시간 이후에도 미복약이면 알림
// 아침 08:00 + 2h = 10:00, 점심 12:00 + 2h = 14:00, 저녁 18:00 + 2h = 20:00, 취침 22:00 + 2h = 24:00(=0)
const SLOT_CUTOFF = {
  morning:  { hour: 10, minute: 0 },
  lunch:    { hour: 14, minute: 0 },
  dinner:   { hour: 20, minute: 0 },
  bedtime:  { hour: 0,  minute: 0 },  // 자정 이후
};

function startScheduler() {
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
          await pool.query(
            `INSERT IGNORE INTO guardian_alerts
               (guardian_id, patient_id, patient_name, time_slot, alert_date)
             VALUES (?, ?, ?, ?, CURDATE())`,
            [row.guardian_id, row.patient_id, row.patient_name, slot]
          );
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
