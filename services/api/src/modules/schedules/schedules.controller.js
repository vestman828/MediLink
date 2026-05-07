const pool = require('../../config/db');

// 스케줄 생성
async function createSchedule(req, res) {
  try {
    const { patient_medicine_id, day_of_week, time_slot, scheduled_time } = req.body;
    if (patient_medicine_id === undefined || day_of_week === undefined || !time_slot || !scheduled_time) {
      return res.status(400).json({ success: false, message: '필수값이 누락되었습니다.' });
    }

    const [result] = await pool.query(
      `INSERT INTO schedules (patient_medicine_id, day_of_week, time_slot, scheduled_time)
       VALUES (?, ?, ?, ?)`,
      [patient_medicine_id, day_of_week, time_slot, scheduled_time]
    );
    return res.status(201).json({ success: true, schedule_id: result.insertId });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false, message: '서버 오류' });
  }
}

// 오늘 복약 스케줄 조회
async function getTodaySchedules(req, res) {
  try {
    const { patient_id, date } = req.query;
    if (!patient_id) {
      return res.status(400).json({ success: false, message: 'patient_id가 필요합니다.' });
    }

    const targetDate = date || new Date().toISOString().slice(0, 10);
    // MySQL WEEKDAY: 0=월 ~ 6=일
    const [rows] = await pool.query(
      `SELECT
         s.schedule_id,
         m.name AS medicine_name,
         m.unit,
         pm.dose,
         s.time_slot,
         s.scheduled_time,
         il.log_id,
         il.status,
         il.auth_method,
         il.photo_url,
         il.taken_at
       FROM schedules s
       JOIN patient_medicines pm ON s.patient_medicine_id = pm.patient_medicine_id
       JOIN medicines m ON pm.medicine_id = m.medicine_id
       LEFT JOIN intake_logs il
         ON il.schedule_id = s.schedule_id
         AND il.patient_id = pm.patient_id
         AND DATE(il.taken_at) = ?
       WHERE pm.patient_id = ?
         AND pm.is_active = 1
         AND s.day_of_week = WEEKDAY(?)
       ORDER BY s.scheduled_time`,
      [targetDate, patient_id, targetDate]
    );

    return res.json({ success: true, data: rows });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false, message: '서버 오류' });
  }
}

// 특정 약의 스케줄 조회 (수정용)
async function getSchedulesByMedicine(req, res) {
  try {
    const { patient_medicine_id } = req.params;
    const [rows] = await pool.query(
      `SELECT schedule_id, day_of_week, time_slot, scheduled_time
       FROM schedules WHERE patient_medicine_id = ?
       ORDER BY day_of_week, scheduled_time`,
      [patient_medicine_id]
    );
    return res.json({ success: true, data: rows });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false, message: '서버 오류' });
  }
}

// 스케줄 전체 교체 (기존 삭제 후 새로 등록)
async function replaceSchedules(req, res) {
  try {
    const { patient_medicine_id } = req.params;
    const { schedules, dose } = req.body;
    if (!schedules || !Array.isArray(schedules)) {
      return res.status(400).json({ success: false, message: 'schedules 배열이 필요합니다.' });
    }

    const conn = await pool.getConnection();
    try {
      await conn.beginTransaction();

      // 용량 업데이트
      if (dose) {
        await conn.query(
          `UPDATE patient_medicines SET dose = ? WHERE patient_medicine_id = ?`,
          [dose, patient_medicine_id]
        );
      }

      // 기존 스케줄의 복약 로그 삭제 후 스케줄 삭제
      const [existing] = await conn.query(
        `SELECT schedule_id FROM schedules WHERE patient_medicine_id = ?`,
        [patient_medicine_id]
      );
      const ids = existing.map(s => s.schedule_id);
      if (ids.length > 0) {
        await conn.query(`DELETE FROM intake_logs WHERE schedule_id IN (?)`, [ids]);
        await conn.query(`DELETE FROM schedules WHERE patient_medicine_id = ?`, [patient_medicine_id]);
      }

      // 새 스케줄 등록
      for (const s of schedules) {
        await conn.query(
          `INSERT INTO schedules (patient_medicine_id, day_of_week, time_slot, scheduled_time)
           VALUES (?, ?, ?, ?)`,
          [patient_medicine_id, s.day_of_week, s.time_slot, s.scheduled_time]
        );
      }

      await conn.commit();
      return res.json({ success: true, message: '스케줄이 수정되었습니다.' });
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

module.exports = { createSchedule, getTodaySchedules, getSchedulesByMedicine, replaceSchedules };
