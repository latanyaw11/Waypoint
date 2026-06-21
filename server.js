require('dotenv').config();
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');

const authRoutes = require('./routes/auth');
const tripRoutes = require('./routes/trips');
const placeRoutes = require('./routes/places');
const routeRoutes = require('./routes/routing');
const rideRoutes = require('./routes/rides');
const celebrityRoutes = require('./routes/celebrity');
const adminRoutes = require('./routes/admin');
const shareRoutes = require('./routes/sharing');

const app = express();

app.use(helmet());
app.use(cors({ origin: process.env.ALLOWED_ORIGINS?.split(',') || '*' }));
app.use(express.json({ limit: '2mb' }));

// Global rate limit; tighter limits applied per-route where needed (e.g. geocoding)
app.use(rateLimit({ windowMs: 60 * 1000, max: 120 }));

app.get('/health', (req, res) => res.json({ status: 'ok', service: 'waypoint-api', time: new Date().toISOString() }));

app.use('/api/auth', authRoutes);
app.use('/api/trips', tripRoutes);
app.use('/api/trips/:tripId/places', placeRoutes);
app.use('/api/trips/:tripId/routing', routeRoutes);
app.use('/api/trips/:tripId/rides', rideRoutes);
app.use('/api/celebrity-picks', celebrityRoutes);
app.use('/api/share', shareRoutes);
app.use('/api/admin', adminRoutes);

app.use((err, req, res, next) => {
  console.error(err);
  res.status(err.status || 500).json({ error: err.message || 'Internal server error' });
});

const PORT = process.env.PORT || 4000;
app.listen(PORT, () => console.log(`Waypoint API listening on :${PORT}`));

module.exports = app;
