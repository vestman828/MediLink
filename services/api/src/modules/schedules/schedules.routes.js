const express = require('express');
const { createSchedule, getTodaySchedules, getSchedulesByMedicine, replaceSchedules } = require('./schedules.controller');
const auth = require('../../middleware/auth');

const router = express.Router();

router.post('/', auth, createSchedule);
router.get('/today', auth, getTodaySchedules);
router.get('/by-medicine/:patient_medicine_id', auth, getSchedulesByMedicine);
router.put('/by-medicine/:patient_medicine_id', auth, replaceSchedules);

module.exports = router;
