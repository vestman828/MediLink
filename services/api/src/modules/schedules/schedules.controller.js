const pool = require('../../config/db');

function getKstDateString(base = new Date()) {
  return new Date(base.getTime() + 9 * 60 * 60 * 1000)
    .toISOString()
    .slice(0, 10);
}

function validateSchedules(schedules = []) {
  const keySet = new Set();

  for (const s of schedules) {
    if (
      s?.day_of_week === undefined ||
      s?.day_of_week === null ||
      typeof s?.time_slot !== 'string' ||
      typeof s?.scheduled_time !== 'string'
    ) {
      return '잘못된 스케줄 항목이 포함되어 있습니다.';
    }

    const key = `${s.day_of_week}_${s.scheduled_time}`;
    if (keySet.has(key)) {
      return '같은 요일에 복약 시간이 겹치도록 설정할 수 없습니다.';
    }
    keySet.add(key);
  }

  return null;
}

async function ensureGuardianMappedPatient(guardianId, patientId) {
  const [mapping] = await pool.query(
    `SELECT map_id
     FROM family_map
     WHERE guardian_id = ? AND patient_id = ?
     LIMIT 1`,
    [guardianId, patientId]
  );
  return mapping.length > 0;
}

async function ensureUserCanAccessPatient(reqUser, patientId) {
  if (reqUser.role === 'patient') {
    return reqUser.user_id === Number(patientId);
  }
  if (reqUser.role === 'guardian') {
    return ensureGuardianMappedPatient(reqUser.user_id, Number(patientId));
  }
  return false;
}

async function ensureUserCanManagePatientMedicine(reqUser, patientMedicineId) {
  const [rows] = await pool.query(
    `SELECT pm.patient_id
     FROM patient_medicines pm
     WHERE pm.patient_medicine_id = ?
     LIMIT 1`,
    [patientMedicineId]
  );

  if (rows.length === 0) {
    return { ok: false, status: 404, message: '복용약 정보를 찾을 수 없습니다.' };
  }

  const patientId = Number(rows[0].patient_id);
  const canManage = await ensureUserCanAccessPatient(reqUser, patientId);
  if (!canManage) {
    return {
      ok: false,
      status: 403,
      message:
        reqUser.role === 'patient'
          ? '본인 복약 시간만 설정할 수 있습니다.'
          : '연동된 환자의 복약 시간만 설정할 수 있습니다.',
    };
  }

  return { ok: true, patientId };
}

async function createSchedule(req, res) {
  try {
    if (!['guardian', 'patient'].includes(req.user.role)) {
      return res
        .status(403)
        .json({ success: false, message: '복약 시간을 설정할 권한이 없습니다.' });
    }

    const { patient_medicine_id, day_of_week, time_slot, scheduled_time } =
      req.body;
    if (
      patient_medicine_id === undefined ||
      day_of_week === undefined ||
      !time_slot ||
      !scheduled_time
    ) {
      return res
        .status(400)
        .json({ success: false, message: '필수값이 누락되었습니다.' });
    }

    const access = await ensureUserCanManagePatientMedicine(
      req.user,
      Number(patient_medicine_id)
    );
    if (!access.ok) {
      return res
        .status(access.status)
        .json({ success: false, message: access.message });
    }

    const [overlap] = await pool.query(
      `SELECT s.schedule_id
       FROM schedules s
       WHERE s.patient_medicine_id = ?
         AND s.day_of_week = ?
         AND s.scheduled_time = ?
       LIMIT 1`,
      [patient_medicine_id, day_of_week, scheduled_time]
    );

    if (overlap.length > 0) {
      return res
        .status(409)
        .json({ success: false, message: '같은 시간으로 중복 설정할 수 없습니다.' });
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

async function getTodaySchedules(req, res) {
  try {
    const patientId = Number(req.query.patient_id);
    if (!patientId) {
      return res
        .status(400)
        .json({ success: false, message: 'patient_id가 필요합니다.' });
    }

    if (!['guardian', 'patient'].includes(req.user.role)) {
      return res
        .status(403)
        .json({ success: false, message: '복약 정보를 조회할 권한이 없습니다.' });
    }

    const canAccess = await ensureUserCanAccessPatient(req.user, patientId);
    if (!canAccess) {
      return res.status(403).json({
        success: false,
        message:
          req.user.role === 'patient'
            ? '본인 복약 정보만 조회할 수 있습니다.'
            : '연동된 환자 정보만 조회할 수 있습니다.',
      });
    }

    const targetDate = req.query.date || getKstDateString();

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
         AND DATE(DATE_ADD(il.taken_at, INTERVAL 9 HOUR)) = ?
       WHERE pm.patient_id = ?
         AND pm.is_active = 1
         AND s.day_of_week = WEEKDAY(?)
       ORDER BY s.scheduled_time`,
      [targetDate, patientId, targetDate]
    );

    return res.json({ success: true, data: rows });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false, message: '서버 오류' });
  }
}

async function getSchedulesByMedicine(req, res) {
  try {
    const patientMedicineId = Number(req.params.patient_medicine_id);
    if (!patientMedicineId) {
      return res.status(400).json({
        success: false,
        message: 'patient_medicine_id가 필요합니다.',
      });
    }

    const access = await ensureUserCanManagePatientMedicine(
      req.user,
      patientMedicineId
    );
    if (!access.ok) {
      return res
        .status(access.status)
        .json({ success: false, message: access.message });
    }

    const [rows] = await pool.query(
      `SELECT schedule_id, day_of_week, time_slot, scheduled_time
       FROM schedules
       WHERE patient_medicine_id = ?
       ORDER BY day_of_week, scheduled_time`,
      [patientMedicineId]
    );

    return res.json({ success: true, data: rows });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false, message: '서버 오류' });
  }
}

async function replaceSchedules(req, res) {
  try {
    if (!['guardian', 'patient'].includes(req.user.role)) {
      return res
        .status(403)
        .json({ success: false, message: '복약 시간을 설정할 권한이 없습니다.' });
    }

    const patientMedicineId = Number(req.params.patient_medicine_id);
    const { schedules, dose } = req.body;

    if (!Array.isArray(schedules)) {
      return res
        .status(400)
        .json({ success: false, message: 'schedules 배열이 필요합니다.' });
    }

    const invalidMessage = validateSchedules(schedules);
    if (invalidMessage) {
      return res.status(400).json({ success: false, message: invalidMessage });
    }

    const access = await ensureUserCanManagePatientMedicine(
      req.user,
      patientMedicineId
    );
    if (!access.ok) {
      return res
        .status(access.status)
        .json({ success: false, message: access.message });
    }

    const conn = await pool.getConnection();
    try {
      await conn.beginTransaction();

      if (dose) {
        await conn.query(
          `UPDATE patient_medicines
           SET dose = ?
           WHERE patient_medicine_id = ?`,
          [dose, patientMedicineId]
        );
      }

      const [existing] = await conn.query(
        `SELECT schedule_id
         FROM schedules
         WHERE patient_medicine_id = ?`,
        [patientMedicineId]
      );
      const ids = existing.map((s) => s.schedule_id);
      if (ids.length > 0) {
        await conn.query(`DELETE FROM intake_logs WHERE schedule_id IN (?)`, [
          ids,
        ]);
        await conn.query(
          `DELETE FROM schedules WHERE patient_medicine_id = ?`,
          [patientMedicineId]
        );
      }

      for (const s of schedules) {
        await conn.query(
          `INSERT INTO schedules (patient_medicine_id, day_of_week, time_slot, scheduled_time)
           VALUES (?, ?, ?, ?)`,
          [patientMedicineId, s.day_of_week, s.time_slot, s.scheduled_time]
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

module.exports = {
  createSchedule,
  getTodaySchedules,
  getSchedulesByMedicine,
  replaceSchedules,
};

