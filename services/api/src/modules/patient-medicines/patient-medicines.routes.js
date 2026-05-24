const express = require('express');
const { createPatientMedicine, getPatientMedicines, reactivatePatientMedicine, deactivatePatientMedicine, deletePatientMedicine, renameMedicine } = require('./patient-medicines.controller');
const auth = require('../../middleware/auth');

const router = express.Router();

router.post('/', auth, createPatientMedicine);
router.get('/:patient_id', auth, getPatientMedicines);
router.patch('/:patient_medicine_id/rename', auth, renameMedicine);
router.patch('/:patient_medicine_id/deactivate', auth, deactivatePatientMedicine);
router.patch('/:patient_medicine_id/reactivate', auth, reactivatePatientMedicine);
router.delete('/:patient_medicine_id', auth, deletePatientMedicine);

module.exports = router;
