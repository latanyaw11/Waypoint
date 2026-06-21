const router = require('express').Router({ mergeParams: true });
const { supabase } = require('../db/client');
const { requireAuth } = require('../middleware/auth');
const { uberDeepLink, lyftDeepLink } = require('../services/rideService');

router.use(requireAuth);

// Generate a ride deep link between two places (or base -> place) and log the request
router.post('/', async (req, res, next) => {
  try {
    const { fromPlaceId, toPlaceId, provider } = req.body;

    const resolve = async (id) => {
      if (id === 'base') {
        const { data } = await supabase.from('bases').select('*').eq('trip_id', req.params.tripId).eq('is_primary', true).single();
        return data;
      }
      const { data } = await supabase.from('places').select('*').eq('id', id).single();
      return data;
    };

    const from = await resolve(fromPlaceId);
    const to = await resolve(toPlaceId);
    if (!from || !to) return res.status(404).json({ error: 'Origin or destination not found' });

    const deepLink = provider === 'lyft' ? lyftDeepLink({ from, to }) : uberDeepLink({ from, to, clientId: process.env.UBER_CLIENT_ID });

    const { data, error } = await supabase
      .from('ride_requests')
      .insert({
        trip_id: req.params.tripId,
        requested_by: req.user.sub,
        from_place_id: fromPlaceId === 'base' ? null : fromPlaceId,
        to_place_id: toPlaceId === 'base' ? null : toPlaceId,
        provider: provider || 'uber',
        deep_link: deepLink,
      })
      .select()
      .single();
    if (error) throw error;

    // Affiliate event for revenue tracking (see business plan: per-ride referral fee)
    await supabase.from('affiliate_events').insert({
      trip_id: req.params.tripId, user_id: req.user.sub, partner: provider || 'uber', place_id: toPlaceId === 'base' ? null : toPlaceId, event_type: 'click',
    });

    res.status(201).json(data);
  } catch (e) { next(e); }
});

router.get('/', async (req, res, next) => {
  try {
    const { data, error } = await supabase.from('ride_requests').select('*').eq('trip_id', req.params.tripId).order('requested_at', { ascending: false });
    if (error) throw error;
    res.json(data);
  } catch (e) { next(e); }
});

module.exports = router;
