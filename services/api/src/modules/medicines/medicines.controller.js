const pool = require('../../config/db');

const SEARCH_LIMIT = 20;

function cleanText(value) {
  return String(value ?? '')
    .replace(/\s+/g, ' ')
    .trim();
}

function valueOrDash(value) {
  const text = cleanText(value);
  return text || '-';
}

function mapDbMedicine(row) {
  return {
    medicine_id: row.medicine_id,
    name: cleanText(row.name),
    unit: cleanText(row.unit || '정') || '정',
    description: cleanText(row.description),
    source: 'db',
  };
}

async function searchMedicines(req, res) {
  try {
    const q = cleanText(req.query.q);
    if (!q) return res.json({ success: true, data: [] });

    const [rows] = await pool.query(
      `SELECT medicine_id, name, unit, description
       FROM medicines
       WHERE name LIKE ?
       ORDER BY name ASC
       LIMIT ?`,
      [`%${q}%`, SEARCH_LIMIT]
    );

    return res.json({ success: true, data: rows.map(mapDbMedicine) });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false, message: '서버 오류' });
  }
}

async function getDrugDetail(req, res) {
  try {
    const name = cleanText(req.query.name);
    if (!name) {
      return res.status(400).json({ success: false, message: '약 이름이 필요합니다.' });
    }

    const [rows] = await pool.query(
      `SELECT name, description
       FROM medicines
       WHERE name = ?
       LIMIT 1`,
      [name]
    );

    const dbRow = rows[0];
    const detail = {
      name: dbRow ? cleanText(dbRow.name) : name,
      entpName: '-',
      efcy: valueOrDash(dbRow?.description),
      useMethod: '-',
      atpnWarn: '-',
      atpn: '-',
      intrc: '-',
      se: '-',
      deposit: '-',
    };

    return res.json({ success: true, data: detail });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false, message: '서버 오류' });
  }
}

async function createMedicine(req, res) {
  try {
    if (req.user.role !== 'guardian') {
      return res
        .status(403)
        .json({ success: false, message: '보호자만 복약 약목록을 설정할 수 있습니다.' });
    }

    const name = String(req.body.name ?? '').trim();
    const unit = String(req.body.unit ?? '정').trim() || '정';
    const description = req.body.description ?? null;

    if (!name) {
      return res.status(400).json({ success: false, message: '약 이름은 필수입니다.' });
    }

    const [existing] = await pool.query(
      `SELECT medicine_id
       FROM medicines
       WHERE name = ?
       LIMIT 1`,
      [name]
    );

    if (existing.length > 0) {
      return res.status(200).json({ success: true, medicine_id: existing[0].medicine_id, reused: true });
    }

    const [result] = await pool.query(
      `INSERT INTO medicines (name, unit, description)
       VALUES (?, ?, ?)`,
      [name, unit, description]
    );

    return res.status(201).json({ success: true, medicine_id: result.insertId });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false, message: '서버 오류' });
  }
}

module.exports = { searchMedicines, createMedicine, getDrugDetail };
