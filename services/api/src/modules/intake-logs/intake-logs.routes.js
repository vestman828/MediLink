const express = require('express');
const auth = require('../../middleware/auth');
const { MAX_IMAGE_BYTES } = require('../../utils/image-storage');
const intakeLogsController = require('./intake-logs.controller');

const router = express.Router();

router.post(
  '/photo',
  auth,
  express.raw({
    type: ['image/jpeg', 'image/png', 'image/webp'],
    limit: MAX_IMAGE_BYTES,
  }),
  intakeLogsController.createPhotoIntakeLog
);
router.post('/', auth, intakeLogsController.createIntakeLog);
router.get('/history', auth, intakeLogsController.getIntakeHistory);
router.delete('/:log_id', auth, intakeLogsController.deleteIntakeLog);
router.get('/patient-history', auth, intakeLogsController.getPatientIntakeHistory);

module.exports = router;
