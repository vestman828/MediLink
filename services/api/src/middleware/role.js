export function requireRole(_roles = []) {
  return (_req, _res, next) => {
    // TODO: role guard
    next();
  };
}
