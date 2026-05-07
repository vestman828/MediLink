const pool = require('../../config/db');

// 보호자 대시보드
async function getDashboard(req, res) {
  try {
    const { guardian_id } = req.query;
    if (!guardian_id) {
      return res.status(400).json({ success: false, message: 'guardian_id가 필요합니다.' });
    }

    // 보호자가 관리하는 환자 목록
    const [patients] = await pool.query(
      `SELECT u.user_id, u.name
       FROM family_map fm
       JOIN users u ON fm.patient_id = u.user_id
       WHERE fm.guardian_id = ?`,
      [guardian_id]
    );

    const result = [];
    for (const patient of patients) {
      // 오늘 복약 현황
      const [schedules] = await pool.query(
        `SELECT
           s.schedule_id,
           m.name AS medicine_name,
           pm.dose,
           s.time_slot,
           s.scheduled_time,
           CASE
             WHEN il.log_id IS NOT NULL THEN 'taken'
             WHEN s.scheduled_time < TIME(DATE_SUB(NOW(), INTERVAL 2 HOUR)) THEN 'missed'
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
           AND DATE(il.taken_at) = CURDATE()
         WHERE pm.patient_id = ?
           AND pm.is_active = 1
           AND s.day_of_week = WEEKDAY(NOW())
         ORDER BY s.scheduled_time`,
        [patient.user_id]
      );

      // 최근 7일 이행률
      const [adherence] = await pool.query(
        `SELECT
           COUNT(DISTINCT DATE(il.taken_at)) AS taken_days,
           7 AS total_days
         FROM intake_logs il
         WHERE il.patient_id = ?
           AND il.taken_at >= DATE_SUB(CURDATE(), INTERVAL 7 DAY)`,
        [patient.user_id]
      );

      const takenDays = adherence[0]?.taken_days || 0;
      const adherenceRate = Math.round((takenDays / 7) * 100);

      result.push({
        patient_id: patient.user_id,
        patient_name: patient.name,
        today_schedules: schedules,
        adherence_rate_7days: adherenceRate,
        missed_count: schedules.filter(s => s.status === 'missed').length,
      });
    }

    return res.json({ success: true, data: result });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false, message: '서버 오류' });
  }
}

module.exports = { getDashboard };
