export function requireAuth(req, _res, next) {
  // TODO: JWT verify
  req.user = null;
  next();
}
