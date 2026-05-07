const express = require('express');
const { searchMedicines, createMedicine } = require('./medicines.controller');
const auth = require('../../middleware/auth');

const router = express.Router();

router.get('/search', auth, searchMedicines);
router.post('/', auth, createMedicine);

module.exports = router;
