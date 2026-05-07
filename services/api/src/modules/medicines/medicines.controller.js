const pool = require('../../config/db');

// 약물 검색 (자동완성)
async function searchMedicines(req, res) {
  try {
    const { q = '' } = req.query;
    const [rows] = await pool.query(
      'SELECT medicine_id, name, unit, description FROM medicines WHERE name LIKE ? LIMIT 20',
      [`%${q}%`]
    );
    return res.json({ success: true, data: rows });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false, message: '서버 오류' });
  }
}

// 약물 등록
async function createMedicine(req, res) {
  try {
    const { name, unit = 'mg', description } = req.body;
    if (!name) return res.status(400).json({ success: false, message: '약 이름은 필수입니다.' });

    const [result] = await pool.query(
      'INSERT INTO medicines (name, unit, description) VALUES (?, ?, ?)',
      [name, unit, description || null]
    );
    return res.status(201).json({ success: true, medicine_id: result.insertId });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false, message: '서버 오류' });
  }
}

module.exports = { searchMedicines, createMedicine };
