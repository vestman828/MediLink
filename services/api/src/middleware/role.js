function requireRole(roles = []) {
  const allowed = Array.isArray(roles) ? roles : [roles];

  return (req, res, next) => {
    const role = req.user?.role;
    if (!role) {
      return res.status(401).json({ success: false, message: '인증 정보가 없습니다.' });
    }
    if (!allowed.includes(role)) {
      return res.status(403).json({ success: false, message: '권한이 없습니다.' });
    }
    return next();
  };
}

module.exports = { requireRole };
