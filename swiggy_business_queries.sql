/*
================================================================================
SWIGGY RESTAURANT ANALYTICS - PRODUCTION SQL BUSINESS QUERY SUITE
================================================================================
Target Database : PostgreSQL 14+ (Tested on PostgreSQL 18.4)
Table           : swiggy_restaurants (139,321 Records)
Author          : Data Analytics Project
Description     : 15 Real-World Business Intelligence & Strategy SQL Queries
                  covering Window Functions, CTEs, Filter Aggregations,
                  Statistical Functions, and Strategic Segmentation.
================================================================================
*/

-- ============================================================================
-- SECTION 1: MARKET PENETRATION & GEOGRAPHIC EXPANSION
-- ============================================================================

-- Q1: Top 10 Cities by Restaurant Density & Cumulative Market Share
-- Business Goal: Identify Swiggy's highest inventory markets and market concentration.
-- SQL Concepts: CTE, Window Function (SUM() OVER ()), DENSE_RANK()
WITH CityCounts AS (
    SELECT 
        location,
        COUNT(*) AS restaurant_count
    FROM swiggy_restaurants
    GROUP BY location
)
SELECT 
    location,
    restaurant_count,
    ROUND((restaurant_count * 100.0 / SUM(restaurant_count) OVER ())::numeric, 2) AS pct_market_share,
    DENSE_RANK() OVER (ORDER BY restaurant_count DESC) AS city_rank
FROM CityCounts
ORDER BY restaurant_count DESC, location ASC
LIMIT 10;


-- Q2: Pure Vegetarian Market Penetration Across Top Cities
-- Business Goal: Identify underserved markets for pure veg cloud kitchens.
-- SQL Concepts: FILTER (WHERE ...), Conditional Aggregations, HAVING
SELECT 
    location,
    COUNT(*) AS total_restaurants,
    COUNT(*) FILTER (WHERE is_pure_veg = TRUE) AS pure_veg_count,
    ROUND((COUNT(*) FILTER (WHERE is_pure_veg = TRUE) * 100.0 / COUNT(*))::numeric, 1) AS veg_percentage,
    ROUND(AVG(rating) FILTER (WHERE is_pure_veg = TRUE)::numeric, 2) AS avg_veg_rating,
    ROUND(AVG(rating) FILTER (WHERE is_pure_veg = FALSE)::numeric, 2) AS avg_nonveg_rating
FROM swiggy_restaurants
GROUP BY location
HAVING COUNT(*) >= 1000
ORDER BY veg_percentage DESC
LIMIT 10;


-- Q3: City-Level #1 Cuisine Monopoly (Top Cuisine in Each Major City)
-- Business Goal: Tailor homepage recommendation carousels based on dominant local preferences.
-- SQL Concepts: CTE, PARTITION BY, ROW_NUMBER()
WITH CityCuisineRank AS (
    SELECT 
        location,
        primary_cuisine,
        COUNT(*) AS cuisine_count,
        ROUND((COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (PARTITION BY location))::numeric, 1) AS local_market_share,
        ROW_NUMBER() OVER (PARTITION BY location ORDER BY COUNT(*) DESC) AS rank
    FROM swiggy_restaurants
    GROUP BY location, primary_cuisine
)
SELECT 
    location,
    primary_cuisine AS top_cuisine,
    cuisine_count AS outlet_count,
    local_market_share AS market_share_percentage
FROM CityCuisineRank
WHERE rank = 1 
  AND location IN ('Mumbai', 'Bangalore', 'Hyderabad', 'Kolkata', 'Delhi', 'Jaipur', 'Lucknow', 'Ahmedabad', 'Pune', 'Chandigarh')
ORDER BY outlet_count DESC;


-- Q4: Cold-Start Problem: Percentage of Unrated / Low-Engagement Outlets by City
-- Business Goal: Identify regions requiring review-collection campaigns or delivery incentives.
-- SQL Concepts: FILTER (WHERE rating IS NULL), Ratio Computation
SELECT 
    location,
    COUNT(*) AS total_listings,
    COUNT(*) FILTER (WHERE rating IS NULL) AS unrated_count,
    ROUND((COUNT(*) FILTER (WHERE rating IS NULL) * 100.0 / COUNT(*))::numeric, 1) AS unrated_percentage,
    COUNT(*) FILTER (WHERE rating IS NOT NULL) AS rated_count
FROM swiggy_restaurants
GROUP BY location
HAVING COUNT(*) >= 1000
ORDER BY unrated_percentage DESC
LIMIT 10;


-- ============================================================================
-- SECTION 2: CUISINE PERFORMANCE & MENU ECONOMICS
-- ============================================================================

-- Q5: Top 10 Most Dominant Cuisines & Price/Discount Profiles
-- Business Goal: Evaluate menu category volume vs pricing power.
-- SQL Concepts: Global Window Aggregates, Multi-column Aggregations
SELECT 
    primary_cuisine,
    COUNT(*) AS outlet_count,
    ROUND((COUNT(*) * 100.0 / SUM(COUNT(*)) OVER ())::numeric, 2) AS cuisine_share_pct,
    ROUND(AVG(cost_for_two)::numeric, 0) AS avg_cost_for_two,
    ROUND(AVG(rating)::numeric, 2) AS avg_rating,
    ROUND(AVG(offer_count)::numeric, 1) AS avg_offers
FROM swiggy_restaurants
GROUP BY primary_cuisine
ORDER BY outlet_count DESC
LIMIT 10;


-- Q6: Premium vs Budget Cuisines (Ticket Size Economics)
-- Business Goal: Discover high Average Order Value (AOV) cuisine categories for targeted monetization.
-- SQL Concepts: HAVING filter, MIN/MAX range metrics
SELECT 
    primary_cuisine,
    COUNT(*) AS restaurant_count,
    ROUND(AVG(cost_for_two)::numeric, 0) AS avg_cost,
    MIN(cost_for_two) AS min_cost,
    MAX(cost_for_two) AS max_cost,
    ROUND(AVG(rating)::numeric, 2) AS avg_rating
FROM swiggy_restaurants
GROUP BY primary_cuisine
HAVING COUNT(*) >= 100
ORDER BY avg_cost DESC
LIMIT 10;


-- Q7: Specialist vs Multi-Cuisine Outlets: Does Menu Complexity Hurt Quality?
-- Business Goal: Guide new restaurant partners on whether to specialize or offer extensive multi-cuisine menus.
-- SQL Concepts: CASE statement classification, Group by alias
SELECT 
    CASE 
        WHEN cuisine_count = 1 THEN '1. Single Cuisine (Specialist)'
        WHEN cuisine_count BETWEEN 2 AND 4 THEN '2. Multi-Cuisine (2-4 Cuisines)'
        ELSE '3. Generalist (5+ Cuisines)'
    END AS restaurant_model,
    COUNT(*) AS total_restaurants,
    ROUND(AVG(rating)::numeric, 2) AS avg_rating,
    ROUND(AVG(cost_for_two)::numeric, 0) AS avg_cost,
    ROUND(AVG(rating_count)::numeric, 0) AS avg_review_count
FROM swiggy_restaurants
WHERE rating IS NOT NULL
GROUP BY 1
ORDER BY 1;


-- Q8: Rating Consistency & Standard Deviation by Cuisine (Risk vs Reward)
-- Business Goal: Identify cuisines with predictable high ratings vs high volatility.
-- SQL Concepts: STDDEV(), Statistical dispersion
SELECT 
    primary_cuisine,
    COUNT(*) AS total_outlets,
    ROUND(AVG(rating)::numeric, 2) AS mean_rating,
    ROUND(STDDEV(rating)::numeric, 2) AS rating_std_dev,
    ROUND(MIN(rating)::numeric, 1) AS min_rating,
    ROUND(MAX(rating)::numeric, 1) AS max_rating
FROM swiggy_restaurants
WHERE rating IS NOT NULL
GROUP BY primary_cuisine
HAVING COUNT(*) >= 1000
ORDER BY mean_rating DESC, rating_std_dev ASC
LIMIT 10;


-- ============================================================================
-- SECTION 3: PRICING STRATEGY & CUSTOMER RATINGS
-- ============================================================================

-- Q9: Price Tier Segmentation (Finding the Rating Sweet Spot)
-- Business Goal: Understand how price sensitivity affects customer review volume and satisfaction.
-- SQL Concepts: Categorical Binning, Aggregations
SELECT 
    CASE 
        WHEN cost_for_two < 200 THEN 'Budget (< Rs.200)'
        WHEN cost_for_two BETWEEN 200 AND 400 THEN 'Mid-Range (Rs.200-400)'
        WHEN cost_for_two BETWEEN 401 AND 700 THEN 'Upper Mid-Range (Rs.401-700)'
        ELSE 'Premium (> Rs.700)'
    END AS price_tier,
    COUNT(*) AS total_restaurants,
    ROUND(AVG(rating)::numeric, 2) AS avg_rating,
    ROUND(AVG(rating_count)::numeric, 0) AS avg_review_volume,
    ROUND(AVG(offer_count)::numeric, 1) AS avg_active_offers
FROM swiggy_restaurants
WHERE rating IS NOT NULL
GROUP BY 1
ORDER BY MIN(cost_for_two) ASC;


-- Q10: Top 3 Highest-Rated Restaurants in Top 5 Metro Cities
-- Business Goal: Highlight flagship restaurants for "Gourmet / Editor's Pick" carousels.
-- SQL Concepts: Window Function (DENSE_RANK() PARTITION BY), Multi-metric ordering
WITH MetroTop AS (
    SELECT 
        restaurant_name,
        location,
        primary_cuisine,
        rating,
        rating_count,
        cost_for_two,
        DENSE_RANK() OVER (
            PARTITION BY location 
            ORDER BY rating DESC, rating_count DESC
        ) AS city_rank
    FROM swiggy_restaurants
    WHERE location IN ('Bangalore', 'Mumbai', 'Hyderabad', 'Kolkata', 'Delhi')
      AND rating_count >= 50
)
SELECT 
    city_rank,
    location,
    restaurant_name,
    primary_cuisine,
    rating,
    rating_count,
    cost_for_two
FROM MetroTop
WHERE city_rank <= 3
ORDER BY location, city_rank;


-- Q11: Correlation between City Average Ticket Size & Overall Customer Ratings
-- Business Goal: Discover if affluent markets correlate with harsher or more generous review ratings.
-- SQL Concepts: Cross-City Aggregations, Volume normalization
SELECT 
    location,
    COUNT(*) AS restaurant_count,
    ROUND(AVG(cost_for_two)::numeric, 0) AS avg_ticket_size,
    ROUND(AVG(rating)::numeric, 2) AS avg_city_rating,
    ROUND((SUM(rating_count) / 1000.0)::numeric, 1) AS total_reviews_in_k
FROM swiggy_restaurants
WHERE rating IS NOT NULL
GROUP BY location
HAVING COUNT(*) >= 1500
ORDER BY avg_ticket_size DESC
LIMIT 10;


-- ============================================================================
-- SECTION 4: PROMOTIONS, BRANDS & STRATEGIC QUADRANTS
-- ============================================================================

-- Q12: The Discount Dilemma: Do Promotions Drive Reviews and Ratings?
-- Business Goal: Measure return on promotion (Are heavy discounters rewarded with more orders/reviews?).
-- SQL Concepts: Promo grouping, Impact analysis
SELECT 
    CASE 
        WHEN offer_count = 0 THEN 'No Offers'
        WHEN offer_count BETWEEN 1 AND 2 THEN '1-2 Offers'
        ELSE '3+ Offers (Aggressive)'
    END AS promotional_activity,
    COUNT(*) AS restaurant_count,
    ROUND(AVG(rating)::numeric, 2) AS avg_rating,
    ROUND(AVG(rating_count)::numeric, 0) AS avg_reviews_received,
    ROUND(AVG(cost_for_two)::numeric, 0) AS avg_price
FROM swiggy_restaurants
WHERE rating IS NOT NULL
GROUP BY 1
ORDER BY MIN(offer_count) ASC;


-- Q13: Top Discount-Reliant Cuisines (Highest % of Outlets with 2+ Offers)
-- Business Goal: Pinpoint competitive categories where discounts are mandatory to survive.
-- SQL Concepts: Percentage of heavy discounters, High-volume filtering
SELECT 
    primary_cuisine,
    COUNT(*) AS total_outlets,
    COUNT(*) FILTER (WHERE offer_count >= 2) AS heavy_discount_outlets,
    ROUND((COUNT(*) FILTER (WHERE offer_count >= 2) * 100.0 / COUNT(*))::numeric, 1) AS discount_reliance_pct,
    ROUND(AVG(cost_for_two)::numeric, 0) AS avg_cost
FROM swiggy_restaurants
GROUP BY primary_cuisine
HAVING COUNT(*) >= 500
ORDER BY discount_reliance_pct DESC
LIMIT 10;


-- Q14: Restaurant Strategic Positioning Matrix (Value vs Premium Quadrants)
-- Business Goal: Segment all partner restaurants into a 2x2 Boston Consulting Group (BCG)-style Matrix.
-- SQL Concepts: Dual CTE, Cross Join, 4-Way CASE classification
WITH Metrics AS (
    SELECT 
        AVG(rating) AS overall_avg_rating,
        AVG(cost_for_two) AS overall_avg_cost
    FROM swiggy_restaurants
    WHERE rating IS NOT NULL
)
SELECT 
    CASE 
        WHEN r.rating >= m.overall_avg_rating AND r.cost_for_two < m.overall_avg_cost 
            THEN '1. Value Champions (High Rating, Low Price)'
        WHEN r.rating >= m.overall_avg_rating AND r.cost_for_two >= m.overall_avg_cost 
            THEN '2. Premium Leaders (High Rating, High Price)'
        WHEN r.rating < m.overall_avg_rating AND r.cost_for_two < m.overall_avg_cost 
            THEN '3. Budget Underperformers (Low Rating, Low Price)'
        ELSE '4. Overpriced Risk (Low Rating, High Price)'
    END AS strategic_quadrant,
    COUNT(*) AS restaurant_count,
    ROUND((COUNT(*) * 100.0 / (SELECT COUNT(*) FROM swiggy_restaurants WHERE rating IS NOT NULL))::numeric, 1) AS pct_of_rated,
    ROUND(AVG(r.rating)::numeric, 2) AS avg_rating,
    ROUND(AVG(r.cost_for_two)::numeric, 0) AS avg_cost_for_two,
    ROUND(AVG(r.rating_count)::numeric, 0) AS avg_ratings_volume
FROM swiggy_restaurants r
CROSS JOIN Metrics m
WHERE r.rating IS NOT NULL
GROUP BY 1
ORDER BY 1;


-- Q15: Top National Restaurant Chains by Geographic Footprint & Performance
-- Business Goal: Identify key enterprise brand partners across India.
-- SQL Concepts: COUNT(DISTINCT location), Enterprise brand aggregation
SELECT 
    restaurant_name,
    COUNT(DISTINCT location) AS cities_present,
    COUNT(*) AS total_outlets,
    ROUND(AVG(rating)::numeric, 2) AS avg_brand_rating,
    ROUND(AVG(cost_for_two)::numeric, 0) AS avg_brand_cost,
    ROUND(SUM(rating_count)::numeric, 0) AS total_customer_reviews
FROM swiggy_restaurants
GROUP BY restaurant_name
HAVING COUNT(DISTINCT location) >= 15
ORDER BY cities_present DESC, total_outlets DESC
LIMIT 10;
