const express = require('express');
const auth = require('../../middleware/auth');
const { getMe, updateName, updatePassword, updateFcmToken } = require('./users.controller');

const router = express.Router();

router.get('/me', auth, getMe);
router.patch('/me/name', auth, updateName);
router.patch('/me/password', auth, updatePassword);
router.patch('/me/fcm-token', auth, updateFcmToken);

module.exports = router;
