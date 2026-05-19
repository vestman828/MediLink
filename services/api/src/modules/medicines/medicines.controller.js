const pool = require('../../config/db');
const https = require('https');

const DRUG_API_KEY = process.env.DRUG_API_KEY || '';
const DRUG_API_URL = 'https://apis.data.go.kr/1471000/DrbEasyDrugInfoService/getDrbEasyDrugList';
const SEARCH_LIMIT = 20;
const API_SEARCH_ROWS = 20;

function cleanText(value) {
  return String(value ?? '')
    .replace(/\s+/g, ' ')
    .trim();
}

function normalizeNameKey(name) {
  return cleanText(name).replace(/\s+/g, '').toLowerCase();
}

function hasBrokenChars(value) {
  return /�/.test(String(value ?? ''));
}

function parseDrugItems(apiData) {
  const items = apiData?.body?.items;
  if (!items) return [];
  if (Array.isArray(items)) return items;
  if (Array.isArray(items.item)) return items.item;
  if (items.item) return [items.item];
  return [];
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

function mapApiMedicine(item) {
  const name = cleanText(item?.itemName);
  if (!name || hasBrokenChars(name)) return null;

  return {
    name,
    unit: '정',
    description: cleanText(item?.efcyQesitm),
    source: 'api',
  };
}

function mergeMedicines(dbMedicines, apiMedicines) {
  const merged = [];
  const seen = new Set();

  const pushUnique = (medicine) => {
    const key = normalizeNameKey(medicine.name);
    if (!key || seen.has(key)) return;
    seen.add(key);
    merged.push(medicine);
  };

  dbMedicines.forEach(pushUnique);
  apiMedicines.forEach(pushUnique);

  return merged.slice(0, SEARCH_LIMIT);
}

function fetchDrugApi(params) {
  return new Promise((resolve, reject) => {
    const query = new URLSearchParams({
      serviceKey: DRUG_API_KEY,
      type: 'json',
      numOfRows: '10',
      pageNo: '1',
      ...params,
    }).toString();

    const url = `${DRUG_API_URL}?${query}`;
    const req = https.get(url, (res) => {
      if (res.statusCode < 200 || res.statusCode >= 300) {
        res.resume();
        reject(new Error(`Drug API request failed (${res.statusCode})`));
        return;
      }

      let data = '';
      res.on('data', (chunk) => {
        data += chunk;
      });
      res.on('end', () => {
        try {
          resolve(JSON.parse(data));
        } catch (e) {
          reject(e);
        }
      });
    });

    req.on('error', reject);
    req.setTimeout(5000, () => {
      req.destroy(new Error('Drug API request timeout'));
    });
  });
}

async function searchMedicines(req, res) {
  try {
    const q = String(req.query.q ?? '').trim();
    if (!q) return res.json({ success: true, data: [] });

    const [rows] = await pool.query(
      `SELECT medicine_id, name, unit, description
       FROM medicines
       WHERE name LIKE ?
       ORDER BY name ASC
       LIMIT ?`,
      [`%${q}%`, SEARCH_LIMIT]
    );

    const dbMedicines = rows.map(mapDbMedicine);
    let apiMedicines = [];

    if (DRUG_API_KEY) {
      try {
        const apiData = await fetchDrugApi({ itemName: q, numOfRows: String(API_SEARCH_ROWS) });
        apiMedicines = parseDrugItems(apiData).map(mapApiMedicine).filter(Boolean);
      } catch (e) {
        console.error('[drug-search-api-error]', e.message);
      }
    }

    const data = mergeMedicines(dbMedicines, apiMedicines);
    return res.json({ success: true, data });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false, message: '서버 오류' });
  }
}

async function getDrugDetail(req, res) {
  try {
    const name = String(req.query.name ?? '').trim();
    if (!name) {
      return res.status(400).json({ success: false, message: '약 이름이 필요합니다.' });
    }

    const [dbRows] = await pool.query(
      `SELECT name, unit, description
       FROM medicines
       WHERE name = ?
       LIMIT 1`,
      [name]
    );

    let detail = null;

    if (DRUG_API_KEY) {
      try {
        const apiData = await fetchDrugApi({ itemName: name, numOfRows: '1' });
        const itemList = parseDrugItems(apiData);

        if (itemList.length > 0) {
          const item = itemList[0];
          detail = {
            name: item.itemName || name,
            entpName: item.entpName || '',
            efcy: item.efcyQesitm || '',
            useMethod: item.useMethodQesitm || '',
            atpnWarn: item.atpnWarnQesitm || '',
            atpn: item.atpnQesitm || '',
            intrc: item.intrcQesitm || '',
            se: item.seQesitm || '',
            deposit: item.depositMethodQesitm || '',
          };
        }
      } catch (e) {
        console.error('[drug-detail-api-error]', e.message);
      }
    }

    if (!detail && dbRows.length > 0) {
      detail = {
        name: dbRows[0].name,
        entpName: '',
        efcy: dbRows[0].description || '',
        useMethod: '',
        atpnWarn: '',
        atpn: '',
        intrc: '',
        se: '',
        deposit: '',
      };
    }

    return res.json({ success: true, data: detail });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false, message: '서버 오류' });
  }
}

async function createMedicine(req, res) {
  try {
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
