const pool = require('../../config/db');
const { normalizePhone, isValidPhone } = require('../../utils/phone');

async function searchPatientByPhone(req, res) {
  try {
    if (req.user.role !== 'guardian') {
      return res.status(403).json({ success: false, message: '보호자만 조회할 수 있습니다.' });
    }

    const normalizedPhone = normalizePhone(req.query.phone);
    if (!isValidPhone(normalizedPhone)) {
      return res.status(400).json({ success: false, message: '전화번호 형식이 올바르지 않습니다.' });
    }

    const [rows] = await pool.query(
      `SELECT user_id, name, phone
       FROM users
       WHERE REPLACE(phone, '-', '') = ?
         AND role = 'patient'`,
      [normalizedPhone]
    );

    if (rows.length === 0) {
      return res.status(404).json({ success: false, message: '해당 전화번호의 환자를 찾을 수 없습니다.' });
    }

    return res.json({ success: true, data: rows[0] });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false, message: '서버 오류' });
  }
}

async function createFamilyMap(req, res) {
  try {
    if (req.user.role !== 'guardian') {
      return res.status(403).json({ success: false, message: '보호자만 연동할 수 있습니다.' });
    }

    const guardianId = req.user.user_id;
    const { patient_id } = req.body;

    if (!patient_id) {
      return res.status(400).json({ success: false, message: '필수값이 누락되었습니다.' });
    }

    const [existing] = await pool.query(
      'SELECT map_id FROM family_map WHERE guardian_id = ? AND patient_id = ?',
      [guardianId, patient_id]
    );

    if (existing.length > 0) {
      return res.status(409).json({ success: false, message: '이미 연동된 관계입니다.' });
    }

    const [result] = await pool.query(
      'INSERT INTO family_map (guardian_id, patient_id) VALUES (?, ?)',
      [guardianId, patient_id]
    );

    return res.status(201).json({ success: true, map_id: result.insertId });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false, message: '서버 오류' });
  }
}

async function getPatientsByGuardian(req, res) {
  try {
    const guardianId = Number(req.params.guardian_id);
    if (!guardianId) {
      return res.status(400).json({ success: false, message: 'guardian_id가 필요합니다.' });
    }

    if (req.user.role !== 'guardian' || req.user.user_id !== guardianId) {
      return res.status(403).json({ success: false, message: '본인 계정으로만 조회할 수 있습니다.' });
    }

    const [rows] = await pool.query(
      `SELECT u.user_id AS patient_id, u.name, u.phone, fm.mapped_at
       FROM family_map fm
       JOIN users u ON fm.patient_id = u.user_id
       WHERE fm.guardian_id = ?`,
      [guardianId]
    );

    return res.json({ success: true, data: rows });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false, message: '서버 오류' });
  }
}

async function deleteFamilyMap(req, res) {
  try {
    if (req.user.role !== 'guardian') {
      return res.status(403).json({ success: false, message: '보호자만 연동을 해제할 수 있습니다.' });
    }

    const guardianId = req.user.user_id;
    const { patient_id } = req.params;

    if (!patient_id) {
      return res.status(400).json({ success: false, message: 'patient_id가 필요합니다.' });
    }

    const [result] = await pool.query(
      'DELETE FROM family_map WHERE guardian_id = ? AND patient_id = ?',
      [guardianId, patient_id]
    );

    if (result.affectedRows === 0) {
      return res.status(404).json({ success: false, message: '연동 정보를 찾을 수 없습니다.' });
    }

    return res.json({ success: true, message: '연동이 해제되었습니다.' });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false, message: '서버 오류' });
  }
}

module.exports = { searchPatientByPhone, createFamilyMap, getPatientsByGuardian, deleteFamilyMap };
