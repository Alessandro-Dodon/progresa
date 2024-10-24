# Loading Data and Libraries
# Suppress warnings and messages
suppressWarnings(suppressMessages({
  
  # Load necessary libraries quietly
  library(haven)
  library(dplyr)
  library(tidyr)
  library(lmtest)
  library(ggplot2)
  library(estimatr)
}))

# Use a relative path
file_path <- "./Progresa.dta"

# Load the dataset
dataset <- read_dta(file_path)

################################################################################
# Important Facts (before starting)
# Survey conducted in 1997, villages assigned to intervention or control group
# Intervention begins in 1998, continues in 1999
# This is why D is not available for 1997, but D_assig yes 
# We are analyzing the impact of the program on children enrollment in school

################################################################################
# Part 1 Descriptive Analysis
# Understanding the dataset better via classic functions
head(dataset)

summary(dataset)

str(dataset)

dim(dataset)

sum(is.na(dataset))

sapply(dataset, function(x) length(unique(x)))

# Histograms
hist(dataset$age_ind)
hist(dataset$yycali)
hist(dataset$eduHH)
hist(dataset$ageHH)
hist(dataset$yycali)

################################################################################
# Summary Statistics 
# Select only the specified variables for analysis
selected_dataset <- select(dataset, age_ind, yycali, ageHH, eduHH, age, enroll_child, sex, lang, sexHH, D, pov_HH, D_HH, uniqhh, D_assig, maxcut, E)

# Directly generate summary statistics for the selected dataset
summary_stats <- function(data) {
  # Create an empty data frame for the summary statistics
  summary_df <- data.frame(Variable = character(), Mean = numeric(), SD = numeric(), Missing_Values = integer())
  
  for (var in names(data)) {
    # Calculate mean, sd, and missing values for each variable
    mean_val <- mean(data[[var]], na.rm = TRUE)
    sd_val <- sd(data[[var]], na.rm = TRUE)
    missing_val <- sum(is.na(data[[var]]))
    
    # Append the calculated values to the summary data frame
    summary_df <- rbind(summary_df, data.frame(Variable = var, Mean = mean_val, SD = sd_val, Missing_Values = missing_val))
  }
  
  # Round the Mean and SD to 2 decimal places
  summary_df$Mean <- round(summary_df$Mean, 2)
  summary_df$SD <- round(summary_df$SD, 2)
  
  return(summary_df)
}

# Apply the function to the selected dataset
summary_table_selected <- summary_stats(selected_dataset)

# Print the summary table
print(summary_table_selected)

################################################################################
# Differences at Baseline (Eligible vs Non Eligible Group in 1997 for poor households)
# Filter the dataset for year 1997 and poor households (we will use D_assig as D for 1997 is not available, intervention started in 1998)
dataset_1997_poor <- dataset %>% 
  filter(year == 1997 & pov_HH == 1)

# Variables of interest
variables_of_interest <- c("age_ind", "yycali", "ageHH", "eduHH", "age", 
                           "enroll_child", "sex", "lang", "sexHH", "uniqhh", "maxcut", "E")

# Initialize an empty data frame to store the results
results_df <- data.frame(Variable = character(), Mean_Assigned = numeric(), Mean_NotAssigned = numeric(),
                         Mean_Difference = numeric(), T_Statistic = numeric(), P_Value = numeric(), stringsAsFactors = FALSE)

# Loop through each variable of interest
for (var in variables_of_interest) {
  # Ensure the variable is numeric for the T-test
  if (is.numeric(dataset_1997_poor[[var]])) {
    # Calculate means for each group
    mean_assigned <- mean(dataset_1997_poor %>% filter(D_assig == 1) %>% pull(var), na.rm = TRUE)
    mean_notAssigned <- mean(dataset_1997_poor %>% filter(D_assig == 0) %>% pull(var), na.rm = TRUE)
    
    # Attempt to perform T-test, catching any errors
    t_test <- tryCatch({
      t.test(as.formula(paste(var, "~ D_assig")), data = dataset_1997_poor)
    }, error = function(e) {
      # Return NA values on error
      return(list(statistic = NA, p.value = NA))
    })
    
    # Calculate mean difference
    mean_difference <- mean_assigned - mean_notAssigned
    
    # Store the results
    results_df <- rbind(results_df, data.frame(Variable = var, Mean_Assigned = mean_assigned, 
                                               Mean_NotAssigned = mean_notAssigned, Mean_Difference = mean_difference,
                                               T_Statistic = ifelse(is.na(t_test$statistic), NA, t_test$statistic), 
                                               P_Value = ifelse(is.na(t_test$p.value), NA, t_test$p.value)))
  }
}

# Display the results
print(results_df)

################################################################################
# Program Compliance at Household level
# Step 1: Filter for households assigned to treatment in 1997
assigned_households <- dataset %>%
  filter(year == 1997 & D_assig == 1) %>%
  select(hogid) %>%
  distinct()

# Total households assigned to treatment in 1997
total_assigned <- nrow(assigned_households)

# Step 2: Check their participation status in 1998 and 1999
participation_status <- dataset %>%
  filter(hogid %in% assigned_households$hogid & year %in% c(1998, 1999)) %>%
  select(hogid, year, D_assig, D_HH) %>%
  distinct()

# Calculate compliance for each household by year
# A household is compliant if it was assigned to treatment (D_assig = 1) and participated (D_HH = 1)
compliance_by_household <- participation_status %>%
  mutate(Compliant = ifelse(D_assig == 1 & D_HH == 1, 1, 0)) %>%
  group_by(hogid) %>%
  summarise(Compliance_1998 = sum(Compliant & year == 1998),
            Compliance_1999 = sum(Compliant & year == 1999)) %>%
  ungroup()

# Calculate overall compliance and non-compliance rates
compliance_summary <- compliance_by_household %>%
  summarise(
    Total_Compliance_1998 = sum(Compliance_1998 > 0, na.rm = TRUE),
    Total_Compliance_1999 = sum(Compliance_1999 > 0, na.rm = TRUE),
    Percentage_Compliance_1998 = Total_Compliance_1998 / total_assigned * 100,
    Percentage_Compliance_1999 = ifelse(is.na(Total_Compliance_1999), 0, Total_Compliance_1999 / total_assigned * 100),
    Percentage_Non_Compliance_1998 = 100 - Percentage_Compliance_1998,
    Percentage_Non_Compliance_1999 = ifelse(is.na(Percentage_Compliance_1999), 100, 100 - Percentage_Compliance_1999)
  )

print(compliance_summary)

# Double manual check
# Total households assigned to treatment in 1997, ensuring uniqueness by hogid
total_assigned_1997 <- dataset %>%
  filter(year == 1997 & D_assig == 1) %>%
  select(hogid) %>%
  distinct() %>%
  nrow()
print(paste("Total households assigned to treatment in 1997:", total_assigned_1997))

# Total unique households in the dataset for years 1997, 1998, and 1999, reinforced by distinct hogid
total_households <- dataset %>%
  filter(year %in% c(1997, 1998, 1999)) %>%
  select(hogid) %>%
  distinct() %>%
  nrow()
print(paste("Total unique households in 1997, 1998, and 1999:", total_households))

################################################################################
# Part 2 Measuring Impact 
# Simple Differences 
# Filter the dataset for the year 1998 and for poor households 
dataset_1998_poor <- filter(dataset, year == 1998 & pov_HH == 1)

# Calculate the average enrollment rate for treatment and control groups
avg_enroll_treatment <- mean(dataset_1998_poor %>% filter(D_HH == 1) %>% pull(enroll_child), na.rm = TRUE)
avg_enroll_control <- mean(dataset_1998_poor %>% filter(D_HH == 0) %>% pull(enroll_child), na.rm = TRUE)

# Perform a T-test to determine if the difference is statistically significant
t_test_results <- t.test(enroll_child ~ D_HH, data = dataset_1998_poor)

# Print the average enrollment rates and T-test results
cat("Average enrollment rate in treatment villages (1998, poor households):", avg_enroll_treatment, "\n")
cat("Average enrollment rate in control villages (1998, poor households):", avg_enroll_control, "\n\n")
cat("T-test results:\n")
print(t_test_results)

# Repeat the same for 1999
# Filter the dataset for the year 1999 and for poor households
dataset_1999_poor <- filter(dataset, year == 1999 & pov_HH == 1)

# Calculate the average enrollment rate for treatment and control groups
avg_enroll_treatment_1999 <- mean(dataset_1999_poor %>% filter(D_HH == 1) %>% pull(enroll_child), na.rm = TRUE)
avg_enroll_control_1999 <- mean(dataset_1999_poor %>% filter(D_HH == 0) %>% pull(enroll_child), na.rm = TRUE)

# Perform a T-test to determine if the difference is statistically significant
t_test_results_1999 <- t.test(enroll_child ~ D_HH, data = dataset_1999_poor)

# Print the average enrollment rates and T-test results for 1999
cat("Average enrollment rate in treatment villages (1999, poor households):", avg_enroll_treatment_1999, "\n")
cat("Average enrollment rate in control villages (1999, poor households):", avg_enroll_control_1999, "\n\n")
cat("T-test results for 1999:\n")
print(t_test_results_1999)

################################################################################
# Simple Regression 
# Filter the dataset for the year 1998 and poor households 
dataset_1998_poor <- filter(dataset, year == 1998 & pov_HH == 1)

# Run the regression model for 1998
regression_1998 <- lm(enroll_child ~ D_HH, data = dataset_1998_poor)

# Display the summary of the regression model for 1998
summary(regression_1998)

# Repeat for year 1999
# Filter the dataset for the year 1999 and poor households
dataset_1999_poor <- filter(dataset, year == 1999 & pov_HH == 1)

# Run the regression model for 1999
regression_1999 <- lm(enroll_child ~ D_HH, data = dataset_1999_poor)

# Display the summary of the regression model for 1999
summary(regression_1999)

################################################################################
# Multiple Regression/ Conditioning
# Run the regression model for 1998 with control variables 
regression_1998_controls <- lm(enroll_child ~ D_HH + age_ind + sex + eduHH + yycali + lang, data = dataset_1998_poor)

# Display the summary of the regression model for 1998 with control variables
summary(regression_1998_controls)

# Repeat for year 1999
# Run the regression model for 1999 with control variables
regression_1999_controls <- lm(enroll_child ~ D_HH + age_ind + sex + eduHH + yycali + lang, data = dataset_1999_poor)

# Display the summary of the regression model for 1999 with control variables
summary(regression_1999_controls)

################################################################################
# Multiple Logistic Regression/ Conditioning
# Run the logistic regression model for 1998 with control variables 
logistic_regression_1998_controls <- glm(enroll_child ~ D_HH + age_ind + sex + eduHH + yycali + lang, data = dataset_1998_poor, family = binomial)

# Display the summary of the logistic regression model for 1998 with control variables
summary(logistic_regression_1998_controls)

# Repeat for year 1999
# Run the logistic regression model for 1999 with control variables
logistic_regression_1999_controls <- glm(enroll_child ~ D_HH + age_ind + sex + eduHH + yycali + lang, data = dataset_1999_poor, family = binomial)

# Display the summary of the logistic regression model for 1999 with control variables
summary(logistic_regression_1999_controls)

################################################################################
# IV Regression Using estimatr Package for Robust Standard Errors
# Robust IV regression for 1998 using D_assig as an instrument for D_HH
model_2sls_1998_robust <- iv_robust(
  formula = enroll_child ~ D_HH | D_assig,
  data = dataset_1998_poor
)

# Display the summary of the IV model for 1998
summary(model_2sls_1998_robust)

# Robust IV regression for 1999 using D_assig as an instrument for D
model_2sls_1999_robust <- iv_robust(
  formula = enroll_child ~ D_HH | D_assig,
  data = dataset_1999_poor
)

# Display the summary of the IV model for 1999
summary(model_2sls_1999_robust)

################################################################################
# Prepare the data for DiD
# Step 1: Create a new variable 'D_HH_assig' and initially set it identical to D_HH
dataset$D_HH_assig <- dataset$D_HH

# Step 2: Optionally, set 'D_HH_assig' to NA for 1997 only
dataset$D_HH_assig[dataset$year == 1997] <- NA

# Step 3: Summarize the 1998 treatment status for each household
treatment_status_1998 <- dataset %>%
  filter(year == 1998) %>%
  group_by(hogid) %>%
  summarize(D_HH_1998 = max(D_HH), .groups = 'drop')  # Ensure 'D_HH_1998' is created for each 'hogid'

# Verify the structure of 'treatment_status_1998'
print(head(treatment_status_1998))

# Step 4: Merge the 1998 treatment status back to the dataset for 1997 entries
dataset <- left_join(dataset, treatment_status_1998, by = "hogid")

# Verify that 'D_HH_1998' is present after join
print(head(dataset))

# Step 5: Use 'mutate' to assign the 1998 treatment status to 'D_HH_assig' for 1997 entries
dataset <- dataset %>%
  mutate(D_HH_assig = if_else(year == 1997, D_HH_1998, as.double(NA)))  # Use 'as.double(NA)' to ensure NA is treated as a numeric type

# Optional: Verify the assignment was successful
print(head(dataset[dataset$year == 1997, ]))

# Verify it worked correctly
# Count the number of households with D_HH = 1 in 1998
count_1998_treated <- dataset %>%
  filter(year == 1998, D_HH == 1) %>%
  distinct(hogid) %>%
  nrow()

print(count_1998_treated)

# Count the number of households with D_HH_assig = 1 for the year 1997
count_1997_assigned_treated <- dataset %>%
  filter(year == 1997, D_HH_assig == 1) %>%
  distinct(hogid) %>%
  nrow()

print(count_1997_assigned_treated)

# Randomly selected 10 households with their respective ID and checked manually if D_HH for 1998 corresponded to D_HH_assig for 1997

###############################################################################
# DiD Manual 
# Filtering for poor households in 1997 and excluding rows with NAs in relevant variables
dataset_1997_poor <- filter(dataset, year == 1997 & pov_HH == 1 & !is.na(enroll_child) & !is.na(D_HH_assig))

# Average enrollment rates for assigned treatment and control groups in 1997
avg_enroll_1997_assigned_treated <- mean(dataset_1997_poor$enroll_child[dataset_1997_poor$D_HH_assig == 1], na.rm = TRUE)
avg_enroll_1997_assigned_control <- mean(dataset_1997_poor$enroll_child[dataset_1997_poor$D_HH_assig == 0], na.rm = TRUE)

# Filtering for poor households in 1998 and excluding rows with NAs in relevant variables
dataset_1998_poor <- filter(dataset, year == 1998 & pov_HH == 1 & !is.na(enroll_child) & !is.na(D_HH))

# Average enrollment rates for treated and control groups in 1998
avg_enroll_1998_treated <- mean(dataset_1998_poor$enroll_child[dataset_1998_poor$D_HH == 1], na.rm = TRUE)
avg_enroll_1998_control <- mean(dataset_1998_poor$enroll_child[dataset_1998_poor$D_HH == 0], na.rm = TRUE)

# Calculating the differences in average enrollment rates from 1997 to 1998
diff_treated <- avg_enroll_1998_treated - avg_enroll_1997_assigned_treated
diff_control <- avg_enroll_1998_control - avg_enroll_1997_assigned_control

# Calculate the Difference-in-Differences estimate
DiD_estimate <- diff_treated - diff_control

# Output the results
cat("Difference in average enrollment rate (1997 to 1998) for treated households:", diff_treated, "\n")
cat("Difference in average enrollment rate (1997 to 1998) for control households:", diff_control, "\n")
cat("Difference-in-Differences estimate:", DiD_estimate, "\n")

################################################################################
# DiD Regression/Conditioning
# For 1997, use D_HH_assig as the treatment indicator and mark the year as T=0
dataset_1997_poor <- filter(dataset, year == 1997 & pov_HH == 1 & !is.na(enroll_child) & !is.na(D_HH_assig)) %>%
  mutate(T = 0, D_new = D_HH_assig)

# For 1998, use D_HH as the treatment indicator and mark the year as T=1
dataset_1998_poor <- filter(dataset, year == 1998 & pov_HH == 1 & !is.na(enroll_child) & !is.na(D_HH)) %>%
  mutate(T = 1, D_new = D_HH)

# Combine the datasets for 1997 and 1998
dataset_combined <- bind_rows(dataset_1997_poor, dataset_1998_poor)

# Run the DiD regression using the updated treatment and time variables, along with control variables
DiD_regression_model <- lm(enroll_child ~ D_new + T + D_new:T + age_ind + sex + eduHH + yycali + lang, data = dataset_combined)

# Display the summary of the regression model
summary(DiD_regression_model)





