const pool = require('../../config/db');

function getKstDateString(base = new Date()) {
  return new Date(base.getTime() + 9 * 60 * 60 * 1000).toISOString().slice(0, 10);
}

function getKstWeekday(base = new Date()) {
  const kst = new Date(base.getTime() + 9 * 60 * 60 * 1000);
  const day = kst.getUTCDay(); // 0=Sun..6=Sat
  return (day + 6) % 7; // MySQL WEEKDAY: 0=Mon..6=Sun
}

function getKstNowMinutes(base = new Date()) {
  const kst = new Date(base.getTime() + 9 * 60 * 60 * 1000);
  return kst.getUTCHours() * 60 + kst.getUTCMinutes();
}

function parseTimeToMinutes(timeString) {
  const parts = String(timeString || '00:00:00').split(':');
  const hour = Number(parts[0] || 0);
  const minute = Number(parts[1] || 0);
  return hour * 60 + minute;
}

async function createIntakeLog(req, res) {
  try {
    const { schedule_id, patient_id, auth_method = 'button', photo_url } = req.body;

    if (!schedule_id || !patient_id) {
      return res.status(400).json({ success: false, message: '필수값이 누락되었습니다.' });
    }

    if (req.user.role !== 'patient' || req.user.user_id !== Number(patient_id)) {
      return res.status(403).json({ success: false, message: '본인 복약만 체크할 수 있습니다.' });
    }

    const [scheduleRows] = await pool.query(
      `SELECT s.schedule_id, s.day_of_week, s.time_slot, s.scheduled_time, pm.patient_id
       FROM schedules s
       JOIN patient_medicines pm ON s.patient_medicine_id = pm.patient_medicine_id
       WHERE s.schedule_id = ?
         AND pm.patient_id = ?
         AND pm.is_active = 1
       LIMIT 1`,
      [schedule_id, patient_id]
    );

    if (scheduleRows.length === 0) {
      return res.status(404).json({ success: false, message: '유효한 복약 스케줄을 찾을 수 없습니다.' });
    }

    const schedule = scheduleRows[0];
    const kstWeekday = getKstWeekday();
    if (Number(schedule.day_of_week) !== kstWeekday) {
      return res.status(400).json({ success: false, message: '오늘 복약 스케줄만 체크할 수 있습니다.' });
    }

    const nowMinutes = getKstNowMinutes();
    const scheduledMinutes = parseTimeToMinutes(schedule.scheduled_time);
    if (nowMinutes < scheduledMinutes) {
      return res.status(400).json({ success: false, message: '복약 예정 시간 이전에는 체크할 수 없습니다.' });
    }

    const kstDate = getKstDateString();
    const [existing] = await pool.query(
      `SELECT log_id
       FROM intake_logs
       WHERE schedule_id = ?
         AND patient_id = ?
         AND DATE(DATE_ADD(taken_at, INTERVAL 9 HOUR)) = ?`,
      [schedule_id, patient_id, kstDate]
    );

    if (existing.length > 0) {
      return res.status(409).json({ success: false, message: '오늘 이미 복약 체크했습니다.' });
    }

    const conn = await pool.getConnection();
    try {
      await conn.beginTransaction();

      const [result] = await conn.query(
        `INSERT INTO intake_logs (schedule_id, patient_id, status, auth_method, photo_url)
         VALUES (?, ?, 'taken', ?, ?)`,
        [schedule_id, patient_id, auth_method, photo_url || null]
      );

      await conn.query(
        `INSERT INTO points_badges (user_id, points, reason)
         VALUES (?, 100, '복약 체크')`,
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

async function getIntakeHistory(req, res) {
  try {
    const { patient_id, limit = 30 } = req.query;
    if (!patient_id) {
      return res.status(400).json({ success: false, message: 'patient_id가 필요합니다.' });
    }

    if (req.user.role !== 'patient' || req.user.user_id !== Number(patient_id)) {
      return res.status(403).json({ success: false, message: '본인 기록만 조회할 수 있습니다.' });
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

async function deleteIntakeLog(req, res) {
  try {
    const { log_id } = req.params;

    const [logs] = await pool.query(
      `SELECT log_id, patient_id
       FROM intake_logs
       WHERE log_id = ?`,
      [log_id]
    );

    if (logs.length === 0) {
      return res.status(404).json({ success: false, message: '기록을 찾을 수 없습니다.' });
    }

    const { patient_id } = logs[0];
    if (req.user.role !== 'patient' || req.user.user_id !== Number(patient_id)) {
      return res.status(403).json({ success: false, message: '본인 기록만 취소할 수 있습니다.' });
    }

    const conn = await pool.getConnection();
    try {
      await conn.beginTransaction();

      await conn.query(`DELETE FROM intake_logs WHERE log_id = ?`, [log_id]);
      await conn.query(
        `INSERT INTO points_badges (user_id, points, reason)
         VALUES (?, -100, '복약 취소')`,
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

async function getPatientIntakeHistory(req, res) {
  try {
    const { patient_id, year, month } = req.query;
    if (!patient_id || !year || !month) {
      return res.status(400).json({ success: false, message: 'patient_id, year, month 필요' });
    }

    if (req.user.role !== 'guardian') {
      return res.status(403).json({ success: false, message: '보호자만 조회할 수 있습니다.' });
    }

    const [mapping] = await pool.query(
      `SELECT map_id
       FROM family_map
       WHERE guardian_id = ? AND patient_id = ?
       LIMIT 1`,
      [req.user.user_id, patient_id]
    );
    if (mapping.length === 0) {
      return res.status(403).json({ success: false, message: '연동된 환자만 조회할 수 있습니다.' });
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
