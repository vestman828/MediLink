const express = require('express');
const { getDashboard } = require('./guardian.controller');
const auth = require('../../middleware/auth');

const router = express.Router();

router.get('/dashboard', auth, getDashboard);

module.exports = router;
