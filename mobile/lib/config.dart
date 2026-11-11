/// App-level constants. Sport *behaviour* (thresholds etc.) lives in profiles/sport_profiles.yaml;
/// these lists are only the picker options and can grow freely. Each value is a free-text slug.
library;

const appVersion = '0.1.0';

/// WHOOP recovery, day strain and the backend sync are switched off while the product is our own sensor
/// first. The code stays; flip this to bring the WHOOP cards and settings back. Any Bluetooth heart-rate
/// strap (including a WHOOP band's Heart Rate Broadcast) still works as an optional extra.
const whoopEnabled = false;

const sportOptions = ['general', 'cricket', 'soccer', 'running', 'basketball', 'tennis', 'cycling', 'gym'];
const sessionTypeOptions = ['training', 'match', 'drill', 'gym'];
const placementOptions = [
  'phone_armband',
  'phone_pocket',
  'ankle',
  'shin',
  'thigh',
  'waist',
  'wrist',
  'upper_arm',
  'chest',
];
