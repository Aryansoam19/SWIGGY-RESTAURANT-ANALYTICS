"""
Swiggy Dataset Cleaning Pipeline
Author: Antigravity
Description:
    Reads raw Swiggy data, performs deduplication, type casting,
    missing value imputation, text sanitization, outlier treatment,
    and feature engineering. Saves the cleaned data to swiggy_cleaned.csv.
"""

import os
import re
import sys
import pandas as pd
import numpy as np

# Ensure UTF-8 output formatting for terminal
sys.stdout.reconfigure(encoding='utf-8')


def parse_rating_count(val):
    """Parses text rating strings like '100+ ratings', '1K+ ratings' into numeric values."""
    if pd.isna(val) or val == 'Too Few Ratings':
        return np.nan
    val_str = str(val).lower().replace('ratings', '').replace('rating', '').strip()
    val_str = val_str.replace('+', '').strip()
    if 'k' in val_str:
        try:
            return float(val_str.replace('k', '').strip()) * 1000
        except ValueError:
            return np.nan
    try:
        return float(val_str)
    except ValueError:
        return np.nan


def clean_offer_text(text):
    """Sanitizes multiline offer text, replacing linebreaks with pipe separators."""
    if pd.isna(text) or str(text).strip() == '':
        return 'No Offer'
    parts = [part.strip() for part in re.split(r'[\r\n]+', str(text)) if part.strip()]
    return ' | '.join(parts) if parts else 'No Offer'


def clean_swiggy_data(input_csv_path, output_csv_path):
    print("=" * 60)
    print("Starting Swiggy Data Cleaning Pipeline...")
    print("=" * 60)

    # 1. Load Data
    print(f"\n[1/7] Loading raw data from: {input_csv_path}")
    df = pd.read_csv(input_csv_path)
    initial_rows, initial_cols = df.shape
    print(f"      Initial shape: {initial_rows:,} rows, {initial_cols} columns")

    # 2. Deduplication
    print("\n[2/7] Checking and removing duplicates...")
    exact_duplicates = df.duplicated().sum()
    print(f"      Found {exact_duplicates:,} exact duplicate rows.")
    df = df.drop_duplicates().reset_index(drop=True)
    print(f"      Rows after deduplication: {len(df):,}")

    # 3. Standardize Column Names
    print("\n[3/7] Standardizing column names...")
    rename_mapping = {
        'Restaurant Name': 'restaurant_name',
        'Cuisine': 'cuisine',
        'Rating': 'rating_raw',
        'Number of Ratings': 'rating_count_raw',
        'Average Price': 'cost_for_two_raw',
        'Number of Offers': 'offer_count',
        'Offer Name': 'offer_name_raw',
        'Area': 'area',
        'Pure Veg': 'pure_veg_raw',
        'Location': 'location'
    }
    df = df.rename(columns=rename_mapping)

    # 4. Text & Missing Value Imputation
    print("\n[4/7] Cleaning text columns & imputing missing values...")
    # Strip whitespace
    for col in ['restaurant_name', 'location', 'area', 'cuisine']:
        if col in df.columns:
            df[col] = df[col].astype(str).str.strip().replace({'nan': np.nan})

    # Impute Area: 2 missing in Shillong -> fill with Location
    missing_area_count = df['area'].isna().sum()
    if missing_area_count > 0:
        df['area'] = df['area'].fillna(df['location'])
        print(f"      Imputed {missing_area_count} missing 'area' values using 'location'.")

    # Impute Cuisine: 27 missing -> fill with 'Unknown'
    missing_cuisine_count = df['cuisine'].isna().sum()
    df['cuisine'] = df['cuisine'].fillna('Unknown')
    print(f"      Imputed {missing_cuisine_count} missing 'cuisine' values with 'Unknown'.")

    # Clean up cuisine commas and extra internal spaces
    def normalize_cuisine(c):
        if pd.isna(c) or c == 'Unknown':
            return 'Unknown'
        items = [i.strip() for i in str(c).split(',') if i.strip()]
        return ', '.join(items) if items else 'Unknown'

    df['cuisine'] = df['cuisine'].apply(normalize_cuisine)

    # Feature Engineering on Cuisine
    df['primary_cuisine'] = df['cuisine'].apply(lambda x: x.split(',')[0].strip())
    df['cuisine_count'] = df['cuisine'].apply(
        lambda x: 0 if x == 'Unknown' else len([i for i in x.split(',') if i.strip()])
    )

    # 5. Rating & Rating Count Parsing
    print("\n[5/7] Parsing rating metrics...")
    # Rating Status category: 'Rated', 'New', 'Unrated'
    def get_rating_status(val):
        if pd.isna(val) or val == '--':
            return 'Unrated'
        elif str(val).strip().upper() == 'NEW':
            return 'New'
        return 'Rated'

    df['rating_status'] = df['rating_raw'].apply(get_rating_status)
    df['rating'] = pd.to_numeric(
        df['rating_raw'].replace({'--': np.nan, 'NEW': np.nan}),
        errors='coerce'
    ).round(2)

    # Number of Ratings parsed into numeric
    df['rating_count'] = df['rating_count_raw'].apply(parse_rating_count)

    # 6. Price & Offer Cleaning
    print("\n[6/7] Extracting price & cleaning offers...")
    # Extract integer price
    df['cost_for_two'] = df['cost_for_two_raw'].str.extract(r'(\d+)')[0].astype(int)

    # Outlier correction: Fix known extreme typo (e.g. ₹199246 for two in Lalitpur snack shop)
    extreme_mask = df['cost_for_two'] > 50000
    if extreme_mask.sum() > 0:
        print(f"      Treating {extreme_mask.sum()} extreme pricing typo(s) (> ₹50,000):")
        for idx in df[extreme_mask].index:
            old_val = df.loc[idx, 'cost_for_two']
            # Correct ₹199246 to ₹199
            corrected_val = int(str(old_val)[:3])
            df.loc[idx, 'cost_for_two'] = corrected_val
            print(f"      - Row {idx} ({df.loc[idx, 'restaurant_name']}): {old_val} -> {corrected_val}")

    # Pure Veg to boolean and standardized string
    df['is_pure_veg'] = df['pure_veg_raw'].astype(str).str.strip().str.lower().eq('yes')

    # Offers
    df['offer_count'] = df['offer_count'].fillna(0).astype(int)
    df['offer_name'] = df['offer_name_raw'].apply(clean_offer_text)

    # 7. Select & Reorder Columns
    final_columns = [
        'restaurant_name',
        'location',
        'area',
        'cuisine',
        'primary_cuisine',
        'cuisine_count',
        'rating',
        'rating_status',
        'rating_count',
        'cost_for_two',
        'is_pure_veg',
        'offer_count',
        'offer_name'
    ]
    cleaned_df = df[final_columns].copy()

    # Save to CSV
    print(f"\n[7/7] Exporting cleaned data to: {output_csv_path}")
    cleaned_df.to_csv(output_csv_path, index=False, encoding='utf-8')
    print("      Export complete!")

    print("\n" + "=" * 60)
    print("DATA CLEANING SUMMARY & VALIDATION")
    print("=" * 60)
    print(f"Final Shape: {cleaned_df.shape[0]:,} rows, {cleaned_df.shape[1]} columns")
    print(f"Memory Usage: {cleaned_df.memory_usage(deep=True).sum() / (1024 * 1024):.2f} MB")
    print("\nColumn Data Types & Non-Null Counts:")
    for col in cleaned_df.columns:
        null_cnt = cleaned_df[col].isna().sum()
        dtype = cleaned_df[col].dtype
        print(f" - {col:18} | Type: {str(dtype):10} | Nulls: {null_cnt:6,} ({null_cnt/len(cleaned_df)*100:.1f}%)")

    print("\nRating Status Distribution:")
    print(cleaned_df['rating_status'].value_counts())

    print("\nPure Veg Distribution:")
    print(cleaned_df['is_pure_veg'].value_counts())

    print("\nCost for Two Summary (INR):")
    print(cleaned_df['cost_for_two'].describe().round(1))

    print("\nTop 5 Cuisines (Primary):")
    print(cleaned_df['primary_cuisine'].value_counts().head(5))

    print("\nTop 5 Locations by Restaurant Count:")
    print(cleaned_df['location'].value_counts().head(5))

    print("\n" + "=" * 60)
    print("Pipeline finished successfully! Data is ready for analysis.")
    print("=" * 60)

    return cleaned_df


if __name__ == '__main__':
    base_dir = r"e:\DATA-ANALYTICS\Swiggy project DA"
    raw_path = os.path.join(base_dir, "swiggy_file.csv", "swiggy_file.csv")
    cleaned_path = os.path.join(base_dir, "swiggy_cleaned.csv")
    clean_swiggy_data(raw_path, cleaned_path)
