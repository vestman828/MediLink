const pool = require('../../config/db');

// 환자별 복용 약 등록
async function createPatientMedicine(req, res) {
  try {
    const { patient_id, medicine_id, dose, frequency, start_date, end_date } = req.body;
    if (!patient_id || !medicine_id || !dose || !start_date) {
      return res.status(400).json({ success: false, message: '필수값이 누락되었습니다.' });
    }

    const [result] = await pool.query(
      `INSERT INTO patient_medicines (patient_id, medicine_id, dose, frequency, start_date, end_date)
       VALUES (?, ?, ?, ?, ?, ?)`,
      [patient_id, medicine_id, dose, frequency || null, start_date, end_date || null]
    );
    return res.status(201).json({ success: true, patient_medicine_id: result.insertId });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false, message: '서버 오류' });
  }
}

// 환자의 복용 약 목록 조회
async function getPatientMedicines(req, res) {
  try {
    const { patient_id } = req.params;
    const [rows] = await pool.query(
      `SELECT pm.patient_medicine_id, m.name, m.unit, pm.dose, pm.frequency,
              pm.is_active, pm.start_date, pm.end_date
       FROM patient_medicines pm
       JOIN medicines m ON pm.medicine_id = m.medicine_id
       WHERE pm.patient_id = ?
       ORDER BY pm.is_active DESC, pm.created_at DESC`,
      [patient_id]
    );
    return res.json({ success: true, data: rows });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false, message: '서버 오류' });
  }
}

// 약 재활성화 (복용 재개)
async function reactivatePatientMedicine(req, res) {
  try {
    const { patient_medicine_id } = req.params;
    const [result] = await pool.query(
      `UPDATE patient_medicines SET is_active = 1 WHERE patient_medicine_id = ?`,
      [patient_medicine_id]
    );
    if (result.affectedRows === 0) {
      return res.status(404).json({ success: false, message: '약을 찾을 수 없습니다.' });
    }
    return res.json({ success: true, message: '복용이 재개되었습니다.' });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false, message: '서버 오류' });
  }
}

// 약 비활성화 (복용 중단)
async function deactivatePatientMedicine(req, res) {
  try {
    const { patient_medicine_id } = req.params;
    const [result] = await pool.query(
      `UPDATE patient_medicines SET is_active = 0 WHERE patient_medicine_id = ?`,
      [patient_medicine_id]
    );
    if (result.affectedRows === 0) {
      return res.status(404).json({ success: false, message: '약을 찾을 수 없습니다.' });
    }
    return res.json({ success: true, message: '약 복용이 중단되었습니다.' });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false, message: '서버 오류' });
  }
}

// 약 완전 삭제 (스케줄 + 로그 포함)
async function deletePatientMedicine(req, res) {
  try {
    const { patient_medicine_id } = req.params;
    const conn = await pool.getConnection();
    try {
      await conn.beginTransaction();
      const [schedules] = await conn.query(
        `SELECT schedule_id FROM schedules WHERE patient_medicine_id = ?`,
        [patient_medicine_id]
      );
      const scheduleIds = schedules.map(s => s.schedule_id);
      if (scheduleIds.length > 0) {
        await conn.query(`DELETE FROM intake_logs WHERE schedule_id IN (?)`, [scheduleIds]);
        await conn.query(`DELETE FROM schedules WHERE patient_medicine_id = ?`, [patient_medicine_id]);
      }
      await conn.query(`DELETE FROM patient_medicines WHERE patient_medicine_id = ?`, [patient_medicine_id]);
      await conn.commit();
      return res.json({ success: true, message: '약이 삭제되었습니다.' });
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

module.exports = { createPatientMedicine, getPatientMedicines, reactivatePatientMedicine, deactivatePatientMedicine, deletePatientMedicine };
