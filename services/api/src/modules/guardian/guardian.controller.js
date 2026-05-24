const pool = require('../../config/db');

async function getDashboard(req, res) {
  try {
    const { guardian_id } = req.query;
    const guardianId = Number(guardian_id);

    if (!guardianId) {
      return res.status(400).json({ success: false, message: 'guardian_id가 필요합니다.' });
    }

    if (req.user.role !== 'guardian' || req.user.user_id !== guardianId) {
      return res.status(403).json({ success: false, message: '본인 계정으로만 조회할 수 있습니다.' });
    }

    const [patients] = await pool.query(
      `SELECT u.user_id, u.name
       FROM family_map fm
       JOIN users u ON fm.patient_id = u.user_id
       WHERE fm.guardian_id = ?`,
      [guardianId]
    );

    const result = [];
    for (const patient of patients) {
      const [schedules] = await pool.query(
        `SELECT
           s.schedule_id,
           m.name AS medicine_name,
           pm.dose,
           s.time_slot,
           s.scheduled_time,
           CASE
             WHEN il.log_id IS NOT NULL THEN 'taken'
             WHEN s.scheduled_time < TIME(DATE_ADD(UTC_TIMESTAMP(), INTERVAL 7 HOUR)) THEN 'missed'
             ELSE 'pending'
           END AS status,
           il.auth_method,
           il.photo_url
         FROM schedules s
         JOIN patient_medicines pm ON s.patient_medicine_id = pm.patient_medicine_id
         JOIN medicines m ON pm.medicine_id = m.medicine_id
         LEFT JOIN intake_logs il
           ON il.schedule_id = s.schedule_id
           AND il.patient_id = pm.patient_id
           AND DATE(DATE_ADD(il.taken_at, INTERVAL 9 HOUR)) = DATE(DATE_ADD(UTC_TIMESTAMP(), INTERVAL 9 HOUR))
         WHERE pm.patient_id = ?
           AND pm.is_active = 1
           AND s.day_of_week = WEEKDAY(DATE_ADD(UTC_TIMESTAMP(), INTERVAL 9 HOUR))
         ORDER BY s.scheduled_time`,
        [patient.user_id]
      );

      const [adherence] = await pool.query(
        `SELECT COUNT(DISTINCT DATE(DATE_ADD(il.taken_at, INTERVAL 9 HOUR))) AS taken_days
         FROM intake_logs il
         WHERE il.patient_id = ?
           AND DATE(DATE_ADD(il.taken_at, INTERVAL 9 HOUR)) >= DATE_SUB(DATE(DATE_ADD(UTC_TIMESTAMP(), INTERVAL 9 HOUR)), INTERVAL 6 DAY)`,
        [patient.user_id]
      );

      const takenDays = adherence[0]?.taken_days || 0;
      const adherenceRate = Math.round((takenDays / 7) * 100);

      result.push({
        patient_id: patient.user_id,
        patient_name: patient.name,
        today_schedules: schedules,
        adherence_rate_7days: adherenceRate,
        missed_count: schedules.filter((s) => s.status === 'missed').length,
      });
    }

    return res.json({ success: true, data: result });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false, message: '서버 오류' });
  }
}

module.exports = { getDashboard };
