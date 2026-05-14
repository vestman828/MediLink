const express = require('express');
const { searchPatientByPhone, createFamilyMap, getPatientsByGuardian, deleteFamilyMap } = require('./family-map.controller');
const auth = require('../../middleware/auth');

const router = express.Router();

router.get('/search', auth, searchPatientByPhone);
router.post('/', auth, createFamilyMap);
router.get('/:guardian_id/patients', auth, getPatientsByGuardian);
router.delete('/patients/:patient_id', auth, deleteFamilyMap);

module.exports = router;
