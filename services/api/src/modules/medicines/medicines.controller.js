const pool = require('../../config/db');
const https = require('https');
const http = require('http');

const DRUG_API_KEY = process.env.DRUG_API_KEY || '';
const DRUG_API_URL = 'http://apis.data.go.kr/1471000/DrbEasyDrugInfoService/getDrbEasyDrugList';

// e약은요 API 호출 헬퍼
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
    http.get(url, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try { resolve(JSON.parse(data)); }
        catch (e) { reject(e); }
      });
    }).on('error', reject);
  });
}

// 약물 검색 - DB 우선, 없으면 e약은요 API 병행
async function searchMedicines(req, res) {
  try {
    const { q = '' } = req.query;
    if (!q.trim()) return res.json({ success: true, data: [] });

    // 1. 로컬 DB 검색
    const [dbRows] = await pool.query(
      'SELECT medicine_id, name, unit, description FROM medicines WHERE name LIKE ? LIMIT 10',
      [`%${q}%`]
    );

    // 2. e약은요 API 검색 (API 키 있을 때만)
    let apiResults = [];
    if (DRUG_API_KEY) {
      try {
        const apiData = await fetchDrugApi({ itemName: q });
        const items = apiData?.body?.items || [];
        const itemList = Array.isArray(items) ? items : (items.item ? [items.item].flat() : []);
        apiResults = itemList.map(item => ({
          medicine_id: null,
          name: item.itemName || '',
          unit: '정',
          description: item.efcyQesitm || '',
          // 상세 정보
          efcy: item.efcyQesitm || '',
          useMethod: item.useMethodQesitm || '',
          atpnWarn: item.atpnWarnQesitm || '',
          atpn: item.atpnQesitm || '',
          intrc: item.intrcQesitm || '',
          se: item.seQesitm || '',
          deposit: item.depositMethodQesitm || '',
          entpName: item.entpName || '',
          source: 'api',
        }));
      } catch (e) {
        console.error('[e약은요 API 오류]', e.message);
      }
    }

    // DB 결과에 source 표시
    const dbResults = dbRows.map(r => ({ ...r, source: 'db' }));

    // DB에 없는 API 결과만 추가 (이름 중복 제거)
    const dbNames = new Set(dbResults.map(r => r.name));
    const merged = [
      ...dbResults,
      ...apiResults.filter(r => !dbNames.has(r.name)),
    ];

    return res.json({ success: true, data: merged });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false, message: '서버 오류' });
  }
}

// 약 상세 정보 조회 (e약은요 API)
async function getDrugDetail(req, res) {
  try {
    const { name } = req.query;
    if (!name) return res.status(400).json({ success: false, message: '약 이름 필요' });

    // DB에서 먼저 찾기
    const [dbRows] = await pool.query(
      'SELECT * FROM medicines WHERE name = ? LIMIT 1',
      [name]
    );

    // e약은요 API에서 상세 정보 가져오기
    let detail = null;
    if (DRUG_API_KEY) {
      try {
        const apiData = await fetchDrugApi({ itemName: name, numOfRows: '1' });
        const items = apiData?.body?.items || [];
        const itemList = Array.isArray(items) ? items : (items.item ? [items.item].flat() : []);
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
        console.error('[e약은요 상세 오류]', e.message);
      }
    }

    if (!detail && dbRows.length > 0) {
      detail = {
        name: dbRows[0].name,
        efcy: dbRows[0].description || '',
        entpName: '', useMethod: '', atpnWarn: '',
        atpn: '', intrc: '', se: '', deposit: '',
      };
    }

    return res.json({ success: true, data: detail });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false, message: '서버 오류' });
  }
}

// 약물 등록
async function createMedicine(req, res) {
  try {
    const { name, unit = '정', description } = req.body;
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

module.exports = { searchMedicines, createMedicine, getDrugDetail };
