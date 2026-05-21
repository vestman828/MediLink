const crypto = require('crypto');

function generateOtpCode() {
  const n = crypto.randomInt(0, 1000000);
  return String(n).padStart(6, '0');
}

function hashOtpCode(code) {
  return crypto.createHash('sha256').update(String(code)).digest('hex');
}

function verifyOtpCode(code, hash) {
  const computed = hashOtpCode(code);
  const left = Buffer.from(computed, 'hex');
  const right = Buffer.from(String(hash), 'hex');
  if (left.length !== right.length) return false;
  return crypto.timingSafeEqual(left, right);
}

function generateVerifyToken() {
  return crypto.randomBytes(32).toString('hex');
}

module.exports = {
  generateOtpCode,
  hashOtpCode,
  verifyOtpCode,
  generateVerifyToken,
};
