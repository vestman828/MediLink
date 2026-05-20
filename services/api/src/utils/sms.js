const { SolapiMessageService } = require('solapi');

let cachedApiKey = null;
let cachedApiSecret = null;
let cachedMessageService = null;

function readEnv(...keys) {
  for (const key of keys) {
    const value = process.env[key];
    if (value && String(value).trim()) return String(value).trim();
  }
  return '';
}

function digitsOnly(value) {
  return String(value ?? '').replace(/\D/g, '');
}

function maskPhone(phone) {
  const raw = digitsOnly(phone);
  if (raw.length < 7) return raw;
  return `${raw.slice(0, 3)}****${raw.slice(-4)}`;
}

function getMessageService() {
  const apiKey = readEnv('SOLAPI_API_KEY', 'COOLSMS_API_KEY');
  const apiSecret = readEnv('SOLAPI_API_SECRET', 'COOLSMS_API_SECRET');
  if (!apiKey || !apiSecret) return null;

  if (!cachedMessageService || cachedApiKey !== apiKey || cachedApiSecret !== apiSecret) {
    cachedApiKey = apiKey;
    cachedApiSecret = apiSecret;
    cachedMessageService = new SolapiMessageService(apiKey, apiSecret);
  }

  return cachedMessageService;
}

function getSenderNumber() {
  const sender = readEnv('SOLAPI_SENDER', 'COOLSMS_SENDER');
  return digitsOnly(sender);
}

async function sendOtpSms(phone, code) {
  const to = digitsOnly(phone);
  const from = getSenderNumber();
  const message = `[MediLink] OTP ${code} (valid for 5 minutes)`;
  const messageService = getMessageService();

  if (!messageService) {
    console.log(`[SMS-MOCK] to=${maskPhone(to)} msg="${message}"`);
    return { sent: true, provider: 'mock' };
  }

  if (!from) {
    throw new Error('SMS sender is not configured. Set SOLAPI_SENDER or COOLSMS_SENDER.');
  }

  await messageService.send({
    to,
    from,
    text: message,
  });

  console.log(`[SMS] sent to=${maskPhone(to)} via solapi`);
  return { sent: true, provider: 'solapi' };
}

module.exports = { sendOtpSms };
