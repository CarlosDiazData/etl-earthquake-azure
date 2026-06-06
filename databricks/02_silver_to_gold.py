# Databricks notebook: 02_silver_to_gold
# Port desde AWS Glue: etl-earthquake-aws/scripts/prosses_silver_gold.py
#
# Lee Delta de ADLS Silver, construye Star Schema dimensional
# (dim_date, dim_location, dim_magnitude, dim_event_type, fact_earthquake_events)
# y escribe Parquet a ADLS Gold.

from pyspark.sql import SparkSession
from pyspark.sql import functions as F
from pyspark.sql.window import Window
from datetime import datetime, timedelta

# Configuración — ADF pasa *path como parámetros; storage account hardcodeado
# para serverless con Unity Catalog MI (sin OAuth en Spark conf).
STORAGE_ACCOUNT = "sadearthemovitdev"

dbutils.widgets.text("silver_path", "cleansed/")
dbutils.widgets.text("gold_path", "dimensional/")

SILVER_PATH = f"abfss://silver@{STORAGE_ACCOUNT}.dfs.core.windows.net/{dbutils.widgets.get('silver_path')}"
GOLD_PATH_BASE = f"abfss://gold@{STORAGE_ACCOUNT}.dfs.core.windows.net/{dbutils.widgets.get('gold_path')}"

print(f"Silver path: {SILVER_PATH}")
print(f"Gold path: {GOLD_PATH_BASE}")

spark = SparkSession.builder.getOrCreate()

# --- 1. Read Silver ---
print("Reading Silver Delta table...")
df_silver = spark.read.format("delta").load(SILVER_PATH)

if df_silver.limit(1).count() == 0:
    print("Silver layer is empty. Nothing to process.")
    dbutils.notebook.exit("SUCCESS_NO_DATA")

record_count = df_silver.count()
print(f"Read {record_count} records from Silver.")

# --- 2. Dimension: dim_date ---
print("Generating dim_date...")
min_max = df_silver.select(
    F.min("event_timestamp_utc").alias("min_date"),
    F.max("event_timestamp_utc").alias("max_date")
).first()

start_date = min_max["min_date"].date()
end_date = min_max["max_date"].date() + timedelta(days=30)

date_list = []
current_date = start_date
while current_date <= end_date:
    date_list.append({
        "DateKey": int(current_date.strftime("%Y%m%d")),
        "FullDate": current_date,
        "Year": current_date.year,
        "Quarter": (current_date.month - 1) // 3 + 1,
        "Month": current_date.month,
        "MonthName": current_date.strftime("%B"),
        "DayOfMonth": current_date.day,
        "DayOfWeek": current_date.isoweekday() % 7 + 1,
        "DayName": current_date.strftime("%A"),
        "IsWeekend": 1 if current_date.weekday() >= 5 else 0,
    })
    current_date += timedelta(days=1)

df_dim_date = spark.createDataFrame(date_list)
print(f"dim_date: {df_dim_date.count()} rows")

# --- 3. Dimension: dim_location ---
print("Generating dim_location...")
df_dim_location = df_silver.select(
    "latitude", "longitude", "place", "extracted_country",
    "extracted_region_detail", "hemisphere_ns", "hemisphere_ew"
).distinct() \
    .withColumn("LocationKey", F.monotonically_increasing_id())
print(f"dim_location: {df_dim_location.count()} rows")

# --- 4. Dimension: dim_magnitude ---
print("Generating dim_magnitude...")
magnitude_data = [
    {"MagnitudeCategory": "Micro",   "MinMagnitude": -2.0, "MaxMagnitude": 2.9, "Description": "Not felt or rarely felt."},
    {"MagnitudeCategory": "Minor",   "MinMagnitude": 3.0,  "MaxMagnitude": 3.9, "Description": "Often felt, rarely causes damage."},
    {"MagnitudeCategory": "Light",   "MinMagnitude": 4.0,  "MaxMagnitude": 4.9, "Description": "Felt by many, possible minor damage."},
    {"MagnitudeCategory": "Moderate","MinMagnitude": 5.0,  "MaxMagnitude": 5.9, "Description": "Damage to weak structures."},
    {"MagnitudeCategory": "Strong",  "MinMagnitude": 6.0,  "MaxMagnitude": 6.9, "Description": "Moderate damage to well-built structures."},
    {"MagnitudeCategory": "Major",   "MinMagnitude": 7.0,  "MaxMagnitude": 7.9, "Description": "Serious damage to most buildings."},
    {"MagnitudeCategory": "Great",   "MinMagnitude": 8.0,  "MaxMagnitude": 10.0,"Description": "Widespread destruction."},
    {"MagnitudeCategory": "Unknown", "MinMagnitude": None,  "MaxMagnitude": None, "Description": "Category not determined."},
]
df_dim_magnitude = spark.createDataFrame(magnitude_data) \
    .withColumn("MagnitudeKey", F.monotonically_increasing_id())

# --- 5. Dimension: dim_event_type ---
print("Generating dim_event_type...")
df_dim_event_type = df_silver.select("event_type", "magType").distinct() \
    .withColumn("EventTypeKey", F.monotonically_increasing_id())
print(f"dim_event_type: {df_dim_event_type.count()} rows")

# --- 6. Fact table ---
print("Building fact_earthquake_events...")
df_fact_source = df_silver.withColumn(
    "DateKey",
    F.date_format(F.col("event_timestamp_utc"), "yyyyMMdd").cast("int")
)

df_fact_joined = df_fact_source \
    .join(df_dim_date.select("DateKey"), "DateKey", "inner") \
    .join(df_dim_location, ["latitude", "longitude", "place"], "inner") \
    .join(df_dim_magnitude, df_fact_source.magnitude_category == df_dim_magnitude.MagnitudeCategory, "inner") \
    .join(df_dim_event_type, ["event_type", "magType"], "inner")

df_fact_final = df_fact_joined.select(
    F.col("event_id").alias("EventID"),
    F.col("DateKey"),
    F.col("LocationKey"),
    F.col("MagnitudeKey"),
    F.col("EventTypeKey"),
    F.col("magnitude").alias("Magnitude"),
    F.col("depth_km").alias("DepthKm"),
    F.col("tsunami_warning").alias("TsunamiWarning"),
    F.col("significance").alias("Significance"),
    F.col("felt_reports").alias("FeltReports"),
    F.col("nst_stations").alias("NumberOfStations"),
    F.col("rms_travel_time").alias("RmsTravelTime"),
    F.col("gap_azimuthal").alias("AzimuthalGap"),
    F.col("url").alias("SourceURL"),
    F.col("silver_processing_timestamp_utc").alias("SilverProcessingTimestampUTC"),
    F.current_timestamp().alias("DWLoadTimestampUTC")
).dropDuplicates(["EventID"])

print(f"fact_earthquake_events: {df_fact_final.count()} rows")

# --- 7. Write all tables to Gold ---
def write_to_gold(df, table_name):
    path = f"{GOLD_PATH_BASE}{table_name}/"
    full_name = f"earthquake_etl.gold.{table_name}"
    print(f"Writing {full_name} to {path}")

    df.createOrReplaceTempView("__tmp_write")

    spark.sql(f"DROP TABLE IF EXISTS {full_name}")
    spark.sql(f"""
        CREATE TABLE {full_name}
        USING parquet
        LOCATION '{path}'
        AS SELECT * FROM __tmp_write
    """)

write_to_gold(df_dim_date, "dim_date")
write_to_gold(df_dim_location, "dim_location")
write_to_gold(df_dim_magnitude, "dim_magnitude")
write_to_gold(df_dim_event_type, "dim_event_type")
write_to_gold(df_fact_final, "fact_earthquake_events")

print("Silver → Gold completed successfully")
dbutils.notebook.exit("SUCCESS")
