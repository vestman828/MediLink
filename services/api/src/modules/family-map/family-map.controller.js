const pool = require('../../config/db');

// 전화번호로 환자 검색
async function searchPatientByPhone(req, res) {
  try {
    const { phone } = req.query;
    if (!phone) return res.status(400).json({ success: false, message: '전화번호를 입력해주세요.' });

    const [rows] = await pool.query(
      `SELECT user_id, name, phone FROM users WHERE phone = ? AND role = 'patient'`,
      [phone]
    );
    if (rows.length === 0) {
      return res.status(404).json({ success: false, message: '해당 전화번호의 환자를 찾을 수 없어요.' });
    }
    return res.json({ success: true, data: rows[0] });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false, message: '서버 오류' });
  }
}

// 가족 연동
async function createFamilyMap(req, res) {
  try {
    const { guardian_id, patient_id } = req.body;
    if (!guardian_id || !patient_id) {
      return res.status(400).json({ success: false, message: '필수값이 누락되었습니다.' });
    }

    const [existing] = await pool.query(
      'SELECT map_id FROM family_map WHERE guardian_id = ? AND patient_id = ?',
      [guardian_id, patient_id]
    );
    if (existing.length > 0) {
      return res.status(409).json({ success: false, message: '이미 연동된 관계입니다.' });
    }

    const [result] = await pool.query(
      'INSERT INTO family_map (guardian_id, patient_id) VALUES (?, ?)',
      [guardian_id, patient_id]
    );
    return res.status(201).json({ success: true, map_id: result.insertId });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false, message: '서버 오류' });
  }
}

// 보호자의 환자 목록 조회
async function getPatientsByGuardian(req, res) {
  try {
    const { guardian_id } = req.params;
    const [rows] = await pool.query(
      `SELECT u.user_id, u.name, u.phone, fm.mapped_at
       FROM family_map fm
       JOIN users u ON fm.patient_id = u.user_id
       WHERE fm.guardian_id = ?`,
      [guardian_id]
    );
    return res.json({ success: true, data: rows });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false, message: '서버 오류' });
  }
}

module.exports = { searchPatientByPhone, createFamilyMap, getPatientsByGuardian };
