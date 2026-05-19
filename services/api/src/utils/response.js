function ok(res, data = {}, message = '') {
  return res.json({ success: true, data, message });
}

function fail(res, status, code, message) {
  return res.status(status).json({
    success: false,
    error: { code, message }
  });
}

module.exports = { ok, fail };
