# Databricks notebook: 01_bronze_to_silver
# Port desde AWS Glue: etl-earthquake-aws/scripts/process_bronze_to_silver.py
#
# Lee JSON raw de ADLS Bronze, flattrea GeoJSON, limpia, valida,
# deduplica, enriquece con features, y escribe Delta a ADLS Silver.

from pyspark.sql import SparkSession
from pyspark.sql import functions as F
from pyspark.sql.window import Window
from pyspark.sql.types import TimestampType, IntegerType, DoubleType, BooleanType

# Configuración — ADF pasa estos parámetros
dbutils.widgets.text("adls_container", "bronze")
dbutils.widgets.text("adls_account", "")
dbutils.widgets.text("bronze_path", "raw/")
dbutils.widgets.text("silver_path", "cleansed/")

ADLS_ACCOUNT = dbutils.widgets.get("adls_account")
ADLS_CONTAINER = dbutils.widgets.get("adls_container")
BRONZE_PATH = f"abfss://{ADLS_CONTAINER}@{ADLS_ACCOUNT}.dfs.core.windows.net/{dbutils.widgets.get('bronze_path')}"
SILVER_PATH = f"abfss://silver@{ADLS_ACCOUNT}.dfs.core.windows.net/{dbutils.widgets.get('silver_path')}"

print(f"Bronze path: {BRONZE_PATH}")
print(f"Silver path: {SILVER_PATH}")

spark = SparkSession.builder.getOrCreate()

# --- 1. Ingestion & Flattening ---
print("Reading raw JSON data from Bronze layer...")
df_bronze_raw = spark.read.json(BRONZE_PATH)

if df_bronze_raw.rdd.isEmpty():
    print("Bronze layer is empty. Nothing to process.")
    dbutils.notebook.exit("SUCCESS_NO_DATA")

df_features = df_bronze_raw.select(F.explode("features").alias("feature"))

df_bronze = df_features.select(
    F.col("feature.id").alias("id"),
    F.col("feature.properties.mag").alias("mag"),
    F.col("feature.properties.place").alias("place"),
    F.col("feature.properties.time").alias("time"),
    F.col("feature.properties.updated").alias("updated"),
    F.col("feature.properties.url").alias("url"),
    F.col("feature.properties.felt").alias("felt"),
    F.col("feature.properties.cdi").alias("cdi"),
    F.col("feature.properties.mmi").alias("mmi"),
    F.col("feature.properties.alert").alias("alert"),
    F.col("feature.properties.status").alias("status"),
    F.col("feature.properties.tsunami").alias("tsunami"),
    F.col("feature.properties.sig").alias("sig"),
    F.col("feature.properties.net").alias("net"),
    F.col("feature.properties.code").alias("code"),
    F.col("feature.properties.nst").alias("nst"),
    F.col("feature.properties.dmin").alias("dmin"),
    F.col("feature.properties.rms").alias("rms"),
    F.col("feature.properties.gap").alias("gap"),
    F.col("feature.properties.magType").alias("magType"),
    F.col("feature.properties.type").alias("type"),
    F.col("feature.properties.title").alias("title"),
    F.col("feature.geometry.coordinates").getItem(0).alias("longitude"),
    F.col("feature.geometry.coordinates").getItem(1).alias("latitude"),
    F.col("feature.geometry.coordinates").getItem(2).alias("depth")
)

print(f"Flattened records: {df_bronze.count()}")

# --- 2. Transformation: casting, validation, dedup ---
df_cleaned = df_bronze \
    .withColumn("event_timestamp_utc", (F.col("time") / 1000).cast(TimestampType())) \
    .withColumn("updated_timestamp_utc", (F.col("updated") / 1000).cast(TimestampType())) \
    .withColumn("magnitude", F.col("mag").cast(DoubleType())) \
    .withColumn("depth_km", F.col("depth").cast(DoubleType())) \
    .withColumn("tsunami_warning", (F.col("tsunami") == 1).cast(BooleanType())) \
    .withColumn("significance", F.col("sig").cast(IntegerType())) \
    .withColumn("felt_reports", F.col("felt").cast(IntegerType())) \
    .withColumn("nst_stations", F.col("nst").cast(IntegerType())) \
    .withColumn("rms_travel_time", F.col("rms").cast(DoubleType())) \
    .withColumn("gap_azimuthal", F.col("gap").cast(DoubleType()))

df_selected = df_cleaned.select(
    F.col("id").alias("event_id"),
    "event_timestamp_utc", "updated_timestamp_utc",
    "magnitude", "depth_km", "latitude", "longitude", "place",
    F.col("type").alias("event_type"), "magType", "tsunami_warning",
    "significance", "felt_reports", "nst_stations",
    "rms_travel_time", "gap_azimuthal", "alert", "status", "url", "title"
)

# Data quality validation
df_validated = df_selected.filter(
    (F.col("magnitude").isNotNull()) & (F.col("magnitude").between(-2.0, 10.0)) &
    (F.col("latitude").isNotNull()) & (F.col("latitude").between(-90.0, 90.0)) &
    (F.col("longitude").isNotNull()) & (F.col("longitude").between(-180.0, 180.0)) &
    (F.col("depth_km").isNotNull()) & (F.col("depth_km") >= 0) & (F.col("depth_km") < 1000) &
    (F.col("event_timestamp_utc").isNotNull()) & (F.col("event_id").isNotNull())
)

# Dedup: keep most recent update per event_id
window_spec = Window.partitionBy("event_id").orderBy(F.col("updated_timestamp_utc").desc())
df_deduplicated = df_validated \
    .withColumn("rn", F.row_number().over(window_spec)) \
    .filter(F.col("rn") == 1) \
    .drop("rn")

# --- 3. Feature Engineering ---
df_enriched = df_deduplicated \
    .withColumn("magnitude_category",
        F.when(F.col("magnitude") < 3.0, "Micro")
         .when(F.col("magnitude") < 4.0, "Minor")
         .when(F.col("magnitude") < 5.0, "Light")
         .when(F.col("magnitude") < 6.0, "Moderate")
         .when(F.col("magnitude") < 7.0, "Strong")
         .when(F.col("magnitude") < 8.0, "Major")
         .otherwise("Great")) \
    .withColumn("depth_category",
        F.when(F.col("depth_km") <= 70, "Shallow")
         .when(F.col("depth_km") <= 300, "Intermediate")
         .otherwise("Deep")) \
    .withColumn("hemisphere_ns", F.when(F.col("latitude") >= 0, "Northern").otherwise("Southern")) \
    .withColumn("hemisphere_ew", F.when(F.col("longitude") >= 0, "Eastern").otherwise("Western")) \
    .withColumn("year", F.year(F.col("event_timestamp_utc"))) \
    .withColumn("month", F.month(F.col("event_timestamp_utc"))) \
    .withColumn("day", F.dayofmonth(F.col("event_timestamp_utc"))) \
    .withColumn("hour", F.hour(F.col("event_timestamp_utc"))) \
    .withColumn("day_of_week", F.dayofweek(F.col("event_timestamp_utc"))) \
    .withColumn("extracted_region_detail", F.trim(F.regexp_extract(F.col("place"), r",\s*(.*)$", 1))) \
    .withColumn("extracted_country",
        F.when(F.col("extracted_region_detail") != "", F.col("extracted_region_detail"))
         .otherwise(F.trim(F.col("place")))) \
    .withColumn("silver_processing_timestamp_utc", F.current_timestamp())

# --- 4. Write to Silver (Delta) ---
print(f"Writing {df_enriched.count()} records to Silver (Delta) at: {SILVER_PATH}")

df_enriched.write \
    .format("delta") \
    .mode("overwrite") \
    .partitionBy("year", "month") \
    .save(SILVER_PATH)

print("Bronze → Silver completed successfully")
dbutils.notebook.exit("SUCCESS")
