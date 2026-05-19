const pool = require('../../config/db');
const { sendFcmNotification } = require('../../config/firebase');
const { normalizePhone, isValidPhone } = require('../../utils/phone');

async function sendRequest(req, res) {
  try {
    if (req.user.role !== 'guardian') {
      return res.status(403).json({ success: false, message: '보호자만 요청을 보낼 수 있습니다.' });
    }

    const guardianId = req.user.user_id;
    const normalizedPhone = normalizePhone(req.body.phone);

    if (!isValidPhone(normalizedPhone)) {
      return res.status(400).json({ success: false, message: '전화번호 형식이 올바르지 않습니다.' });
    }

    const [patients] = await pool.query(
      `SELECT user_id, name, fcm_token
       FROM users
       WHERE REPLACE(phone, '-', '') = ?
         AND role = 'patient'`,
      [normalizedPhone]
    );

    if (patients.length === 0) {
      return res.status(404).json({ success: false, message: '해당 전화번호의 환자를 찾을 수 없습니다.' });
    }

    const patient = patients[0];

    const [existing] = await pool.query(
      `SELECT map_id
       FROM family_map
       WHERE guardian_id = ? AND patient_id = ?`,
      [guardianId, patient.user_id]
    );
    if (existing.length > 0) {
      return res.status(400).json({ success: false, message: '이미 연동된 환자입니다.' });
    }

    const [pendingReq] = await pool.query(
      `SELECT request_id
       FROM family_requests
       WHERE guardian_id = ? AND patient_id = ? AND status = 'pending'`,
      [guardianId, patient.user_id]
    );
    if (pendingReq.length > 0) {
      return res.status(400).json({ success: false, message: '이미 연동 요청을 보냈습니다.' });
    }

    const [guardians] = await pool.query(`SELECT name FROM users WHERE user_id = ?`, [guardianId]);
    const guardianName = guardians[0]?.name ?? '보호자';

    await pool.query(
      `INSERT INTO family_requests (guardian_id, patient_id) VALUES (?, ?)
       ON DUPLICATE KEY UPDATE status = 'pending', created_at = NOW()`,
      [guardianId, patient.user_id]
    );

    await sendFcmNotification(
      patient.fcm_token,
      '보호자 연동 요청',
      `${guardianName}님이 보호자 연동을 요청했습니다. 앱에서 수락 또는 거절해주세요.`,
      { type: 'family_request', guardian_id: String(guardianId) }
    );

    return res.json({ success: true, message: '연동 요청을 보냈습니다.' });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false, message: '서버 오류' });
  }
}

async function getPendingRequests(req, res) {
  try {
    if (req.user.role !== 'patient') {
      return res.status(403).json({ success: false, message: '환자만 조회할 수 있습니다.' });
    }

    const patientId = req.user.user_id;
    const [rows] = await pool.query(
      `SELECT fr.request_id, fr.guardian_id, u.name AS guardian_name, u.phone AS guardian_phone, fr.created_at
       FROM family_requests fr
       JOIN users u ON fr.guardian_id = u.user_id
       WHERE fr.patient_id = ? AND fr.status = 'pending'
       ORDER BY fr.created_at DESC`,
      [patientId]
    );

    return res.json({ success: true, data: rows });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false, message: '서버 오류' });
  }
}

async function respondRequest(req, res) {
  try {
    if (req.user.role !== 'patient') {
      return res.status(403).json({ success: false, message: '환자만 응답할 수 있습니다.' });
    }

    const patientId = req.user.user_id;
    const { request_id, action } = req.body;

    if (!request_id || !action) {
      return res.status(400).json({ success: false, message: 'request_id, action이 필요합니다.' });
    }

    if (!['accept', 'reject'].includes(action)) {
      return res.status(400).json({ success: false, message: 'action은 accept 또는 reject 이어야 합니다.' });
    }

    const [requests] = await pool.query(
      `SELECT request_id, guardian_id
       FROM family_requests
       WHERE request_id = ? AND patient_id = ? AND status = 'pending'`,
      [request_id, patientId]
    );

    if (requests.length === 0) {
      return res.status(404).json({ success: false, message: '요청을 찾을 수 없습니다.' });
    }

    const request = requests[0];

    if (action === 'accept') {
      await pool.query(
        `INSERT IGNORE INTO family_map (guardian_id, patient_id) VALUES (?, ?)`,
        [request.guardian_id, patientId]
      );
      await pool.query(`UPDATE family_requests SET status = 'accepted' WHERE request_id = ?`, [request_id]);

      const [patients] = await pool.query(`SELECT name FROM users WHERE user_id = ?`, [patientId]);
      const [guardians] = await pool.query(`SELECT fcm_token FROM users WHERE user_id = ?`, [request.guardian_id]);
      const patientName = patients[0]?.name ?? '환자';

      await sendFcmNotification(
        guardians[0]?.fcm_token,
        '보호자 연동 수락',
        `${patientName}님이 보호자 연동을 수락했습니다.`,
        { type: 'family_accepted' }
      );

      return res.json({ success: true, message: '연동 요청을 수락했습니다.' });
    }

    await pool.query(`UPDATE family_requests SET status = 'rejected' WHERE request_id = ?`, [request_id]);
    return res.json({ success: true, message: '연동 요청을 거절했습니다.' });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false, message: '서버 오류' });
  }
}

module.exports = { sendRequest, getPendingRequests, respondRequest };
