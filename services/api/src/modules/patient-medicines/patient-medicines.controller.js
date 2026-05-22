const pool = require('../../config/db');

async function ensureGuardianMappedPatient(guardianId, patientId) {
  const [rows] = await pool.query(
    `SELECT map_id
     FROM family_map
     WHERE guardian_id = ? AND patient_id = ?
     LIMIT 1`,
    [guardianId, patientId]
  );

  return rows.length > 0;
}

async function findPatientIdByMedicine(patientMedicineId) {
  const [rows] = await pool.query(
    `SELECT patient_id
     FROM patient_medicines
     WHERE patient_medicine_id = ?
     LIMIT 1`,
    [patientMedicineId]
  );

  return rows[0]?.patient_id ?? null;
}

async function ensureUserCanManagePatient(reqUser, patientId) {
  if (reqUser.role === 'patient') {
    return reqUser.user_id === patientId;
  }
  if (reqUser.role === 'guardian') {
    return ensureGuardianMappedPatient(reqUser.user_id, patientId);
  }
  return false;
}

async function ensureUserCanManagePatientMedicine(reqUser, patientMedicineId) {
  const patientId = await findPatientIdByMedicine(patientMedicineId);
  if (!patientId) {
    return { ok: false, status: 404, message: '약 정보를 찾을 수 없습니다.' };
  }

  const canManage = await ensureUserCanManagePatient(reqUser, patientId);
  if (!canManage) {
    return {
      ok: false,
      status: 403,
      message:
        reqUser.role === 'patient'
          ? '본인 복약 정보만 관리할 수 있습니다.'
          : '연동된 환자 정보만 관리할 수 있습니다.',
    };
  }

  return { ok: true, patientId };
}

async function createPatientMedicine(req, res) {
  try {
    if (req.user.role !== 'guardian') {
      return res
        .status(403)
        .json({ success: false, message: '보호자만 복약 정보를 설정할 수 있습니다.' });
    }

    const { patient_id, medicine_id, dose, frequency, start_date, end_date } =
      req.body;
    const patientId = Number(patient_id);
    const medicineId = Number(medicine_id);

    if (!patientId || !medicineId || !dose || !start_date) {
      return res
        .status(400)
        .json({ success: false, message: '필수값이 누락되었습니다.' });
    }

    const canManage = await ensureUserCanManagePatient(req.user, patientId);
    if (!canManage) {
      return res.status(403).json({
        success: false,
        message: '연동된 환자 정보만 설정할 수 있습니다.',
      });
    }

    const [result] = await pool.query(
      `INSERT INTO patient_medicines (patient_id, medicine_id, dose, frequency, start_date, end_date)
       VALUES (?, ?, ?, ?, ?, ?)`,
      [patientId, medicineId, dose, frequency || null, start_date, end_date || null]
    );

    return res
      .status(201)
      .json({ success: true, patient_medicine_id: result.insertId });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false, message: '서버 오류' });
  }
}

async function getPatientMedicines(req, res) {
  try {
    const patientId = Number(req.params.patient_id);
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

    const canManage = await ensureUserCanManagePatient(req.user, patientId);
    if (!canManage) {
      return res.status(403).json({
        success: false,
        message:
          req.user.role === 'patient'
            ? '본인 복약 정보만 조회할 수 있습니다.'
            : '연동된 환자 정보만 조회할 수 있습니다.',
      });
    }

    const [rows] = await pool.query(
      `SELECT pm.patient_medicine_id, m.name, m.unit, pm.dose, pm.frequency,
              pm.is_active, pm.start_date, pm.end_date
       FROM patient_medicines pm
       JOIN medicines m ON pm.medicine_id = m.medicine_id
       WHERE pm.patient_id = ?
       ORDER BY pm.is_active DESC, pm.created_at DESC`,
      [patientId]
    );

    return res.json({ success: true, data: rows });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false, message: '서버 오류' });
  }
}

async function reactivatePatientMedicine(req, res) {
  try {
    if (req.user.role !== 'guardian') {
      return res
        .status(403)
        .json({ success: false, message: '보호자만 복약 정보를 설정할 수 있습니다.' });
    }

    const patientMedicineId = Number(req.params.patient_medicine_id);
    const access = await ensureUserCanManagePatientMedicine(
      req.user,
      patientMedicineId
    );
    if (!access.ok) {
      return res
        .status(access.status)
        .json({ success: false, message: access.message });
    }

    await pool.query(
      `UPDATE patient_medicines SET is_active = 1 WHERE patient_medicine_id = ?`,
      [patientMedicineId]
    );
    return res.json({ success: true, message: '복용을 재개했습니다.' });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false, message: '서버 오류' });
  }
}

async function deactivatePatientMedicine(req, res) {
  try {
    if (req.user.role !== 'guardian') {
      return res
        .status(403)
        .json({ success: false, message: '보호자만 복약 정보를 설정할 수 있습니다.' });
    }

    const patientMedicineId = Number(req.params.patient_medicine_id);
    const access = await ensureUserCanManagePatientMedicine(
      req.user,
      patientMedicineId
    );
    if (!access.ok) {
      return res
        .status(access.status)
        .json({ success: false, message: access.message });
    }

    await pool.query(
      `UPDATE patient_medicines SET is_active = 0 WHERE patient_medicine_id = ?`,
      [patientMedicineId]
    );
    return res.json({ success: true, message: '복용을 중단했습니다.' });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false, message: '서버 오류' });
  }
}

async function deletePatientMedicine(req, res) {
  try {
    if (req.user.role !== 'guardian') {
      return res
        .status(403)
        .json({ success: false, message: '보호자만 복약 정보를 설정할 수 있습니다.' });
    }

    const patientMedicineId = Number(req.params.patient_medicine_id);
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

      const [schedules] = await conn.query(
        `SELECT schedule_id FROM schedules WHERE patient_medicine_id = ?`,
        [patientMedicineId]
      );
      const scheduleIds = schedules.map((s) => s.schedule_id);

      if (scheduleIds.length > 0) {
        await conn.query(`DELETE FROM intake_logs WHERE schedule_id IN (?)`, [
          scheduleIds,
        ]);
        await conn.query(
          `DELETE FROM schedules WHERE patient_medicine_id = ?`,
          [patientMedicineId]
        );
      }

      await conn.query(
        `DELETE FROM patient_medicines WHERE patient_medicine_id = ?`,
        [patientMedicineId]
      );
      await conn.commit();

      return res.json({ success: true, message: '약을 삭제했습니다.' });
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

// 약 이름 변경: medicine_id를 새 약으로 교체 (없으면 새로 생성)
async function renameMedicine(req, res) {
  try {
    if (req.user.role !== 'guardian') {
      return res
        .status(403)
        .json({ success: false, message: '보호자만 약 이름을 변경할 수 있습니다.' });
    }

    const patientMedicineId = Number(req.params.patient_medicine_id);
    const { medicine_name } = req.body;

    if (!medicine_name || !medicine_name.trim()) {
      return res.status(400).json({ success: false, message: '약 이름이 필요합니다.' });
    }

    const access = await ensureUserCanManagePatientMedicine(req.user, patientMedicineId);
    if (!access.ok) {
      return res.status(access.status).json({ success: false, message: access.message });
    }

    const name = medicine_name.trim();

    // 이미 동일한 이름의 약이 있으면 재사용, 없으면 새로 생성
    const [existing] = await pool.query(
      `SELECT medicine_id FROM medicines WHERE name = ? LIMIT 1`,
      [name]
    );

    let medicineId;
    if (existing.length > 0) {
      medicineId = existing[0].medicine_id;
    } else {
      const [result] = await pool.query(
        `INSERT INTO medicines (name, unit) VALUES (?, '정')`,
        [name]
      );
      medicineId = result.insertId;
    }

    await pool.query(
      `UPDATE patient_medicines SET medicine_id = ? WHERE patient_medicine_id = ?`,
      [medicineId, patientMedicineId]
    );

    return res.json({ success: true, message: '약 이름이 변경되었습니다.', medicine_id: medicineId });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false, message: '서버 오류' });
  }
}

module.exports = {
  createPatientMedicine,
  getPatientMedicines,
  reactivatePatientMedicine,
  deactivatePatientMedicine,
  deletePatientMedicine,
  renameMedicine,
};
