#-------#
# Setup #
#-------#

# Install and load pacman if not already installed
if (!require("pacman")) install.packages("pacman")
library(pacman)

p_load(tidyverse, #general cleaning and piping
       stringr, #string manipulation
       lubridate, #I hate dates
       purrr,#nifty not_in function
       DataExplorer, #check missings
       ggplot2,plotly, #gen viz
       sf,mapview) #maps
`%not_in%` <- purrr::negate(`%in%`)
#population data from github - fresh up to 2016
#pop <- read_csv("https://raw.githubusercontent.com/datasets/population/master/data/population.csv")
#pop %<>% group_by(`Country Name`) %>% filter(Year == max(Year)) %>% ungroup()


#population data from 2018!
pop <- read_csv("explore_covid/data/2018_world_population_data_worldbank.csv", skip = 4)
pop %<>% select(`Country Name`,"2018")
#function to  combine all the files
source("explore_covid/files_combine_fun.R")

covid <- combine(directory)

#################################################################################################
#CLEAN-UP

covid_df <- covid %>% 
  mutate(province_state = ifelse(is.na(`Province/State`),Province_State,`Province/State`),
         province_state = as_factor(province_state),
         country_region = ifelse(is.na(`Country/Region`),Country_Region,`Country/Region`),
         country_region = as_factor(country_region),
         lat = ifelse(is.na(Lat),Latitude,Lat),
         lon = ifelse(is.na(Long_),Longitude,Long_),
         date = str_extract(path,"[:digit:]{2}-{1}[:digit:]{2}.+.csv$") %>% str_remove(".csv"),
         date = as.Date(date,'%m-%d-%Y')
         ) %>%
  select(-`Province/State`,-Province_State,-`Country/Region`,-Country_Region,
         -Lat,-Latitude,-Long_,-Longitude,-`Last Update`,-Last_Update,-path,
         -Admin2,-FIPS,-Combined_Key) %>%
  mutate_all(stringr::str_trim) %>%
  rename(confirmed = "Confirmed",
         recovered = "Recovered",
         deaths = "Deaths",
         active = "Active") %>% 
  mutate_at(vars("confirmed","recovered","deaths","active","lat","lon"),.funs = as.numeric) %>% 
  mutate(#confirmed = zoo::na.locf(confirmed, fromLast = TRUE),
         #recovered = zoo::na.locf(recovered, fromLast = TRUE),
         confirmed = replace_na(confirmed,0),
         recovered = replace_na(recovered,0),
         deaths = replace_na(deaths,0),
         active = replace_na(active,0)) %>%
  mutate(confirmed = abs(as.numeric(confirmed)),
         recovered = abs(as.numeric(recovered)),
         deaths = abs(as.numeric(deaths)),
         new_confirmed = confirmed - lag(confirmed, default=0),
         new_recovered = recovered - lag(recovered, default=0),
         new_deaths = deaths - lag(deaths, default=0)) %>%
  group_by(country_region,province_state,date) %>%
  mutate(total_infect = sum(confirmed,recovered,deaths),
         deaths_rate = (sum(deaths)/total_infect)*100,
         deaths_rate = ifelse(is.nan(deaths_rate),0,deaths_rate)) %>%
  ungroup() %>%
  #This can be useful to make a way to display dates on axis my month and year
         #date_day = str_extract(date,"[:digit:][:digit:]$"),
         #date_mon = format(as.Date(.$date,format="%Y-%m-%d"), format = "%b")) %>%
  arrange(date) %>%
  ##city clean-up for lat and lon
mutate(lat = case_when(country_region == "Ivory Coast" ~ 7.5400,
          province_state == "Ashland, NE" ~ 43.9654,
          TRUE ~ lat),
       lon = case_when(country_region == "Ivory Coast" ~ 5.5471,
          province_state == "Ashland, NE" ~ 70.8227,
          TRUE ~ lon),
        province_state = case_when(province_state == "Chicago" ~ "Chicago, IL",
                                    province_state == "Bavaria" ~ NA_character_,
                                    province_state == "None" ~ NA_character_,
                                    province_state == "From Diamond Princess" & country_region == "Israel" ~ NA_character_,
                                    (is.na(province_state) | province_state == "Jervis Bay Territory" | province_state == "External territories")& country_region == "Australia" ~ "Australian Capital Territory",
                                    province_state == "Ashland, NE" ~ "New England",
                                    province_state == "Lackland, TX" ~ "Texas",
                                    province_state == "Travis, CA" | province_state == "Cruise Ship" ~ "California",
                                    TRUE ~ province_state),
         country_region = case_when(str_detect(country_region,"Ireland") ~ "Ireland",
                                    #fix cruise ships
                                    province_state == "California" & country_region == "Others" ~ "US",
                                    str_detect(country_region,"Congo") ~ "Congo",
                                    str_detect(country_region,"China") ~ "China",
                                    str_detect(country_region,"Korea") ~ "Korea",
                                    country_region %in% c("Ivory Coast","Central African Republic","South Africa") ~ "Africa",
                                    str_detect(country_region,"Iran") ~ "Iran",
                                    str_detect(country_region,"Taiwan") ~ "Taiwan",
                                    country_region == "UK" ~ "United Kingdom",
                                    country_region == "Viet Nam" ~ "Vietnam",
                                    country_region == "Russian Federation" ~ "Russia",
                                    TRUE ~ country_region),
       date = as_date(date)
    ) %>%
  #Unable to determine origin locations for cruise ships, going to not include these for right now
  filter(country_region %not_in% c("Cruise Ship","Diamond Princess")) 
#fix the blank lat and lon
lat_lon <- covid_df %>%
  select(province_state,country_region,lat,lon) %>%
  filter(!is.na(lat) & !is.na(lon)) %>%
  rename(lat2 = "lat",
         lon2 = "lon") %>%
  distinct()

covid_df %<>% 
  plyr::join(lat_lon,type = "left", by = c("province_state","country_region"),match = "first") %>%
  mutate(lat = ifelse(is.na(lat),lat2,lat),
         lon = ifelse(is.na(lon),lon2,lon)) %>%
  select(-lat2,-lon2)


#rm(covid)
##########################################################################################
#
# DATA EXPLORATION
#
#covid_df %>% GGally::ggcorr()
#covid_df %>% DataExplorer::plot_missing()
# 
# ggplot(covid_df, aes(x = date, y = cases)) + 
#   geom_point(stat="identity",aes(color = type), size = 2) +
#   scale_color_manual(values = c("#00AFBB", "#E7B800","#FC4E07")) +
#   ggtitle("COVID-19") +
#   theme(axis.text.x = element_text(angle = 90),
#         )

########################################################################################
#
# Add in some popuation data
#fix annoying names
names(pop) = str_replace_all(names(pop)," ","_")
names(pop) = str_to_lower(names(pop))

pop_df <- pop %>%
  mutate(
    country_name = case_when(
      str_detect(country_name,"Congo") ~ "Congo",
      str_detect(country_name,"China") ~ "China",
      str_detect(country_name,"Korea") ~ "Korea",
      country_name %in% c("Sub-Saharan Africa","Central African Republic","South Africa") ~ "Africa",
      country_name == "South Sudan" ~ "Sudan",
      country_name == "Egypt, Arab Rep." ~ "Egypt",
      country_name == "Kyrgyz Republic" ~ "Kyrgyzstan",
      country_name %in% c("Virgin Islands (U.S.)","United States") ~ "US",
      country_name == "Syrian Arab Republic" ~ "Syria",
      str_detect(country_name,"Iran") ~ "Iran",
      country_name == "Venezuela, RB" ~ "Venezuela",
      country_name == "Slovak Republic" ~ "Slovakia",
      country_name == "St. Vincent and the Grenadines" ~ "Saint Vincent and the Grenadines",
      country_name == "St. Kitts and Nevis" ~ "Saint Kitts and Nevis",
      country_name == "St. Martin (French part)" ~ "Saint Martin",
      country_name == "Sint Maarten (Dutch part)" ~ "Saint Martin",
      country_name == "St. Lucia" ~ "Saint Lucia",
      TRUE ~ country_name
    )
  ) %>%
  filter(country_name %not_in% c(
    "Arab World",
    "Central Europe and the Baltics",
    "Early-demographic dividend",
    "East Asia & Pacific",
    "East Asia & Pacific (excluding high income)",
    "East Asia & Pacific (IDA & IBRD countries)",
    "Euro area",
    "Europe & Central Asia",
    "Europe & Central Asia (excluding high income)",
    "Europe & Central Asia (IDA & IBRD countries)",
    "European Union",
    "Fragile and conflict affected situations",
    "Heavily indebted poor countries (HIPC)",
    "High income",
    "IBRD only",
    "IDA & IBRD total",
    "IDA blend",
    "IDA only",
    "IDA total",
    "Lao PDR",
    "Late-demographic dividend",
    "Latin America & Caribbean",
    "Latin America & Caribbean (excluding high income)",
    "Latin America & the Caribbean (IDA & IBRD countries)",
    "Least developed countries: UN classification",
    "Low & middle income",
    "Low income",
    "Lower middle income",
    "Middle East & North Africa",
    "Middle East & North Africa (excluding high income)",
    "Middle East & North Africa (IDA & IBRD countries)",
    "Middle income",
    "North America",
    "Not classified",
    "OECD members",
    "Other small states",
    "Post-demographic dividend",
    "Pre-demographic dividend",
    "Small states",
    "South Asia",
    "South Asia (IDA & IBRD)",
    "Sub-Saharan Africa (excluding high ncome)",
    "Sub-Saharan Africa (IDA & IBRD countries)",
    "Upper middle income"
  ))

## NOTE: Left in World in case it is interesting later

########################################################################################################
#CLEAN POP_DF and COVID_DF for join
#
#use the frames below to review and fix pop_df and covid_df iteratively
##until ok with what is left being left out or grouped as 'other'
##the biggest thing is weeding through the summary values also included in that data set (e.g. European Union vs. countries within)
#
#list all pop regions for reference
# pop_name <-  pop_df %>% select(country_name) %>% distinct() %>% arrange(country_name)
# 
# #find out where the countries need match, ~100 do not match
# pop_no_match <- pop_df %>% #these  don't match
#   select(country_name) %>%
#   distinct() %>%
#   anti_join(covid_df, by = c("country_name" = "country_region"))
# 
# #what does match?
# pop_match <- pop_df %>%
#   select(country_name) %>%
#   distinct() %>%
#   anti_join(pop_no_match, by = "country_name")
# 
# #list all for reference
# covid_name <-  covid_df %>% select(country_region) %>% distinct() %>% arrange(country_region)
#   
# #covid no match
# covid_no_match <-  covid_name %>%
#   anti_join(pop_name, by = c("country_region" = "country_name"))
# 
# #covid yes match
# covid_match <-  covid_name %>%
#   anti_join(covid_no_match, by = c("country_region"))
# 
# rm(list = c("pop_name","pop_no_match","pop_match","covid_name","covid_no_match","covid_match"))

########################################################################################################
#
# Pop and Covid Joins - inner 
#
names(pop_df) = c("country_name","country_pop_2018")
pop_df %<>%
  group_by(country_name) %>%
  summarise(country_pop2018 = sum(country_pop_2018)) %>%
  ungroup()
  
covid_ctry_date <-  covid_df %>% 
  select(country_region,date) %>% 
  distinct() %>% 
  arrange(date,country_region) %>%
  group_by(country_region) %>%
  mutate(         #make var to identify days of virus since countries started at different times to compare spread rates
    day_virus = row_number())
#we can do mapping by region, but population is only to country (labeled as such)
covid_pop_df <- 
  covid_df %>% inner_join(pop_df, by = c("country_region" = "country_name")) %>%
  group_by(country_region, date) %>% 
  mutate(perc_ctry_cnfrm = round((sum(confirmed)/country_pop2018)*100,8) %>% as.numeric() %>% format(scientific = F),
         perc_ctry_rcvrd = round((sum(recovered)/country_pop2018)*100,8) %>% as.numeric() %>% format(scientific = F),
         perc_ctry_dead = round((sum(deaths)/country_pop2018)*100,8) %>% as.numeric() %>% format(scientific = F),
         perc_pop_infect = round((total_infect/country_pop2018)*100,8) %>% as.numeric() %>% format(scientific = F)) %>%
  ungroup() %>%
  left_join(covid_ctry_date, by = c("country_region","date")) %>%
  distinct() #%>%
  #gather(case_type,n_cases,confirmed:recovered) %>%
  #mutate(n_cases = as.numeric(n_cases))
feather::write_feather(covid_pop_df,"explore_covid/data/covid_pop.feather")
write_csv(covid_pop_df,"explore_covid/data/covid_pop.csv")


# - DRAFTS ONLY - need tweaked for each use - (e.g. gathered above vs of below etc. )
########################################################################################################
# Get some ideas for visuals
########################################################################################################

#######################################################################################################
# case type vs date

fun_bar <- function(df,x_var,y_var,color_var,color_varName,stacked=T,horizontal=F,...) {
  
  library(magrittr)
  plot_ly(
    x = ~x_var,
    y = ~y_var,
    color = ~as.character(color_var),
    colors = colorRamp(list("blue2","green3","red"))
    
  ) %>%
    add_bars() %>%
    layout(
      barmode = ifelse(stacked,'stack','group'),
      orientation = ifelse(horizontal,'h','v'),    
      title = paste0("COVID-19 Cases by ",color_varName," (Cumulative)"),
      xaxis = list(title = "Date", tickangle = 45),
      yaxis = list(title = "Cases")
    )
}

covid_v1 <- covid_df %>% 
  gather(case_type,n_cases,confirmed:recovered) %>%
  mutate(n_cases = as.numeric(n_cases)) %>%
  group_by(date,case_type) %>%
  #filter(country_region == "US") %>%
  summarise(n_cases = sum(n_cases)) %>%
  distinct()


fun_bar(covid_v1,covid_v1$date,covid_v1$n_cases,covid_v1$case_type,"Date",stacked = F)



#######################################################################################################
# perc pop  - latest date

fun_bar3 <- function(df,x_var,y_var,color_var,color_varName,stacked=T,horizontal=F,...) {
  
  library(magrittr)
  plot_ly(
    x = ~x_var,
    y = ~y_var,
    color = ~as.character(color_var),
    colors = c("blue2","red","green2","yellow")
  ) %>%
    add_bars() %>%
    layout(
      barmode = ifelse(stacked,'stack','group'),
      orientation = ifelse(horizontal,'h','v'),    
      title = paste0("COVID-19 by ",color_varName),
      xaxis = list(title = "", tickangle = 45),
      yaxis = list(title = "Percent")
    )
}

covid_pop_v2 <- covid_pop_df %>% group_by(country_region,day_virus) %>%  gather(case_type,perc_cases,perc_ctry_cnfrm:perc_pop_infect) %>% 
  select(country_region, day_virus,perc_cases,case_type) %>% 
  filter(country_region %in% c("US","Italy","China","Germany")) %>% 
  mutate(perc_cases = as.numeric(perc_cases)) %>%
  group_by(country_region) %>%
  filter(day_virus == max(day_virus)) %>%
  distinct()

fun_bar3(covid_pop_v2,covid_pop_v2$country_region,covid_pop_v2$perc_cases,covid_pop_v2$case_type,"% of Country Population (2018)",stacked = F)


#######################################################################################################
# MAPS MAPS MAPS
#######################################################################################################

#######################################################################################################
# map of confirmed status vs time - this could be a neat viz to have slider bar for in shiny
map_pop <- covid_pop_df %>% select(country_region,province_state,perc_pop_infect,lat,lon) %>% distinct()
sf_covid_pop <- st_as_sf(map_pop, coords = c("lon", "lat"), crs = 4326)
#set the color palette
mapviewOptions(vector.palette =  viridis::inferno)
#map with sizes and locations colored by reason buckets
mapview(sf_covid_pop, legend = F, alpha = 0, burst = T, 
        width = "2500", align = "center", cex = "perc_pop_infect", 
        map.types = c("CartoDB.DarkMatter","CartoDB.Positron","OpenStreetMap","Esri.WorldImagery","OpenTopoMap"))

#######################################################################################################
# What order did the virus hit other countries?
#ok this is scary too, could be cool to render by day
covid_routes <- covid_pop_df %>%
  filter(day_virus == 1) %>% #day 1 would be the first day the virus landed in a country
  select(country_region,day_virus,lat,lon) %>% 
  group_by(country_region) %>%
  mutate(lat = mean(lat),
         lon = mean(lon)) %>%
  distinct() %>% 
  ungroup() %>%
  mutate(from_lat = lat,
         to_lat = lead(from_lat,1),
         from_lon = lon,
         to_lon = lead(lon,1),
        #jitter slightly so that not identical for route map
         from_lat = jitter(from_lat, factor = 0.1),
         from_lon = jitter(from_lon, factor = 0.1),
         to_lat = jitter(to_lat, factor = 0.1),
         to_lon = jitter(to_lon, factor = 0.1))

#https://rstudio-pubs-static.s3.amazonaws.com/259095_2f8cb24b43284692a8af916bd447931d.html
map_setup <- borders("world", colour="grey80", fill="grey3")
virus_travel <- ggplot() + map_setup +
  geom_curve(data=covid_routes,
             aes(x=from_lon, y=from_lat, xend=to_lon, yend=to_lat),
             col="orangered4",
             size=.5,
             curvature=0.2) +
  geom_point(data=covid_routes,
             aes(x=from_lon, y=from_lat), 
             colour="orangered2",
             size=1.5) +
  geom_point(data=covid_routes,
             aes(x=to_lon, y=to_lat), 
             colour="orangered2") +
  theme(axis.line=element_blank(),
        axis.text.x=element_blank(),
        axis.text.y=element_blank(),
        axis.title.x=element_blank(),
        axis.title.y=element_blank(),
        axis.ticks=element_blank(),
        plot.title=element_text(hjust=0.5, size=12)) +
  ggtitle("COVID-19 Routes for First Appearances in Each Country")# +
  #check the min/max of long and lat to get good zoom level if needed or leave out
  #coord_cartesian(ylim=c(10, 75), xlim=c(-160, 70))
virus_travel


########################################################################################################
# glm_us <- glm2::glm2(covid_pop_v1$day_virus ~ covid_pop_v1$n_cases)
# summary(glm_us)
# plot(glm_us)










 