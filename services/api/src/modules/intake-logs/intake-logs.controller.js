const pool = require('../../config/db');

// 복약 체크 (버튼)
async function createIntakeLog(req, res) {
  try {
    const { schedule_id, patient_id, auth_method = 'button', photo_url } = req.body;
    if (!schedule_id || !patient_id) {
      return res.status(400).json({ success: false, message: '필수값이 누락되었습니다.' });
    }

    // 오늘 이미 체크했는지 확인
    const [existing] = await pool.query(
      `SELECT log_id FROM intake_logs
       WHERE schedule_id = ? AND patient_id = ? AND DATE(taken_at) = CURDATE()`,
      [schedule_id, patient_id]
    );
    if (existing.length > 0) {
      return res.status(409).json({ success: false, message: '오늘 이미 복약 체크했습니다.' });
    }

    const conn = await pool.getConnection();
    try {
      await conn.beginTransaction();

      // 복약 로그 저장
      const [result] = await conn.query(
        `INSERT INTO intake_logs (schedule_id, patient_id, status, auth_method, photo_url)
         VALUES (?, ?, 'taken', ?, ?)`,
        [schedule_id, patient_id, auth_method, photo_url || null]
      );

      // 포인트 적립 +100
      await conn.query(
        `INSERT INTO points_badges (user_id, points, reason) VALUES (?, 100, '복약 체크')`,
        [patient_id]
      );

      await conn.commit();
      return res.status(201).json({ success: true, log_id: result.insertId, points_earned: 100 });
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false, message: '서버 오류' });
  }
}

// 복약 기록 히스토리 조회
async function getIntakeHistory(req, res) {
  try {
    const { patient_id, limit = 30 } = req.query;
    if (!patient_id) {
      return res.status(400).json({ success: false, message: 'patient_id가 필요합니다.' });
    }

    const [rows] = await pool.query(
      `SELECT il.log_id, m.name AS medicine_name, pm.dose,
              s.time_slot, il.status, il.auth_method, il.photo_url,
              DATE_FORMAT(DATE_ADD(il.taken_at, INTERVAL 9 HOUR), '%Y-%m-%d %H:%i:%s') AS taken_at
       FROM intake_logs il
       JOIN schedules s ON il.schedule_id = s.schedule_id
       JOIN patient_medicines pm ON s.patient_medicine_id = pm.patient_medicine_id
       JOIN medicines m ON pm.medicine_id = m.medicine_id
       WHERE il.patient_id = ?
       ORDER BY il.taken_at DESC
       LIMIT ?`,
      [patient_id, Number(limit)]
    );
    return res.json({ success: true, data: rows });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false, message: '서버 오류' });
  }
}

// 복약 기록 취소 (로그 삭제 + 포인트 차감)
async function deleteIntakeLog(req, res) {
  try {
    const { log_id } = req.params;

    // 로그 존재 확인 + 소유자 확인
    const [logs] = await pool.query(
      `SELECT log_id, patient_id FROM intake_logs WHERE log_id = ?`,
      [log_id]
    );
    if (logs.length === 0) {
      return res.status(404).json({ success: false, message: '기록을 찾을 수 없습니다.' });
    }
    const { patient_id } = logs[0];

    const conn = await pool.getConnection();
    try {
      await conn.beginTransaction();

      // 복약 로그 삭제
      await conn.query(`DELETE FROM intake_logs WHERE log_id = ?`, [log_id]);

      // 포인트 차감 -100
      await conn.query(
        `INSERT INTO points_badges (user_id, points, reason) VALUES (?, -100, '복약 취소')`,
        [patient_id]
      );

      await conn.commit();
      return res.json({ success: true, message: '복약 기록이 취소되었습니다.' });
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false, message: '서버 오류' });
  }
}

// 보호자가 환자의 복약 기록 조회 (월별)
async function getPatientIntakeHistory(req, res) {
  try {
    const { patient_id, year, month } = req.query;
    if (!patient_id || !year || !month) {
      return res.status(400).json({ success: false, message: 'patient_id, year, month 필요' });
    }
    const [rows] = await pool.query(
      `SELECT il.log_id, m.name AS medicine_name, pm.dose,
              s.time_slot, il.status, il.auth_method,
              DATE_FORMAT(DATE_ADD(il.taken_at, INTERVAL 9 HOUR), '%Y-%m-%d %H:%i:%s') AS taken_at
       FROM intake_logs il
       JOIN schedules s ON il.schedule_id = s.schedule_id
       JOIN patient_medicines pm ON s.patient_medicine_id = pm.patient_medicine_id
       JOIN medicines m ON pm.medicine_id = m.medicine_id
       WHERE il.patient_id = ?
         AND YEAR(DATE_ADD(il.taken_at, INTERVAL 9 HOUR)) = ?
         AND MONTH(DATE_ADD(il.taken_at, INTERVAL 9 HOUR)) = ?
       ORDER BY il.taken_at DESC`,
      [patient_id, Number(year), Number(month)]
    );
    return res.json({ success: true, data: rows });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false, message: '서버 오류' });
  }
}

module.exports = { createIntakeLog, getIntakeHistory, deleteIntakeLog, getPatientIntakeHistory };
