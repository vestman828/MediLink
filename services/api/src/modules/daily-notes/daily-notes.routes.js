const express = require('express');
const auth = require('../../middleware/auth');
const { getNote, getMonthlyNotes, getPatientMonthlyNotes, saveNote } = require('./daily-notes.controller');

const router = express.Router();
router.get('/', auth, getNote);
router.get('/monthly', auth, getMonthlyNotes);
router.get('/patient-monthly', auth, getPatientMonthlyNotes);
router.post('/', auth, saveNote);

module.exports = router;
