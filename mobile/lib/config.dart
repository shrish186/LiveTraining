/// App-level constants. Sport *behaviour* (thresholds etc.) lives in profiles/sport_profiles.yaml;
/// these lists are only the picker options and can grow freely. Each value is a free-text slug.
library;

const appVersion = '0.1.0';

const sportOptions = ['general', 'soccer', 'running', 'basketball', 'tennis', 'cycling', 'gym'];
const sessionTypeOptions = ['training', 'match', 'drill', 'gym'];
const placementOptions = [
  'phone_armband',
  'phone_pocket',
  'shin',
  'thigh',
  'waist',
  'wrist',
  'upper_arm',
  'chest',
];

const defaultBackendUrl = 'http://192.168.1.10:8000';
