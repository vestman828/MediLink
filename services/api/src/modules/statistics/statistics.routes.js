const express = require('express');
const { getAdherence } = require('./statistics.controller');
const auth = require('../../middleware/auth');

const router = express.Router();

router.get('/adherence', auth, getAdherence);

module.exports = router;
