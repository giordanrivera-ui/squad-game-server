/**
 * Properties feature – all static data and configuration.
 * INTERVAL is environment-aware so test vs production never relies on a comment.
 */

const PROPERTIES = [
  {
    name: "Micropod",
    cost: 15000,
    income: 840,
    description: "A compact, efficient urban dwelling designed for minimalist living in bustling city centers, offering basic amenities in a small footprint."
  },
  {
    name: "Cottage",
    cost: 45000,
    income: 2150,
    description: "A cozy, single-story home with a quaint charm, perfect for small families or retirees seeking a peaceful rural or suburban retreat."
  },
  {
    name: "Bungalow",
    cost: 98000,
    income: 4400,
    description: "A single-level residence with a low-pitched roof and wide veranda, ideal for comfortable living in temperate climates with easy accessibility."
  },
  {
    name: "Townhouse",
    cost: 150000,
    income: 6400,
    description: "A multi-story attached home in urban rows, combining privacy with community living, suitable for professionals in city environments."
  },
  {
    name: "Suburban home",
    cost: 210000,
    income: 8750,
    description: "A spacious family house in residential neighborhoods, featuring multiple bedrooms and a yard for everyday comfort and child-rearing."
  },
  {
    name: "Villa",
    cost: 300000,
    income: 11880,
    description: "An elegant countryside estate with expansive grounds, offering luxury and seclusion for those desiring a refined lifestyle away from urban hustle."
  },
  {
    name: "Mansion",
    cost: 500000,
    income: 18520,
    description: "A grand, opulent residence with numerous rooms and high-end features, symbolizing wealth and providing ample space for entertaining."
  },
  {
    name: "Mid-Rise Block",
    cost: 1200000,
    income: 43400,
    description: "A multi-unit apartment building of moderate height, catering to urban dwellers with shared amenities and convenient city access."
  },
  {
    name: "Residential Tower",
    cost: 3800000,
    income: 126700,
    description: "A high-rise condominium complex offering modern living spaces with panoramic views and premium facilities in metropolitan areas."
  },
  {
    name: "Skyscraper",
    cost: 9000000,
    income: 276900,
    description: "A towering architectural marvel housing luxury apartments and offices, representing pinnacle urban development and investment potential."
  }
];

const UPGRADE_COSTS = {
  "Fiber Optic": {
    "Micropod": 540,
    "Cottage": 720,
    "Bungalow": 900,
    "Townhouse": 1080,
    "Suburban home": 1260,
    "Villa": 1530,
    "Mansion": 1800,
    "Mid-Rise Block": 2070,
    "Residential Tower": 2530,
    "Skyscraper": 3200,
  },
  "Smart Appliances": {
    "Micropod": 800,
    "Cottage": 1000,
    "Bungalow": 1200,
    "Townhouse": 1400,
    "Suburban home": 1600,
    "Villa": 1900,
    "Mansion": 2220,
    "Mid-Rise Block": 2550,
    "Residential Tower": 3200,
    "Skyscraper": 4700,
  },
  "Double Glazing": {
    "Micropod": 1100,
    "Cottage": 1320,
    "Bungalow": 1550,
    "Townhouse": 1800,
    "Suburban home": 2020,
    "Villa": 2250,
    "Mansion": 2600,
    "Mid-Rise Block": 2900,
    "Residential Tower": 4000,
    "Skyscraper": 5500,
  },
  "Energy Recovery Ventilation": {
    "Micropod": 1450,
    "Cottage": 1700,
    "Bungalow": 1950,
    "Townhouse": 2200,
    "Suburban home": 2500,
    "Villa": 2750,
    "Mansion": 3250,
    "Mid-Rise Block": 3800,
    "Residential Tower": 4500,
    "Skyscraper": 6500,
  },
};

const UPGRADE_BOOSTS = {
  "Fiber Optic": {
    "Micropod": 30,
    "Cottage": 40,
    "Bungalow": 50,
    "Townhouse": 60,
    "Suburban home": 70,
    "Villa": 85,
    "Mansion": 100,
    "Mid-Rise Block": 115,
    "Residential Tower": 140,
    "Skyscraper": 175,
  },
  "Smart Appliances": {
    "Micropod": 40,
    "Cottage": 50,
    "Bungalow": 60,
    "Townhouse": 70,
    "Suburban home": 80,
    "Villa": 95,
    "Mansion": 110,
    "Mid-Rise Block": 125,
    "Residential Tower": 150,
    "Skyscraper": 210,
  },
  "Double Glazing": {
    "Micropod": 50,
    "Cottage": 60,
    "Bungalow": 70,
    "Townhouse": 80,
    "Suburban home": 90,
    "Villa": 100,
    "Mansion": 115,
    "Mid-Rise Block": 130,
    "Residential Tower": 170,
    "Skyscraper": 230,
  },
  "Energy Recovery Ventilation": {
    "Micropod": 60,
    "Cottage": 70,
    "Bungalow": 80,
    "Townhouse": 90,
    "Suburban home": 90,
    "Villa": 110,
    "Mansion": 130,
    "Mid-Rise Block": 150,
    "Residential Tower": 180,
    "Skyscraper": 260,
  },
};

/**
 * Claim interval. Production default is 4 hours.
 * In non-production environments the original 2-minute test value is used
 * so existing development / QA behaviour is preserved.
 */
const CLAIM_INTERVAL_MS = (typeof process !== 'undefined' && process.env && process.env.NODE_ENV === 'production')
  ? 4 * 60 * 60 * 1000
  : 2 * 60 * 1000;

module.exports = {
  PROPERTIES,
  UPGRADE_COSTS,
  UPGRADE_BOOSTS,
  CLAIM_INTERVAL_MS,
};
