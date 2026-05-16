--user activation cte
--PS cte to show go live and EMS toggle
-- SSO CTE necessary?
-- model info?
-- feature yes/no booleans
-- CHS and churn probability 

{{ config(materialized='view') }}

with acct as 
(
select*
from PROD_HARMONIZED.SALES.VW_ACCOUNT_PROF
where crnt_rcrd_ind = 'Y'
),

user_summary as (
select
    tenant_dc,
    count(distinct user_id) as total_users_enabled,
    count(distinct(case when copilot_access_ind = 'Y' then user_id else null end)) as total_VCP_users_enabled,
    count(distinct(case when (admin_access_ind = 'Y' or mdlr_access_ind = 'Y' or mngr_access_ind = 'Y') then user_id else null end)) as no_power_users,
    count(distinct(case when ((admin_access_ind = 'Y' or mdlr_access_ind = 'Y' or mngr_access_ind = 'Y') and (copilot_access_ind = 'Y')) then user_id else null end)) 
    as no_VCP_power_users,
    count(distinct(case when (admin_access_ind = 'N' and mdlr_access_ind = 'N' and mngr_access_ind = 'N' and cntrbtr_access_ind = 'Y')then user_id else null end)) as no_business_users,
    count(distinct(case when (admin_access_ind = 'N' and mdlr_access_ind = 'N' and mngr_access_ind = 'N' and cntrbtr_access_ind = 'Y' and copilot_access_ind =      
    'Y')then user_id else null end)) as no_VCP_business_users,
    count(distinct(case when viewer_access_ind = 'Y' then user_id else null end)) as no_view_only,
    count(distinct(case when (admin_access_ind = 'N' and mdlr_access_ind = 'N' and mngr_access_ind = 'N' and cntrbtr_access_ind = 'N' and dshbrdr_access_ind = 'Y') then user_id else null end)) as no_dashboarder_only
    from PROD_HARMONIZED.PRODUCT.VW_USER_PROF_EML_INCLD
    where crnt_rcrd_ind = 'Y'
    and actvtn_status_nm = 'ACTIVE'
    and 
   --employee logins
    (login_email not ilike '%@vena%.com' or ntfctn_email not ilike '%@vena%.com') 
    and
    built_in_admin_accnt = 'N'
    group by tenant_dc
),

settings as 
(
select 
data_cntr_cd,
tenant_id,
sso_enbld_ind,
data_prmsns_ind,
two_fa_auth_enbld_ind,
two_fa_auth_admin_cntrld_ind,
auth0_org_id,
auth0_integration_stts
from PROD_HARMONIZED.PRODUCT.TENANT_PROF
where crnt_rcrd_ind = 'Y'
),

ps_projects as 
(
select 
account_id,
count(distinct(case when cohort_nm in ('Expert Services','Expert Services+') and CURRENT_EMS_SERVICE_IND
= 'Y' and project_status_nm <> 'Cancelled' then vena_project_cd else null end))as total_ems_projects,
min(case when cohort_nm in ('Path','Path+','Custom') and project_status_nm <> 'Cancelled' then project_close_dt else null end) as implementation_go_live_dt 
from PROD_PRESENTATION.PROFESSIONAL_SERVICES.VW_PS_PROJECTS
where crnt_rcrd_ind = 'Y'
group by account_id 
),

login_type as 
(
select 
base.data_cntr_cd,
base.tenant_id,
count(distinct(case when request_endpoint_nm = '/login/' and query_string='origin=webclient' then base.user_id else null end)) as normal_login_unique_users,
count(distinct(case when request_endpoint_nm = '/auth/saml/' then base.user_id else null end)) as SSO_login_unique_users,
count(distinct(case when request_endpoint_nm = '/login/twoauth/' then base.user_id else null end)) as MFA_login_unique_users,
from prod_harmonized.product.user_api_activity base 
inner join 
(
select 
data_cntr_cd,
tenant_id,
user_id,
max (request_end_dts) as maxdate 
from prod_harmonized.product.user_api_activity 
where ((request_endpoint_nm = '/login/' and query_string='origin=webclient') 
or request_endpoint_nm='/auth/saml/' or request_endpoint_nm = '/login/twoauth/')
and user_agent like 'Mozilla%'
and request_status_cd < 400
and to_date(request_start_dts) >= '2025-02-01'
group by 
data_cntr_cd,
tenant_id,
user_id
)maxdate 
on maxdate.data_cntr_cd = base.data_cntr_cd and maxdate.tenant_id = base.tenant_id and maxdate.user_id = base.user_id and maxdate.maxdate = base.request_end_dts
where ((request_endpoint_nm = '/login/' and query_string='origin=webclient') 
or request_endpoint_nm='/auth/saml/' or request_endpoint_nm = '/login/twoauth/')
and user_agent like 'Mozilla%'
and request_status_cd < 400
and to_date(request_start_dts) >= '2025-02-01'
group by 
base.data_cntr_cd,
base.tenant_id
)

select 
dc_tenant_id as vena_hub_tenant_id,
prod.data_cntr_cd as vena_hub,
tenant_nm as tenant_name,
prod.account_id as salesforce_account_id,
prod.account_nm as salesforce_account_name,
account_owner_nm as account_manager_name,
account_chrn_rsk as salesforce_csm_listed_churn_risk,
arr_usd,
became_customer_dt as date_became_customer,
renewal_dt as date_of_renewal,
territory_sgmnt_nm as vena_sales_territory_name,
zoom_indstry_nm as zoominfo_industry_name,
powerbi_embedded_ind as vena_insights_indicator,
admin_license_sold as power_user_licenses_sold,
business_license_sold as business_licenses_sold,
any_combination_license_sold,
view_only_license_sold,
total_license_sold,
total_users_enabled,
total_VCP_users_enabled,
no_power_users,
no_VCP_power_users,
no_business_users,
no_VCP_business_users,
no_view_only as no_view_only_users_enabled,
no_dashboarder_only as no_dashboarder_users_enabled,
sso_enbld_ind as sso_enabled,
data_prmsns_ind as data_permissions_enabled,
two_fa_auth_enbld_ind as two_factor_authentication_enabled,
two_fa_auth_admin_cntrld_ind as two_factor_authentication_enabled_by_admin_controls,
auth0_org_id as auth_zero_org_id,
auth0_integration_stts as auth_zero_integration_status,
normal_login_unique_users,
SSO_login_unique_users,
MFA_login_unique_users,
total_ems_projects,
implementation_go_live_dt as implementation_go_live_date
from PROD_HARMONIZED.PRODUCT.VW_ENBLD_PRODUCTION_TENANTS prod 
left join login_type on login_type.data_cntr_cd = prod.data_cntr_cd and login_type.tenant_id = prod.tenant_id 
left join acct on prod.account_id = acct.account_id
left join ps_projects on ps_projects.account_id = prod.account_id 
left join settings on settings.data_Cntr_cd = prod.data_cntr_cd and settings.tenant_id = prod.tenant_id 
left join user_summary on user_summary.tenant_dc = prod.dc_tenant_id 
where tenant_enbld_status_nm = 'ENABLED'
and tenant_typ_nm = 'PRODUCTION'
and prod.account_typ_nm = 'Customer'
