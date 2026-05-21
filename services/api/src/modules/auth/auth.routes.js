const express = require('express');
const auth = require('../../middleware/auth');
const {
  sendSignupOtp,
  verifySignupOtp,
  signup,
  login,
  checkPhoneExists,
  logout,
} = require('./auth.controller');

const router = express.Router();

router.post('/otp/send', sendSignupOtp);
router.post('/otp/verify', verifySignupOtp);
router.post('/signup', signup);
router.post('/login', login);
router.get('/phone-exists', checkPhoneExists);
router.post('/logout', auth, logout);

module.exports = router;
