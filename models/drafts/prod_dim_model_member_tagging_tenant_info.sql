{{ config(materialized='table') }}

with source_data as (
    
with tenants as 
--simple prod tenants CTE
(
select
data_cntr_cd,
tenant_id,
account_id,
tenant_nm,
vena_copilot_exprtn_dts,
vena_copilot_num_of_paid_lic
from PROD_HARMONIZED.PRODUCT.TENANT_PROF
where CRNT_RCRD_IND = 'Y'
and tenant_typ_nm in ('PRODUCTION')
and organization_typ_nm = 'CUSTOMER'
and tenant_enbld_status_nm = 'ENABLED'
),

model_join as 
--required to check member count for a single model, cannot be across all models. Need to join via dim_id
(
select 
data_cntr_cd,
tenant_id,
model_id,
dim_id,
dim_typ_nm
from PROD_HARMONIZED.PRODUCT.MODEL_DIM_DTL
),

VCP_count as 
(
SELECT 
A.data_cntr_cd,
A.TENANT_ID,
tenant_nm,
model_join.model_id,
count(distinct std_member_mapping_typ) as members_satisfied_vcp
FROM PROD_HARMONIZED.PRODUCT.STANDARD_MEMBER_MAPPINGS A
left join model_join on model_join.data_cntr_cd = A.data_cntr_cd and model_join.tenant_id = A.tenant_id and model_join.dim_id = A.dim_id and model_join.dim_typ_nm = A.dim_typ
inner join tenants on A.tenant_id = tenants.tenant_id
WHERE STD_MEMBER_MAPPING_TYP IN 
(
'NET_INCOME', 
'REVENUE', 
'OPERATING_EXPENSES', 
'YEAR_2022', 
'YEAR_2023', 
'YEAR_2024', 
'FULL_YEAR', 
'JANUARY', 
'FEBRUARY', 
'MARCH', 
'APRIL', 
'MAY', 
'JUNE', 
'JULY', 
'AUGUST', 
'SEPTEMBER', 
'OCTOBER', 
'NOVEMBER', 'DECEMBER', 
'ACTUAL', 
'TOTAL_VALUE'
) 
group by 
A.data_cntr_cd,
A.TENANT_ID,
tenant_nm,
model_join.model_id
),

VCP_date as 
(
select distinct
vcp_count.data_cntr_cd,
vcp_count.TENANT_ID,
tenant_nm,
to_date(max(min_date)) as vcp_completion_date
from vcp_count 
inner join 
    (  
    select
    A.data_cntr_cd,
    A.TENANT_ID,
    model_join.model_id,
    std_member_mapping_id,
    min(etl_load_dts) as min_date
    FROM PROD_HARMONIZED.PRODUCT.STANDARD_MEMBER_MAPPINGS A
    left join model_join on model_join.data_cntr_cd = A.data_cntr_cd and model_join.tenant_id = A.tenant_id 
group by 
    A.data_cntr_cd,
    A.TENANT_ID,
    model_join.model_id,
    std_member_mapping_id
)member_min_dates
on vcp_count.tenant_id = member_min_dates.tenant_id and vcp_count.model_id = member_min_dates.model_id 
group by 
vcp_count.data_cntr_cd,
vcp_count.TENANT_ID,
tenant_nm,
members_satisfied_vcp
having members_satisfied_vcp = max(members_satisfied_vcp)
),

insights_count as 
(
SELECT 
A.data_cntr_cd,
A.TENANT_ID,
tenant_nm,
model_join.model_id,
count(distinct std_member_mapping_typ) as members_satisfied_insights
FROM PROD_HARMONIZED.PRODUCT.STANDARD_MEMBER_MAPPINGS A
left join model_join on model_join.data_cntr_cd = A.data_cntr_cd and model_join.tenant_id = A.tenant_id and model_join.dim_id = A.dim_id and model_join.dim_typ_nm = A.dim_typ
inner join tenants on A.tenant_id = tenants.tenant_id
WHERE STD_MEMBER_MAPPING_TYP IN 
(

'ALL_ENTITIES',
'ALL_DEPARTMENTS',
'REVENUE',
'NET_INCOME',
'COGS',
'ALL_YEARS',
'FULL_YEAR',
'JANUARY',
'FEBRUARY',
'MARCH',
'APRIL',
'MAY',
'JUNE',
'JULY',
'AUGUST',
'SEPTEMBER',
'OCTOBER',
'NOVEMBER',
'DECEMBER',
'ALL_SCENARIOS',
'TOTAL_VALUE',
'ALL_CURRENCIES',
'LOCAL'
--potential updated tags for insights
/*
'NET_INCOME',
'REVENUE',
'OPERATING_EXPENSES',
--'ALL_ENTITIES',
--'ALL_YEARS',
'FULL_YEAR',
'JANUARY',
'FEBRUARY',
'MARCH',
'APRIL',
'MAY',
'JUNE',
'JULY',
'AUGUST',
'SEPTEMBER',
'OCTOBER',
'NOVEMBER',
'DECEMBER',
'ALL_SCENARIOS',
'TOTAL_VALUE'
--'ALL_CURRENCIES',
--'LOCAL'--,
--'CASH',
--'CURRENT_LIABILITIES',
--'ACCOUNT_RECEIVABLE',
--'CURRENT_ASSETS',
--'ACCOUNT_PAYABLE',
--'ACCRUED_LIABILITIES'
*/
) 
group by 
A.data_cntr_cd,
A.TENANT_ID,
tenant_nm,
model_join.model_id
),

insights_date as 
(
select distinct
insights_count.data_cntr_cd,
insights_count.TENANT_ID,
tenant_nm,
to_date(max(min_date)) as insights_completion_date
from insights_count 
inner join 
    (  
    select
    A.data_cntr_cd,
    A.TENANT_ID,
    model_join.model_id,
    std_member_mapping_id,
    min(etl_load_dts) as min_date
    FROM PROD_HARMONIZED.PRODUCT.STANDARD_MEMBER_MAPPINGS A
    left join model_join on model_join.data_cntr_cd = A.data_cntr_cd and model_join.tenant_id = A.tenant_id 
group by 
    A.data_cntr_cd,
    A.TENANT_ID,
    model_join.model_id,
    std_member_mapping_id
)member_min_dates
on insights_count.tenant_id = member_min_dates.tenant_id and insights_count.model_id = member_min_dates.model_id 
group by 
insights_count.data_cntr_cd,
insights_count.TENANT_ID,
tenant_nm,
members_satisfied_insights
having members_satisfied_insights = max(members_satisfied_insights)
),

fx_count as 
(
SELECT 
A.data_cntr_cd,
A.TENANT_ID,
tenant_nm,
model_join.model_id,
count(distinct std_member_mapping_typ) as members_satisfied_fx
FROM PROD_HARMONIZED.PRODUCT.STANDARD_MEMBER_MAPPINGS A
left join model_join on model_join.data_cntr_cd = A.data_cntr_cd and model_join.tenant_id = A.tenant_id and model_join.dim_id = A.dim_id and model_join.dim_typ_nm = A.dim_typ
inner join tenants on A.tenant_id = tenants.tenant_id
WHERE STD_MEMBER_MAPPING_TYP IN 
(
'LOCAL',
'ALL_CURRENCIES',
'NET_INCOME',
'BALANCE_SHEET',
'OTHER_ACCOUNTS',
'ALL_YEARS',
'ALL_SCENARIOS',
'FULL_YEAR',
'OTHER_MEASURES',
'UNDEFINED'
) 
group by 
A.data_cntr_cd,
A.TENANT_ID,
tenant_nm,
model_join.model_id
),

fx_date as 
(
select distinct
fx_count.data_cntr_cd,
fx_count.TENANT_ID,
tenant_nm,
to_date(max(min_date)) as fx_completion_date
from fx_count 
inner join 
    (  
    select
    A.data_cntr_cd,
    A.TENANT_ID,
    model_join.model_id,
    std_member_mapping_id,
    min(etl_load_dts) as min_date
    FROM PROD_HARMONIZED.PRODUCT.STANDARD_MEMBER_MAPPINGS A
    left join model_join on model_join.data_cntr_cd = A.data_cntr_cd and model_join.tenant_id = A.tenant_id 
group by 
    A.data_cntr_cd,
    A.TENANT_ID,
    model_join.model_id,
    std_member_mapping_id
)member_min_dates
on fx_count.tenant_id = member_min_dates.tenant_id and fx_count.model_id = member_min_dates.model_id 
group by 
fx_count.data_cntr_cd,
fx_count.TENANT_ID,
tenant_nm,
members_satisfied_fx
having members_satisfied_fx = max(members_satisfied_fx)
),

tstudio_count as 
(
SELECT 
A.data_cntr_cd,
A.TENANT_ID,
tenant_nm,
model_join.model_id,
count(distinct std_member_mapping_typ) as members_satisfied_tstudio
FROM PROD_HARMONIZED.PRODUCT.STANDARD_MEMBER_MAPPINGS A
left join model_join on model_join.data_cntr_cd = A.data_cntr_cd and model_join.tenant_id = A.tenant_id and model_join.dim_id = A.dim_id and model_join.dim_typ_nm = A.dim_typ
inner join tenants on A.tenant_id = tenants.tenant_id
WHERE STD_MEMBER_MAPPING_TYP IN 
(
'ALL_ENTITIES',
'ALL_DEPARTMENTS',
'REVENUE',
'OPERATING_EXPENSES',
'COST_OF_GOODS_SOLD',
'ASSETS',
'LIABILITIES',
'EQUITY',
'JANUARY',
'FEBRUARY',
'MARCH',
'APRIL',
'MAY',
'JUNE',
'JULY',
'AUGUST',
'SEPTEMBER',
'OCTOBER',
'NOVEMBER',
'DECEMBER',
'ACTUAL',
'PLAN',
'LOCAL',
'TOTAL_VALUE',
'VALUE'
) 
group by 
A.data_cntr_cd,
A.TENANT_ID,
tenant_nm,
model_join.model_id
),

tstudio_date as 
(
select distinct
tstudio_count.data_cntr_cd,
tstudio_count.TENANT_ID,
tenant_nm,
to_date(max(min_date)) as tstudio_completion_date
from tstudio_count 
inner join 
    (  
    select
    A.data_cntr_cd,
    A.TENANT_ID,
    model_join.model_id,
    std_member_mapping_id,
    min(etl_load_dts) as min_date
    FROM PROD_HARMONIZED.PRODUCT.STANDARD_MEMBER_MAPPINGS A
    left join model_join on model_join.data_cntr_cd = A.data_cntr_cd and model_join.tenant_id = A.tenant_id 
group by 
    A.data_cntr_cd,
    A.TENANT_ID,
    model_join.model_id,
    std_member_mapping_id
)member_min_dates
on tstudio_count.tenant_id = member_min_dates.tenant_id and tstudio_count.model_id = member_min_dates.model_id 
group by 
tstudio_count.data_cntr_cd,
tstudio_count.TENANT_ID,
tenant_nm,
members_satisfied_tstudio
having members_satisfied_tstudio = max(members_satisfied_tstudio)
),

model_dim as
-- generic model stats across all customers
(
select 
data_cntr_cd,
tenant_id,
count(distinct model_id) no_models,
count(distinct dim_id) no_dimensions,
count(distinct pckg_id) no_packages,
count(dim_typ_nm) no_dimension_types_identified
from PROD_HARMONIZED.PRODUCT.MODEL_DIM_DTL
group by data_cntr_cd, tenant_id
),

members as 
-- generic member stats across all customers
(
select 
data_cntr_cd,
tenant_id,
count(distinct member_id) as no_members,
count(distinct member_typ_nm) as no_member_types_identified,
sum(chldrn_cnt) as total_children_count
from PROD_HARMONIZED.PRODUCT.DIM_MEMBER_DTL
group by
data_cntr_cd,
tenant_id
),

projects as 
-- generic kickoff dates for all customers
(
select 
ACCOUNT_ID,
min(go_live_dt) as go_live_dt
from PROD_PRESENTATION.PROFESSIONAL_SERVICES.VW_PS_PROJECTS
where account_id is not null 
and cohort_nm in ('Custom','Path','Path+')
and go_live_dt is not null 
group by ACCOUNT_ID
)

select 
tenants.data_cntr_cd,
tenants.tenant_id,
tenants.account_id,
tenants.tenant_nm,
vena_copilot_exprtn_dts,
vena_copilot_num_of_paid_lic,

--generic model stats
no_models,
no_dimensions,
no_dimension_types_identified,
no_packages,
no_members,
no_member_types_identified,
total_children_count,

--labels
case 
when ((max(members_satisfied_vcp) = 21) and (max(members_satisfied_insights) = 23) and (max(members_satisfied_tstudio) =25)) then 'Model tagging complete for all major features'
when ((max(members_satisfied_vcp) = 21) or (max(members_satisfied_insights) = 23) or (max(members_satisfied_tstudio) =25)) then 'At least one model tagged for major feature'
when (max(members_satisfied_fx) = 10) then 'only FX tags complete for a model'
else 'not a single model finished tagging' 
end as Tagging_completed,

--member tagging stats vcp 
go_live_dt,
case when
max(members_satisfied_vcp)/21 = 1 then vcp_completion_date else null end as vcp_completed_on,
max(members_satisfied_vcp) as no_members_under_copilot_requirement,
max(members_satisfied_vcp)/21 as percent_of_copilot_std_members_exist,

--member tagging stats insights 
case when
max(members_satisfied_insights)/23 = 1 then insights_completion_date else null end as insights_completed_on,
max(members_satisfied_insights) as no_members_under_insights_requirement,
max(members_satisfied_insights)/23 as percent_of_insights_std_members_exist,

--member tagging stats fx 
case when
max(members_satisfied_fx)/10 = 1 then fx_completion_date else null end as fx_completed_on,
max(members_satisfied_fx) as no_members_under_fx_requirement,
max(members_satisfied_fx)/10 as percent_of_fx_std_members_exist,

--member tagging stats tstudio 
case when
max(members_satisfied_tstudio)/25 = 1 then tstudio_completion_date else null end as tstudio_completed_on,
max(members_satisfied_tstudio) as no_members_under_tstudio_requirement,
max(members_satisfied_tstudio)/25 as percent_of_tstudio_std_members_exist,

--aggregate earliest tagging date
case  
when ((max(members_satisfied_vcp) = 21) or (max(members_satisfied_insights) = 23) or (max(members_satisfied_tstudio) =25))
then least(vcp_completion_date, insights_completion_date,tstudio_completion_date ) else null 
end as completed_atleast_one_major_tagging_on,

--aggregate earliest tagging date all customers
case  
when ((max(members_satisfied_vcp) = 21) and (max(members_satisfied_insights) = 23) and (max(members_satisfied_tstudio) =25))
then least(vcp_completion_date, insights_completion_date,tstudio_completion_date ) else null 
end as completed_all_major_tagging_on

from tenants
left join projects on tenants.account_id = left(projects.account_id,15)
left join model_dim on tenants.data_cntr_cd = model_dim.data_cntr_cd and tenants.tenant_id = model_dim.tenant_id
left join members on tenants.data_cntr_cd = members.data_cntr_cd and tenants.tenant_id = members.tenant_id
left join VCP_COUNT on tenants.data_cntr_cd = VCP_count.data_cntr_cd and tenants.tenant_id = VCP_count.tenant_id
left join VCP_date on tenants.data_cntr_cd = VCP_date.data_cntr_cd and tenants.tenant_id = VCP_date.tenant_id
left join INSIGHTS_COUNT on tenants.data_cntr_cd = insights_count.data_cntr_cd and tenants.tenant_id = insights_count.tenant_id
left join insights_date on tenants.data_cntr_cd = insights_date.data_cntr_cd and tenants.tenant_id = insights_date.tenant_id
left join fx_date on tenants.data_cntr_cd = fx_date.data_cntr_cd and tenants.tenant_id = fx_date.tenant_id
left join fx_count on tenants.data_cntr_cd = fx_count.data_cntr_cd and tenants.tenant_id = fx_count.tenant_id
left join tstudio_date on tenants.data_cntr_cd = tstudio_date.data_cntr_cd and tenants.tenant_id = tstudio_date.tenant_id
left join tstudio_count on tenants.data_cntr_cd = tstudio_count.data_cntr_cd and tenants.tenant_id = tstudio_count.tenant_id
group by 
tenants.data_cntr_cd,
tenants.tenant_id,
tenants.account_id,
tenants.tenant_nm,
vena_copilot_exprtn_dts,
vena_copilot_num_of_paid_lic,
no_models,
no_dimensions,
no_dimension_types_identified,
no_packages,
no_members,
no_member_types_identified,
total_children_count,
go_live_dt,
vcp_completion_date,
insights_completion_date,
fx_completion_date,
tstudio_completion_date

)

select *
from source_data

