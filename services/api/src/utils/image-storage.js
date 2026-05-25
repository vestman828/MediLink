const crypto = require('crypto');
const fs = require('fs/promises');
const path = require('path');

const SERVICE_ROOT = path.resolve(__dirname, '..', '..');
const UPLOAD_ROOT = resolveConfiguredPath(
  process.env.UPLOAD_DIR,
  path.join(SERVICE_ROOT, 'uploads')
);
const UPLOAD_URL_PREFIX = '/uploads';
const INTAKE_PHOTO_DIR = path.join(UPLOAD_ROOT, 'intake-photos');
const MAX_IMAGE_BYTES = parsePositiveInt(
  process.env.INTAKE_PHOTO_MAX_BYTES,
  7 * 1024 * 1024
);

class ImageStorageError extends Error {
  constructor(message, statusCode = 400) {
    super(message);
    this.name = 'ImageStorageError';
    this.statusCode = statusCode;
  }
}

function resolveConfiguredPath(configuredPath, fallbackPath) {
  if (!configuredPath) return fallbackPath;
  return path.isAbsolute(configuredPath)
    ? configuredPath
    : path.resolve(SERVICE_ROOT, configuredPath);
}

function parsePositiveInt(value, fallback) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) return fallback;
  return Math.floor(parsed);
}

function normalizeMimeType(contentType = '') {
  const mimeType = String(contentType).split(';')[0].trim().toLowerCase();
  if (mimeType === 'image/jpg') return 'image/jpeg';
  if (['image/jpeg', 'image/png', 'image/webp'].includes(mimeType)) {
    return mimeType;
  }
  return null;
}

function detectImageType(buffer) {
  if (
    buffer.length >= 3 &&
    buffer[0] === 0xff &&
    buffer[1] === 0xd8 &&
    buffer[2] === 0xff
  ) {
    return { mimeType: 'image/jpeg', extension: 'jpg' };
  }

  if (
    buffer.length >= 8 &&
    buffer[0] === 0x89 &&
    buffer[1] === 0x50 &&
    buffer[2] === 0x4e &&
    buffer[3] === 0x47 &&
    buffer[4] === 0x0d &&
    buffer[5] === 0x0a &&
    buffer[6] === 0x1a &&
    buffer[7] === 0x0a
  ) {
    return { mimeType: 'image/png', extension: 'png' };
  }

  if (
    buffer.length >= 12 &&
    buffer.toString('ascii', 0, 4) === 'RIFF' &&
    buffer.toString('ascii', 8, 12) === 'WEBP'
  ) {
    return { mimeType: 'image/webp', extension: 'webp' };
  }

  return null;
}

function assertValidImageBuffer(buffer, contentType) {
  if (!Buffer.isBuffer(buffer) || buffer.length === 0) {
    throw new ImageStorageError('이미지 파일이 비어 있습니다.');
  }

  if (buffer.length > MAX_IMAGE_BYTES) {
    throw new ImageStorageError('이미지 파일 크기가 너무 큽니다.', 413);
  }

  const detected = detectImageType(buffer);
  if (!detected) {
    throw new ImageStorageError('지원하지 않는 이미지 형식입니다.');
  }

  const declaredMimeType = normalizeMimeType(contentType);
  if (declaredMimeType && declaredMimeType !== detected.mimeType) {
    throw new ImageStorageError('이미지 형식이 Content-Type과 일치하지 않습니다.');
  }

  return detected;
}

function getPublicBaseUrl(req) {
  const configured = String(process.env.PUBLIC_BASE_URL || '').trim();
  if (configured) return configured.replace(/\/+$/, '');

  const protocol = req.protocol || 'http';
  const host = req.get('host');
  return `${protocol}://${host}`;
}

function buildUploadUrl(req, relativePath) {
  const encodedPath = relativePath
    .split(/[\\/]/)
    .map((segment) => encodeURIComponent(segment))
    .join('/');
  return `${getPublicBaseUrl(req)}${UPLOAD_URL_PREFIX}/${encodedPath}`;
}

function compactBase64(value) {
  const encoded = String(value || '').replace(/\s/g, '');
  if (!encoded || encoded.length % 4 !== 0 || !/^[A-Za-z0-9+/]+={0,2}$/.test(encoded)) {
    throw new ImageStorageError('이미지 base64 데이터가 올바르지 않습니다.');
  }
  return encoded;
}

function parseDataImage(input) {
  const match = /^data:([^;,]+);base64,(.*)$/is.exec(String(input || '').trim());
  if (!match) return null;

  const mimeType = normalizeMimeType(match[1]);
  if (!mimeType) {
    throw new ImageStorageError('지원하지 않는 이미지 형식입니다.');
  }

  return {
    buffer: Buffer.from(compactBase64(match[2]), 'base64'),
    contentType: mimeType,
  };
}

function normalizeExistingUrl(input, req) {
  const value = String(input || '').trim();
  if (/^https?:\/\//i.test(value)) return value;
  if (value.startsWith(`${UPLOAD_URL_PREFIX}/`)) {
    return `${getPublicBaseUrl(req)}${value}`;
  }
  return null;
}

function buildFileName(context, extension) {
  const patientId = Number(context?.patientId) || 'unknown';
  const scheduleId = Number(context?.scheduleId) || 'unknown';
  return [
    'intake',
    patientId,
    scheduleId,
    Date.now(),
    crypto.randomUUID(),
  ].join('-') + `.${extension}`;
}

async function saveImageBuffer(buffer, contentType, req, context = {}) {
  const detected = assertValidImageBuffer(buffer, contentType);
  await fs.mkdir(INTAKE_PHOTO_DIR, { recursive: true });

  const fileName = buildFileName(context, detected.extension);
  const filePath = path.join(INTAKE_PHOTO_DIR, fileName);
  await fs.writeFile(filePath, buffer, { flag: 'wx' });

  return {
    url: buildUploadUrl(req, path.join('intake-photos', fileName)),
    filePath,
  };
}

async function savePhotoInput(photoInput, req, context = {}) {
  if (!photoInput) return { url: null, filePath: null };

  const dataImage = parseDataImage(photoInput);
  if (dataImage) {
    return saveImageBuffer(dataImage.buffer, dataImage.contentType, req, context);
  }

  const existingUrl = normalizeExistingUrl(photoInput, req);
  if (existingUrl) return { url: existingUrl, filePath: null };

  throw new ImageStorageError('사진 데이터는 이미지 파일 또는 URL이어야 합니다.');
}

function filePathFromUploadUrl(photoUrl) {
  if (!photoUrl) return null;

  let pathname;
  try {
    pathname = new URL(photoUrl, 'http://local').pathname;
  } catch (_) {
    return null;
  }

  const prefix = `${UPLOAD_URL_PREFIX}/`;
  if (!pathname.startsWith(prefix)) return null;

  const relativePath = decodeURIComponent(pathname.slice(prefix.length));
  const filePath = path.resolve(UPLOAD_ROOT, relativePath);
  const relativeToRoot = path.relative(UPLOAD_ROOT, filePath);

  if (relativeToRoot.startsWith('..') || path.isAbsolute(relativeToRoot)) {
    return null;
  }

  return filePath;
}

async function deleteLocalFile(filePath) {
  if (!filePath) return;

  const resolvedPath = path.resolve(filePath);
  const relativeToRoot = path.relative(UPLOAD_ROOT, resolvedPath);
  if (relativeToRoot.startsWith('..') || path.isAbsolute(relativeToRoot)) return;

  try {
    await fs.unlink(resolvedPath);
  } catch (err) {
    if (err.code !== 'ENOENT') {
      console.error('[uploads] failed to delete file:', err);
    }
  }
}

async function deleteUploadedImageByUrl(photoUrl) {
  await deleteLocalFile(filePathFromUploadUrl(photoUrl));
}

module.exports = {
  ImageStorageError,
  MAX_IMAGE_BYTES,
  UPLOAD_ROOT,
  UPLOAD_URL_PREFIX,
  deleteLocalFile,
  deleteUploadedImageByUrl,
  saveImageBuffer,
  savePhotoInput,
};
