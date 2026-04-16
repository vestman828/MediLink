const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const authRoutes = require('./modules/auth/auth.routes');
const authMiddleware = require('./middleware/auth');

const app = express();

app.use(helmet());
app.use(cors());
app.use(morgan('dev'));
app.use(express.json());

app.get('/health', (req, res) => {
  res.json({ success: true, message: 'MediLink API is running' });
});

app.get('/api/me', authMiddleware, (req, res) => {
  res.json({
    success: true,
    user: req.user,
  });
});

app.use('/api/auth', authRoutes);

module.exports = app;