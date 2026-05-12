const pool = require('../../config/db');

// KST 오늘 날짜 반환 (UTC+9)
function getKstToday() {
  const now = new Date();
  const kst = new Date(now.getTime() + 9 * 60 * 60 * 1000);
  return kst.toISOString().substring(0, 10);
}

// note_date 문자열에서 날짜 부분만 추출 (DB가 DATE 타입이지만 직렬화 시 시간이 붙을 수 있음)
function toDateStr(val) {
  if (!val) return null;
  return String(val).substring(0, 10);
}

// 본인 메모 조회 (특정 날짜)
async function getNote(req, res) {
  try {
    const patientId = req.user.user_id;
    const { date } = req.query;
    const noteDate = date || getKstToday();
    const [rows] = await pool.query(
      `SELECT note_id, DATE_FORMAT(note_date, '%Y-%m-%d') AS note_date, condition_score, memo
       FROM daily_notes WHERE patient_id = ? AND note_date = ?`,
      [patientId, noteDate]
    );
    return res.json({ success: true, data: rows[0] || null });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false, message: '서버 오류' });
  }
}

// 본인 메모 월별 조회 (달력용)
async function getMonthlyNotes(req, res) {
  try {
    const patientId = req.user.user_id;
    const { year, month } = req.query;
    if (!year || !month) return res.status(400).json({ success: false, message: 'year, month 필요' });
    const [rows] = await pool.query(
      `SELECT DATE_FORMAT(note_date, '%Y-%m-%d') AS note_date, condition_score, memo
       FROM daily_notes
       WHERE patient_id = ? AND YEAR(note_date) = ? AND MONTH(note_date) = ?
       ORDER BY note_date`,
      [patientId, year, month]
    );
    return res.json({ success: true, data: rows });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false, message: '서버 오류' });
  }
}

// 보호자가 환자 메모 조회 (월별)
async function getPatientMonthlyNotes(req, res) {
  try {
    const { patient_id, year, month } = req.query;
    if (!patient_id || !year || !month) return res.status(400).json({ success: false, message: 'patient_id, year, month 필요' });
    const [rows] = await pool.query(
      `SELECT DATE_FORMAT(note_date, '%Y-%m-%d') AS note_date, condition_score, memo
       FROM daily_notes
       WHERE patient_id = ? AND YEAR(note_date) = ? AND MONTH(note_date) = ?
       ORDER BY note_date`,
      [patient_id, year, month]
    );
    return res.json({ success: true, data: rows });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false, message: '서버 오류' });
  }
}

// 메모 저장 (upsert)
async function saveNote(req, res) {
  try {
    const patientId = req.user.user_id;
    const { note_date, condition_score, memo } = req.body;
    if (!note_date || condition_score == null) {
      return res.status(400).json({ success: false, message: '날짜와 컨디션 점수는 필수입니다.' });
    }
    await pool.query(
      `INSERT INTO daily_notes (patient_id, note_date, condition_score, memo)
       VALUES (?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE condition_score = VALUES(condition_score), memo = VALUES(memo)`,
      [patientId, note_date, condition_score, memo || null]
    );
    return res.json({ success: true, message: '메모가 저장되었습니다.' });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false, message: '서버 오류' });
  }
}

module.exports = { getNote, getMonthlyNotes, getPatientMonthlyNotes, saveNote };
