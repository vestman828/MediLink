const pool = require('../../config/db');

// 보호자의 미확인 알림 조회
async function getAlerts(req, res) {
  try {
    const guardianId = req.user.user_id;
    const [rows] = await pool.query(
      `SELECT alert_id, patient_id, patient_name, time_slot,
              DATE_FORMAT(alert_date, '%Y-%m-%d') AS alert_date,
              is_read, created_at
       FROM guardian_alerts
       WHERE guardian_id = ? AND is_read = 0
         AND alert_date = CURDATE()
       ORDER BY created_at DESC`,
      [guardianId]
    );
    return res.json({ success: true, data: rows });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false, message: '서버 오류' });
  }
}

// 알림 읽음 처리
async function markAllRead(req, res) {
  try {
    const guardianId = req.user.user_id;
    await pool.query(
      `UPDATE guardian_alerts SET is_read = 1 WHERE guardian_id = ?`,
      [guardianId]
    );
    return res.json({ success: true });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false, message: '서버 오류' });
  }
}

module.exports = { getAlerts, markAllRead };
