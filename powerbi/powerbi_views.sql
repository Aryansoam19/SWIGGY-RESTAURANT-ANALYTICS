/*
================================================================================
SWIGGY RESTAURANT ANALYTICS - POWER BI OPTIMIZED DATABASE VIEWS
================================================================================
Target Database : PostgreSQL (postgres)
Purpose         : Pre-computes categories, price tiers, and aggregates to provide
                  instant, high-performance querying in Microsoft Power BI.
================================================================================
*/

-- ----------------------------------------------------------------------------
-- VIEW 1: Enriched Restaurant Fact Table for Power BI
-- ----------------------------------------------------------------------------
DROP VIEW IF EXISTS vw_powerbi_restaurants CASCADE;

CREATE OR REPLACE VIEW vw_powerbi_restaurants AS
SELECT 
    id AS restaurant_id,
    restaurant_name,
    location AS city,
    area,
    cuisine AS all_cuisines,
    primary_cuisine,
    cuisine_count,
    rating,
    rating_status,
    COALESCE(rating_count, 0) AS review_count,
    cost_for_two,
    is_pure_veg,
    offer_count,
    offer_name,
    -- Enriched Categorical Dimensions for Power BI Slicers
    CASE 
        WHEN cost_for_two < 200 THEN 'Budget (< ₹200)'
        WHEN cost_for_two BETWEEN 200 AND 400 THEN 'Mid-Range (₹200-₹400)'
        WHEN cost_for_two BETWEEN 401 AND 700 THEN 'Upper Mid (₹401-₹700)'
        ELSE 'Premium (> ₹700)'
    END AS price_tier,
    
    CASE 
        WHEN cost_for_two < 200 THEN 1
        WHEN cost_for_two BETWEEN 200 AND 400 THEN 2
        WHEN cost_for_two BETWEEN 401 AND 700 THEN 3
        ELSE 4
    END AS price_tier_sort,

    CASE 
        WHEN rating >= 4.5 THEN '⭐ 4.5+ Elite'
        WHEN rating >= 4.0 THEN '⭐ 4.0 - 4.4 Popular'
        WHEN rating >= 3.5 THEN '⭐ 3.5 - 3.9 Average'
        WHEN rating IS NOT NULL THEN '⭐ Below 3.5 Underperformer'
        ELSE '⚪ Unrated (Cold-Start)'
    END AS rating_tier,

    CASE 
        WHEN rating >= 4.5 THEN 1
        WHEN rating >= 4.0 THEN 2
        WHEN rating >= 3.5 THEN 3
        WHEN rating IS NOT NULL THEN 4
        ELSE 5
    END AS rating_tier_sort,

    CASE 
        WHEN cuisine_count = 1 THEN 'Single Cuisine Specialist'
        WHEN cuisine_count BETWEEN 2 AND 4 THEN 'Multi-Cuisine (2-4)'
        ELSE 'Generalist (5+ Cuisines)'
    END AS kitchen_model,

    CASE 
        WHEN offer_count = 0 THEN 'No Offers'
        WHEN offer_count BETWEEN 1 AND 2 THEN '1-2 Offers (Moderate)'
        ELSE '3+ Offers (Aggressive)'
    END AS promotional_tier,

    CASE 
        WHEN is_pure_veg = TRUE THEN 'Pure Veg'
        ELSE 'Non-Veg / Mixed'
    END AS veg_category

FROM swiggy_restaurants;


-- ----------------------------------------------------------------------------
-- VIEW 2: City-Level Aggregated KPI Summary (High-Speed Geolocation Map)
-- ----------------------------------------------------------------------------
DROP VIEW IF EXISTS vw_powerbi_city_summary CASCADE;

CREATE OR REPLACE VIEW vw_powerbi_city_summary AS
SELECT 
    location AS city,
    COUNT(*) AS total_restaurants,
    ROUND(AVG(rating)::numeric, 2) AS avg_rating,
    ROUND(AVG(cost_for_two)::numeric, 0) AS avg_cost_for_two,
    COUNT(*) FILTER (WHERE is_pure_veg = TRUE) AS pure_veg_count,
    ROUND((COUNT(*) FILTER (WHERE is_pure_veg = TRUE) * 100.0 / COUNT(*))::numeric, 1) AS veg_percentage,
    COUNT(*) FILTER (WHERE rating IS NULL) AS unrated_count,
    ROUND((COUNT(*) FILTER (WHERE rating IS NULL) * 100.0 / COUNT(*))::numeric, 1) AS unrated_percentage,
    ROUND(COALESCE(SUM(rating_count), 0)::numeric, 0) AS total_reviews_volume,
    COUNT(DISTINCT primary_cuisine) AS unique_cuisines_count
FROM swiggy_restaurants
GROUP BY location;


-- ----------------------------------------------------------------------------
-- VIEW 3: Cuisine Economics & Performance Matrix
-- ----------------------------------------------------------------------------
DROP VIEW IF EXISTS vw_powerbi_cuisine_matrix CASCADE;

CREATE OR REPLACE VIEW vw_powerbi_cuisine_matrix AS
SELECT 
    primary_cuisine,
    COUNT(*) AS total_outlets,
    ROUND((COUNT(*) * 100.0 / (SELECT COUNT(*) FROM swiggy_restaurants))::numeric, 2) AS market_share_pct,
    ROUND(AVG(cost_for_two)::numeric, 0) AS avg_cost,
    ROUND(AVG(rating)::numeric, 2) AS avg_rating,
    ROUND(COALESCE(AVG(rating_count), 0)::numeric, 0) AS avg_review_count,
    COUNT(*) FILTER (WHERE offer_count >= 2) AS heavy_discount_outlets,
    ROUND((COUNT(*) FILTER (WHERE offer_count >= 2) * 100.0 / COUNT(*))::numeric, 1) AS discount_reliance_pct,
    ROUND((COUNT(*) FILTER (WHERE is_pure_veg = TRUE) * 100.0 / COUNT(*))::numeric, 1) AS veg_share_pct
FROM swiggy_restaurants
GROUP BY primary_cuisine
HAVING COUNT(*) >= 50;
