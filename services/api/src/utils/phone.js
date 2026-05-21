function normalizePhone(phone) {
  return String(phone ?? '').replace(/\D/g, '');
}

function isValidPhone(phone) {
  const digits = normalizePhone(phone);
  if (!digits) return false;

  // South Korea mobile numbers (e.g. 01012345678)
  if (/^01[016789]\d{7,8}$/.test(digits)) return true;
  // Landline / other domestic formats (conservative fallback)
  if (/^0\d{8,10}$/.test(digits)) return true;

  return false;
}

function formatPhone(phone) {
  const digits = normalizePhone(phone);

  if (digits.length === 11) {
    return `${digits.slice(0, 3)}-${digits.slice(3, 7)}-${digits.slice(7)}`;
  }

  if (digits.length === 10) {
    if (digits.startsWith('02')) {
      return `${digits.slice(0, 2)}-${digits.slice(2, 6)}-${digits.slice(6)}`;
    }
    return `${digits.slice(0, 3)}-${digits.slice(3, 6)}-${digits.slice(6)}`;
  }

  return digits;
}

module.exports = {
  normalizePhone,
  isValidPhone,
  formatPhone,
};
