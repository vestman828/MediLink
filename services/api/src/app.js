const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const authMiddleware = require('./middleware/auth');
const { UPLOAD_ROOT, UPLOAD_URL_PREFIX } = require('./utils/image-storage');

const authRoutes = require('./modules/auth/auth.routes');
const medicinesRoutes = require('./modules/medicines/medicines.routes');
const patientMedicinesRoutes = require('./modules/patient-medicines/patient-medicines.routes');
const schedulesRoutes = require('./modules/schedules/schedules.routes');
const intakeLogsRoutes = require('./modules/intake-logs/intake-logs.routes');
const guardianRoutes = require('./modules/guardian/guardian.routes');
const statisticsRoutes = require('./modules/statistics/statistics.routes');
const familyMapRoutes = require('./modules/family-map/family-map.routes');
const usersRoutes = require('./modules/users/users.routes');
const dailyNotesRoutes = require('./modules/daily-notes/daily-notes.routes');
const guardianAlertsRoutes = require('./modules/guardian-alerts/guardian-alerts.routes');
const familyRequestsRoutes = require('./modules/family-requests/family-requests.routes');

const app = express();

app.use(helmet());
app.use(cors());
app.use(morgan('dev'));
app.use(
  UPLOAD_URL_PREFIX,
  express.static(UPLOAD_ROOT, {
    setHeaders(res) {
      res.setHeader('Cross-Origin-Resource-Policy', 'cross-origin');
    },
  })
);
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
app.use('/api/users', usersRoutes);
app.use('/api/daily-notes', dailyNotesRoutes);
app.use('/api/guardian-alerts', guardianAlertsRoutes);
app.use('/api/family-requests', familyRequestsRoutes);

module.exports = app;
