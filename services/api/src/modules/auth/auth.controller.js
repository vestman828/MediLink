const bcrypt = require('bcrypt');
const pool = require('../../config/db');
const { signToken } = require('../../utils/jwt');

async function signup(req, res) {
  try {
    const { name, phone, password, role } = req.body;

    if (!name || !phone || !password || !role) {
      return res.status(400).json({
        success: false,
        message: '필수값이 누락되었습니다.',
      });
    }

    if (!['patient', 'guardian'].includes(role)) {
      return res.status(400).json({
        success: false,
        message: 'role은 patient 또는 guardian 이어야 합니다.',
      });
    }

    const [existing] = await pool.query(
      'SELECT user_id FROM users WHERE phone = ?',
      [phone]
    );

    if (existing.length > 0) {
      return res.status(409).json({
        success: false,
        message: '이미 가입된 연락처입니다.',
      });
    }

    const passwordHash = await bcrypt.hash(password, 10);

    const [result] = await pool.query(
      `INSERT INTO users (name, phone, password_hash, role)
       VALUES (?, ?, ?, ?)`,
      [name, phone, passwordHash, role]
    );

    return res.status(201).json({
      success: true,
      user_id: result.insertId,
    });
  } catch (error) {
    console.error(error);
    return res.status(500).json({
      success: false,
      message: '서버 오류',
    });
  }
}

async function login(req, res) {
  try {
    const { phone, password } = req.body;

    if (!phone || !password) {
      return res.status(400).json({
        success: false,
        message: '필수값이 누락되었습니다.',
      });
    }

    const [rows] = await pool.query(
      `SELECT user_id, name, phone, password_hash, role
       FROM users
       WHERE phone = ?`,
      [phone]
    );

    if (rows.length === 0) {
      return res.status(404).json({
        success: false,
        message: '사용자가 없습니다.',
      });
    }

    const user = rows[0];
    const isMatch = await bcrypt.compare(password, user.password_hash);

    if (!isMatch) {
      return res.status(401).json({
        success: false,
        message: '비밀번호가 올바르지 않습니다.',
      });
    }

    const accessToken = signToken({
      user_id: user.user_id,
      role: user.role,
    });

    return res.json({
      success: true,
      accessToken,
      user: {
        user_id: user.user_id,
        name: user.name,
        role: user.role,
      },
    });
  } catch (error) {
    console.error(error);
    return res.status(500).json({
      success: false,
      message: '서버 오류',
    });
  }
}

module.exports = { signup, login };