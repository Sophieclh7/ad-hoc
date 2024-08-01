# ---- Load packages ----
library(readxl)
library(tidyverse)
library(httr)
library(readr)
library(utils)
library(dplyr)
library(geographr)

# ---- Load ward names dataset ----
#Scrape URL
#Source: https://www.england.nhs.uk/publication/care-hours-per-patient-day-chppd-data/
#Some UK hospitals don't have wards as only inpatient hospitals have wards
#Ward name dataset
url <- "https://www.england.nhs.uk/wp-content/uploads/2021/02/nhs-england-ward-level-chppd-feb-2024.xlsx"

#Download and read URL as temp file
temp_file <- tempfile(fileext = ".xlsx")
download.file(url, temp_file, mode = "wb")
ward_data <- read_excel(temp_file)

# ---- Load NHS hospitals dataset ----
contact_data <- read_excel("hospital-data/data/nhs_hospital_info.xlsx")

#Organise ODS code column in ascending order
contact_data <- contact_data |>
  arrange(`ODS Code`)

# ---- Load postcode and ltla file ----
#Source: https://www.arcgis.com/sharing/rest/content/items/bc8f6d1f6ee64111b6a59b22c6605f3b/data
#Define URL and destination file path
url <- "https://www.arcgis.com/sharing/rest/content/items/bc8f6d1f6ee64111b6a59b22c6605f3b/data"
temp_dir <- tempdir()
destfile <- file.path(temp_dir, "dataset.zip")

#Download the file
download.file(url, destfile)

#Define path to unzip contents into temporary directory
unzip_dir <- file.path(temp_dir, "dataset")

#Unzip downloaded file
unzip(destfile, exdir = unzip_dir)

#Load dataset CSV file
csv_file_path <- file.path(unzip_dir, "PCD_OA21_LSOA21_MSOA21_LTLA22_UTLA22_CAUTH22_NOV23_UK_LU_v2.csv")
postcodes_data <- read.csv(csv_file_path)

#Rename postcode column
postcode_data <- postcodes_data |>
  rename(
    "Postcode" = `pcds`,
    "ltla21_code" = ltla22cd)

# ---- Merge postcode data to NHS data by postcode ----
postcode_join <- left_join(contact_data, postcode_data, by = "Postcode")

#Get rid of duplicates
regions_df <- lookup_ltla21_brc %>% 
  distinct(ltla21_code, brc_area, .keep_all = TRUE)

# ---- Merge postcode join to BRC data using ltla code ----
postcode_regions_df <- left_join(postcode_join, regions_df, by = "ltla21_code", relationship = "many-to-many")

# ---- Load site code and postcode file
#Source: https://digital.nhs.uk/services/organisation-data-service/export-data-files/csv-downloads/other-nhs-organisations
#Define URL and temporary file paths
url <- "https://files.digital.nhs.uk/assets/ods/current/etrust.zip"
temp_zip <- tempfile(fileext = ".zip")
temp_dir <- tempdir()

#Download and unzip ZIP file
GET(url, write_disk(temp_zip))
unzip(temp_zip, exdir = temp_dir)

#List and read first CSV file in directory
csv_file <- list.files(temp_dir, pattern = "\\.csv$", full.names = TRUE)[1]
if (is.na(csv_file)) {
  stop("No CSV files found in the ZIP archive.")
}
site_data <- read_csv(csv_file)

# ---- Map postcodes to ward names ----
#Rename site code and select only relevant columns before joining
site_data <- site_data |>
  rename("Site Code" = `A0A1E`) |>
  dplyr::select("Site Code", "AL10 8HR")
ward_data <- ward_data |>
  dplyr::select("Organisation Name", "Site Name", "Site Code", "Ward Name")

#Join data
site_join <- left_join(ward_data, site_data, by = "Site Code")

# ---- Join ward names to hospital dataset ----
#Rename column before join
site_join <- site_join |>
  rename(
    "Postcode" = `AL10 8HR`)

#Join datasets
trust_data <- left_join(site_join, postcode_regions_df, by = "Postcode", relationship = "many-to-many")

#Keep only required columns
trust_data <- trust_data |>
  dplyr::select("Organisation Name.y", "ODS Code", "brc_area", "Address1", "Address2", "Address3", "City", "County", "Postcode", "Telephone", "Email", "Website", "Ward Name", "Site Name")

#To find hospitals with missing data
#Some hospitals are in ward names dataset but not in hospital information dataset sent by NHS
na_df <- trust_data |>
  filter(is.na(brc_area))

# ---- Final dataset ----
#Reduce columns and rename
trust_ward_data <- trust_data |>
  dplyr::select(-"Site Name") |>
  rename(
    "Hospital Name" = `Organisation Name.y`,
    "Hospital Code" = `ODS Code`,
    "BRC Area" = `brc_area`,
  )

# ---- Save dataset as csv ----
write_csv(trust_ward_data, "hospital-data/data/trust-ward.csv")
