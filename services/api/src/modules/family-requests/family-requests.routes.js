const express = require('express');
const auth = require('../../middleware/auth');
const { sendRequest, getPendingRequests, respondRequest } = require('./family-requests.controller');

const router = express.Router();

router.post('/send', auth, sendRequest);
router.get('/pending', auth, getPendingRequests);
router.post('/respond', auth, respondRequest);

module.exports = router;
