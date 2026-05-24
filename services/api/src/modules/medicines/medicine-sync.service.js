const https = require('https');
const pool = require('../../config/db');

const DRUG_API_KEY = process.env.DRUG_API_KEY || '';
const DRUG_API_URL =
  'https://apis.data.go.kr/1471000/DrbEasyDrugInfoService/getDrbEasyDrugList';
const SYNC_KEY = 'drug_api_weekly';
const LOCK_KEY = 'medilink_medicine_sync_lock';
const WEEK_MS = 7 * 24 * 60 * 60 * 1000;
const PAGE_SIZE = 100;

let isSyncRunning = false;

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

function fetchDrugApi(params) {
  return new Promise((resolve, reject) => {
    const query = new URLSearchParams({
      serviceKey: DRUG_API_KEY,
      type: 'json',
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
          const parsed = JSON.parse(data);
          const resultCode = String(parsed?.header?.resultCode ?? '').trim();
          if (resultCode && resultCode !== '00') {
            const resultMsg = cleanText(parsed?.header?.resultMsg) || 'Unknown error';
            reject(new Error(`Drug API error (${resultCode}): ${resultMsg}`));
            return;
          }
          resolve(parsed);
        } catch (e) {
          reject(e);
        }
      });
    });

    req.on('error', reject);
    req.setTimeout(10000, () => {
      req.destroy(new Error('Drug API request timeout'));
    });
  });
}

async function getSyncState() {
  const [rows] = await pool.query(
    `SELECT sync_key, last_synced_at
     FROM medicine_sync_state
     WHERE sync_key = ?
     LIMIT 1`,
    [SYNC_KEY]
  );
  return rows[0] ?? null;
}

async function updateSyncState({ status, message = null, touchLastSynced = false }) {
  await pool.query(
    `UPDATE medicine_sync_state
     SET last_status = ?,
         last_message = ?,
         last_synced_at = CASE WHEN ? THEN NOW() ELSE last_synced_at END
     WHERE sync_key = ?`,
    [status, message, touchLastSynced ? 1 : 0, SYNC_KEY]
  );
}

async function countMedicines() {
  const [rows] = await pool.query(`SELECT COUNT(*) AS count FROM medicines`);
  return Number(rows[0]?.count || 0);
}

function toUpsertRows(items) {
  const rows = [];
  const seen = new Set();

  for (const item of items) {
    const name = cleanText(item?.itemName);
    if (!name || hasBrokenChars(name)) continue;

    const normalized = normalizeNameKey(name);
    if (!normalized || seen.has(normalized)) continue;
    seen.add(normalized);

    const description = cleanText(item?.efcyQesitm) || null;
    rows.push([name, '정', description]);
  }

  return rows;
}

async function upsertMedicines(rows) {
  if (rows.length === 0) return;

  const placeholders = rows.map(() => '(?, ?, ?)').join(', ');
  const params = rows.flat();

  await pool.query(
    `INSERT INTO medicines (name, unit, description)
     VALUES ${placeholders}
     ON DUPLICATE KEY UPDATE
       description = CASE
         WHEN (medicines.description IS NULL OR medicines.description = '')
              AND VALUES(description) IS NOT NULL
              AND VALUES(description) <> ''
         THEN VALUES(description)
         ELSE medicines.description
       END`,
    params
  );
}

async function acquireDbLock() {
  const [rows] = await pool.query(`SELECT GET_LOCK(?, 0) AS locked`, [LOCK_KEY]);
  return Number(rows[0]?.locked || 0) === 1;
}

async function releaseDbLock() {
  try {
    await pool.query(`SELECT RELEASE_LOCK(?)`, [LOCK_KEY]);
  } catch (_) {
    // noop
  }
}

async function runMedicineSyncIfDue() {
  if (!DRUG_API_KEY) {
    return { executed: false, reason: 'no_api_key' };
  }

  if (isSyncRunning) {
    return { executed: false, reason: 'already_running' };
  }

  isSyncRunning = true;
  let lockAcquired = false;

  try {
    lockAcquired = await acquireDbLock();
    if (!lockAcquired) {
      return { executed: false, reason: 'locked' };
    }

    const state = await getSyncState();
    if (!state) {
      throw new Error('medicine_sync_state row is missing');
    }

    const now = Date.now();
    const lastSyncedAt = state.last_synced_at ? new Date(state.last_synced_at).getTime() : 0;
    if (lastSyncedAt > 0 && now - lastSyncedAt < WEEK_MS) {
      return { executed: false, reason: 'not_due' };
    }

    await updateSyncState({
      status: 'running',
      message: '공공데이터 의약품 주간 동기화 실행 중',
      touchLastSynced: false,
    });

    const beforeCount = await countMedicines();

    let pageNo = 1;
    let totalPages = 1;
    let scannedItems = 0;

    while (pageNo <= totalPages) {
      const apiData = await fetchDrugApi({
        pageNo: String(pageNo),
        numOfRows: String(PAGE_SIZE),
      });

      const items = parseDrugItems(apiData);
      const totalCount = Number(apiData?.body?.totalCount || items.length || 0);
      totalPages = Math.max(1, Math.ceil(totalCount / PAGE_SIZE));

      scannedItems += items.length;
      const rows = toUpsertRows(items);
      await upsertMedicines(rows);

      pageNo += 1;
    }

    const afterCount = await countMedicines();
    const insertedCount = Math.max(0, afterCount - beforeCount);

    const message = `주간 동기화 완료 (수집 ${scannedItems}건, 신규 ${insertedCount}건)`;
    await updateSyncState({
      status: 'success',
      message,
      touchLastSynced: true,
    });

    return {
      executed: true,
      reason: 'synced',
      scannedItems,
      insertedCount,
    };
  } catch (err) {
    const message = String(err.message || err);
    const missingSyncStateTable =
      err?.code === 'ER_NO_SUCH_TABLE' && /medicine_sync_state/i.test(message);

    if (!missingSyncStateTable) {
      await updateSyncState({
        status: 'failed',
        message: message.slice(0, 250),
        touchLastSynced: false,
      });
    }

    throw err;
  } finally {
    if (lockAcquired) {
      await releaseDbLock();
    }
    isSyncRunning = false;
  }
}

module.exports = { runMedicineSyncIfDue };
