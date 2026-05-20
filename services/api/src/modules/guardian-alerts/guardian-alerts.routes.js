const express = require('express');
const { getAlerts, markAllRead } = require('./guardian-alerts.controller');
const auth = require('../../middleware/auth');

const router = express.Router();

router.get('/', auth, getAlerts);
router.post('/read-all', auth, markAllRead);

module.exports = router;
