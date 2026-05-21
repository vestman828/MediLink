const bcrypt = require('bcrypt');
const pool = require('../../config/db');
const { signToken } = require('../../utils/jwt');
const { normalizePhone, isValidPhone, formatPhone } = require('../../utils/phone');
const {
  generateOtpCode,
  hashOtpCode,
  verifyOtpCode,
  generateVerifyToken,
} = require('../../utils/otp');
const { sendOtpSms } = require('../../utils/sms');

const OTP_EXPIRES_MINUTES = 5;
const OTP_RESEND_SECONDS = 60;
const VERIFY_TOKEN_TTL_MINUTES = 15;
let phoneVerificationsTableReady = false;

async function ensurePhoneVerificationsTable() {
  if (phoneVerificationsTableReady) return;

  await pool.query(`
    CREATE TABLE IF NOT EXISTS phone_verifications (
      verification_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
      phone VARCHAR(20) NOT NULL,
      purpose VARCHAR(20) NOT NULL DEFAULT 'signup',
      code_hash CHAR(64) NOT NULL,
      attempt_count INT NOT NULL DEFAULT 0,
      max_attempts INT NOT NULL DEFAULT 5,
      expires_at DATETIME NOT NULL,
      verified_at DATETIME NULL,
      verify_token VARCHAR(128) NULL,
      consumed_at DATETIME NULL,
      created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (verification_id),
      KEY idx_phone_purpose_verification (phone, purpose, verification_id),
      KEY idx_verify_token (verify_token)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
  `);

  phoneVerificationsTableReady = true;
}

function isOtpCodeExposed() {
  if (process.env.EXPOSE_OTP_CODE !== undefined) {
    return process.env.EXPOSE_OTP_CODE === '1' || process.env.EXPOSE_OTP_CODE === 'true';
  }
  return process.env.NODE_ENV !== 'production';
}

async function sendSignupOtp(req, res) {
  try {
    await ensurePhoneVerificationsTable();

    const normalizedPhone = normalizePhone(req.body.phone);
    const purpose = String(req.body.purpose || 'signup');

    if (purpose !== 'signup') {
      return res.status(400).json({ success: false, message: '지원하지 않는 인증 목적입니다.' });
    }

    if (!isValidPhone(normalizedPhone)) {
      return res.status(400).json({ success: false, message: '전화번호 형식이 올바르지 않습니다.' });
    }

    const [existingUsers] = await pool.query(
      `SELECT user_id
       FROM users
       WHERE REPLACE(phone, '-', '') = ?
       LIMIT 1`,
      [normalizedPhone]
    );
    if (existingUsers.length > 0) {
      return res.status(409).json({ success: false, message: '이미 가입된 전화번호입니다.' });
    }

    const [lastRows] = await pool.query(
      `SELECT TIMESTAMPDIFF(SECOND, created_at, NOW()) AS elapsed_sec
       FROM phone_verifications
       WHERE phone = ? AND purpose = 'signup'
       ORDER BY verification_id DESC
       LIMIT 1`,
      [normalizedPhone]
    );

    if (lastRows.length > 0) {
      const elapsedSec = Number(lastRows[0].elapsed_sec ?? OTP_RESEND_SECONDS);
      if (elapsedSec < OTP_RESEND_SECONDS) {
        return res.status(429).json({
          success: false,
          message: `잠시 후 다시 시도해주세요. (${OTP_RESEND_SECONDS - elapsedSec}초 후 가능)`,
        });
      }
    }

    const code = generateOtpCode();
    const codeHash = hashOtpCode(code);

    await pool.query(
      `INSERT INTO phone_verifications
         (phone, purpose, code_hash, max_attempts, expires_at)
       VALUES
         (?, 'signup', ?, 5, DATE_ADD(NOW(), INTERVAL ? MINUTE))`,
      [normalizedPhone, codeHash, OTP_EXPIRES_MINUTES]
    );

    try {
      await sendOtpSms(normalizedPhone, code);
    } catch (smsError) {
      console.error('[OTP] SMS send failed:', smsError);
      return res.status(502).json({
        success: false,
        message: 'SMS 발송에 실패했습니다. SOLAPI 설정(SOLAPI_API_KEY, SOLAPI_API_SECRET, SOLAPI_SENDER)을 확인해주세요.',
      });
    }

    return res.json({
      success: true,
      message: '인증번호를 전송했습니다.',
      expires_in: OTP_EXPIRES_MINUTES * 60,
      ...(isOtpCodeExposed() ? { debug_code: code } : {}),
    });
  } catch (error) {
    console.error(error);
    return res.status(500).json({ success: false, message: '서버 오류' });
  }
}

async function verifySignupOtp(req, res) {
  try {
    await ensurePhoneVerificationsTable();

    const normalizedPhone = normalizePhone(req.body.phone);
    const code = String(req.body.code || '').trim();
    const purpose = String(req.body.purpose || 'signup');

    if (purpose !== 'signup') {
      return res.status(400).json({ success: false, message: '지원하지 않는 인증 목적입니다.' });
    }

    if (!isValidPhone(normalizedPhone) || !/^\d{6}$/.test(code)) {
      return res.status(400).json({ success: false, message: '요청 형식이 올바르지 않습니다.' });
    }

    const [rows] = await pool.query(
      `SELECT verification_id, code_hash, attempt_count, max_attempts,
              verified_at, verify_token,
              (expires_at <= NOW()) AS is_expired,
              TIMESTAMPDIFF(SECOND, verified_at, NOW()) AS verified_elapsed_sec
       FROM phone_verifications
       WHERE phone = ?
         AND purpose = 'signup'
         AND consumed_at IS NULL
       ORDER BY verification_id DESC
       LIMIT 1`,
      [normalizedPhone]
    );

    if (rows.length === 0) {
      return res.status(400).json({ success: false, message: '먼저 인증번호를 요청해주세요.' });
    }

    const row = rows[0];
    if (Number(row.is_expired) === 1) {
      return res.status(400).json({ success: false, message: '인증번호가 만료되었습니다. 다시 요청해주세요.' });
    }

    if (row.verified_at && row.verify_token) {
      const verifiedElapsedSec = Number(row.verified_elapsed_sec ?? Number.MAX_SAFE_INTEGER);
      if (verifiedElapsedSec <= VERIFY_TOKEN_TTL_MINUTES * 60) {
        return res.json({
          success: true,
          verify_token: row.verify_token,
          already_verified: true,
          message: '이미 인증된 번호입니다.',
        });
      }
    }

    if (Number(row.attempt_count) >= Number(row.max_attempts)) {
      return res.status(429).json({ success: false, message: '인증 시도 횟수를 초과했습니다. 다시 요청해주세요.' });
    }

    const ok = verifyOtpCode(code, row.code_hash);
    if (!ok) {
      await pool.query(
        `UPDATE phone_verifications
         SET attempt_count = attempt_count + 1
         WHERE verification_id = ?`,
        [row.verification_id]
      );
      return res.status(400).json({ success: false, message: '인증번호가 올바르지 않습니다.' });
    }

    const verifyToken = generateVerifyToken();
    await pool.query(
      `UPDATE phone_verifications
       SET verified_at = NOW(), verify_token = ?, attempt_count = attempt_count + 1
       WHERE verification_id = ?`,
      [verifyToken, row.verification_id]
    );

    return res.json({
      success: true,
      verify_token: verifyToken,
      message: '전화번호 인증이 완료되었습니다.',
    });
  } catch (error) {
    console.error(error);
    return res.status(500).json({ success: false, message: '서버 오류' });
  }
}

async function signup(req, res) {
  try {
    // 💡 인증 테이블 확인 로직은 유지
    await ensurePhoneVerificationsTable();

    // 💡 1. 필수로 요구하던 verify_token 슬쩍 빼기!
    const { name, phone, password, role } = req.body; 
    const normalizedPhone = normalizePhone(phone);

    // 💡 2. 필수값 검사에서도 verify_token 빼기!
    if (!name || !phone || !password || !role) {
      return res.status(400).json({ success: false, message: '필수값이 누락되었습니다.' });
    }
    if (!isValidPhone(normalizedPhone)) {
      return res.status(400).json({ success: false, message: '전화번호 형식이 올바르지 않습니다.' });
    }
    if (!['patient', 'guardian'].includes(role)) {
      return res.status(400).json({ success: false, message: 'role은 patient 또는 guardian 이어야 합니다.' });
    }

    const conn = await pool.getConnection();

    try {
      await conn.beginTransaction();

      const [existing] = await conn.query(
        `SELECT user_id
         FROM users
         WHERE REPLACE(phone, '-', '') = ?
         LIMIT 1`,
        [normalizedPhone]
      );
      if (existing.length > 0) {
        await conn.rollback();
        return res.status(409).json({ success: false, message: '이미 가입된 전화번호입니다.' });
      }

      // ==========================================
      // 🚀 골치 아팠던 OTP 검문소 통째로 철거 완료!
      // ==========================================

      const passwordHash = await bcrypt.hash(password, 10);
      const [result] = await conn.query(
        `INSERT INTO users (name, phone, password_hash, role)
         VALUES (?, ?, ?, ?)`,
        [name.trim(), formatPhone(normalizedPhone), passwordHash, role]
      );

      // (OTP 소진 처리하는 UPDATE 문도 필요 없어져서 철거!)

      await conn.commit();
      return res.status(201).json({ success: true, user_id: result.insertId });
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }
  } catch (error) {
    console.error(error);
    return res.status(500).json({ success: false, message: '서버 오류' });
  }
}

async function login(req, res) {
  try {
    const { phone, password } = req.body;
    const normalizedPhone = normalizePhone(phone);

    if (!phone || !password) {
      return res.status(400).json({ success: false, message: '필수값이 누락되었습니다.' });
    }
    if (!isValidPhone(normalizedPhone)) {
      return res.status(400).json({ success: false, message: '전화번호 형식이 올바르지 않습니다.' });
    }

    const [rows] = await pool.query(
      `SELECT user_id, name, phone, password_hash, role
       FROM users
       WHERE REPLACE(phone, '-', '') = ?
       LIMIT 1`,
      [normalizedPhone]
    );

    if (rows.length === 0) {
      return res.status(404).json({ success: false, message: '사용자를 찾을 수 없습니다.' });
    }

    const user = rows[0];
    const isMatch = await bcrypt.compare(password, user.password_hash);
    if (!isMatch) {
      return res.status(401).json({ success: false, message: '비밀번호가 올바르지 않습니다.' });
    }

    const accessToken = signToken({ user_id: user.user_id, role: user.role });
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
    return res.status(500).json({ success: false, message: '서버 오류' });
  }
}

async function checkPhoneExists(req, res) {
  try {
    const normalizedPhone = normalizePhone(req.query.phone);
    if (!isValidPhone(normalizedPhone)) {
      return res.status(400).json({ success: false, message: '전화번호 형식이 올바르지 않습니다.' });
    }

    const [rows] = await pool.query(
      `SELECT user_id, role
       FROM users
       WHERE REPLACE(phone, '-', '') = ?
       LIMIT 1`,
      [normalizedPhone]
    );

    return res.json({
      success: true,
      exists: rows.length > 0,
      user_id: rows[0]?.user_id ?? null,
      role: rows[0]?.role ?? null,
    });
  } catch (error) {
    console.error(error);
    return res.status(500).json({ success: false, message: '서버 오류' });
  }
}

async function logout(req, res) {
  try {
    const userId = req.user.user_id;
    await pool.query(`UPDATE users SET fcm_token = NULL WHERE user_id = ?`, [userId]);
    return res.json({ success: true, message: '로그아웃되었습니다.' });
  } catch (error) {
    console.error(error);
    return res.status(500).json({ success: false, message: '서버 오류' });
  }
}

module.exports = {
  sendSignupOtp,
  verifySignupOtp,
  signup,
  login,
  checkPhoneExists,
  logout,
};
