const bcrypt = require('bcrypt');
const pool = require('../../config/db');

// 내 정보 조회
async function getMe(req, res) {
  try {
    const userId = req.user.user_id;
    const [rows] = await pool.query(
      `SELECT user_id, name, phone, role, created_at FROM users WHERE user_id = ?`,
      [userId]
    );
    if (rows.length === 0) return res.status(404).json({ success: false, message: '사용자를 찾을 수 없습니다.' });
    return res.json({ success: true, data: rows[0] });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false, message: '서버 오류' });
  }
}

// 이름 수정
async function updateName(req, res) {
  try {
    const userId = req.user.user_id;
    const { name } = req.body;
    if (!name || name.trim().length === 0) {
      return res.status(400).json({ success: false, message: '이름을 입력해주세요.' });
    }
    await pool.query(`UPDATE users SET name = ? WHERE user_id = ?`, [name.trim(), userId]);
    return res.json({ success: true, message: '이름이 변경되었습니다.' });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false, message: '서버 오류' });
  }
}

// 비밀번호 변경
async function updatePassword(req, res) {
  try {
    const userId = req.user.user_id;
    const { current_password, new_password } = req.body;
    if (!current_password || !new_password) {
      return res.status(400).json({ success: false, message: '현재 비밀번호와 새 비밀번호를 입력해주세요.' });
    }
    if (new_password.length < 6) {
      return res.status(400).json({ success: false, message: '새 비밀번호는 6자 이상이어야 합니다.' });
    }
    const [rows] = await pool.query(`SELECT password_hash FROM users WHERE user_id = ?`, [userId]);
    if (rows.length === 0) return res.status(404).json({ success: false, message: '사용자를 찾을 수 없습니다.' });

    const isMatch = await bcrypt.compare(current_password, rows[0].password_hash);
    if (!isMatch) return res.status(401).json({ success: false, message: '현재 비밀번호가 올바르지 않습니다.' });

    const newHash = await bcrypt.hash(new_password, 10);
    await pool.query(`UPDATE users SET password_hash = ? WHERE user_id = ?`, [newHash, userId]);
    return res.json({ success: true, message: '비밀번호가 변경되었습니다.' });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false, message: '서버 오류' });
  }
}

// FCM 토큰 저장
async function updateFcmToken(req, res) {
  try {
    const userId = req.user.user_id;
    const { fcm_token } = req.body;
    if (!fcm_token) return res.status(400).json({ success: false, message: 'fcm_token 필요' });
    await pool.query(`UPDATE users SET fcm_token = ? WHERE user_id = ?`, [fcm_token, userId]);
    return res.json({ success: true });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false, message: '서버 오류' });
  }
}

module.exports = { getMe, updateName, updatePassword, updateFcmToken };
