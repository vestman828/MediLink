const express = require('express');
const auth = require('../../middleware/auth');
const intakeLogsController = require('./intake-logs.controller');

const router = express.Router();

router.post('/', auth, intakeLogsController.createIntakeLog);
router.get('/history', auth, intakeLogsController.getIntakeHistory);
router.delete('/:log_id', auth, intakeLogsController.deleteIntakeLog);
router.get('/patient-history', auth, intakeLogsController.getPatientIntakeHistory);

module.exports = router;
