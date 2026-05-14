const express = require('express');
const { searchMedicines, createMedicine, getDrugDetail } = require('./medicines.controller');
const auth = require('../../middleware/auth');

const router = express.Router();

router.get('/search', auth, searchMedicines);
router.get('/detail', auth, getDrugDetail);
router.post('/', auth, createMedicine);

module.exports = router;
