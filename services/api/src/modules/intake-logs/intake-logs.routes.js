const express = require('express');
const { createIntakeLog, getIntakeHistory, deleteIntakeLog, getPatientIntakeHistory } = require('./intake-logs.controller');
const auth = require('../../middleware/auth');

const router = express.Router();

router.post('/', auth, createIntakeLog);
router.get('/history', auth, getIntakeHistory);
router.get('/patient-history', auth, getPatientIntakeHistory);
router.delete('/:log_id', auth, deleteIntakeLog);

module.exports = router;
