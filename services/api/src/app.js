const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const authMiddleware = require('./middleware/auth');

const authRoutes = require('./modules/auth/auth.routes');
const medicinesRoutes = require('./modules/medicines/medicines.routes');
const patientMedicinesRoutes = require('./modules/patient-medicines/patient-medicines.routes');
const schedulesRoutes = require('./modules/schedules/schedules.routes');
const intakeLogsRoutes = require('./modules/intake-logs/intake-logs.routes');
const guardianRoutes = require('./modules/guardian/guardian.routes');
const statisticsRoutes = require('./modules/statistics/statistics.routes');
const familyMapRoutes = require('./modules/family-map/family-map.routes');

const app = express();

app.use(helmet());
app.use(cors());
app.use(morgan('dev'));
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));

app.get('/health', (req, res) => {
  res.json({ success: true, message: 'MediLink API is running' });
});

app.get('/api/me', authMiddleware, (req, res) => {
  res.json({ success: true, user: req.user });
});

app.use('/api/auth', authRoutes);
app.use('/api/medicines', medicinesRoutes);
app.use('/api/patient-medicines', patientMedicinesRoutes);
app.use('/api/schedules', schedulesRoutes);
app.use('/api/intake-logs', intakeLogsRoutes);
app.use('/api/guardian', guardianRoutes);
app.use('/api/statistics', statisticsRoutes);
app.use('/api/family-map', familyMapRoutes);

module.exports = app;