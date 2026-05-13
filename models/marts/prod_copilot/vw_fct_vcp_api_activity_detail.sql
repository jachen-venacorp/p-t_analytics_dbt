{{ config(materialized='view') }}

WITH PROD_TENANT_INFO AS
(
select
tenant_id,
tenant_nm,
account_id,
data_cntr_cd
from PROD_HARMONIZED.PRODUCT.TENANT_PROF
where CRNT_RCRD_IND = 'Y'
and tenant_typ_nm in ('PRODUCTION')
and organization_typ_nm = 'CUSTOMER'
and tenant_enbld_status_nm = 'ENABLED'
),

user_info as 
(
    select
    tenant_dc,
    user_id,
    case when 
    (
    --vena employee login
    (login_email ilike '%@vena%.com' or ntfctn_email ilike '%@vena%.com') 
    --admin@ SSO account for consultants
    or (last_impersonation_login_dt is not null and admin_access_ind = 'Y' and login_email ilike 'admin@%' and login_email not ilike '%@vena%.com') or built_in_admin_accnt = 'Y'
    )
    then 'Y' else null end as consultant_login,
    case
    when admin_access_ind = 'Y' or mdlr_access_ind = 'Y' or mngr_access_ind = 'Y' then 'power user'
    when (admin_access_ind = 'N' and mdlr_access_ind = 'N' and mngr_access_ind = 'N' and cntrbtr_access_ind = 'Y') then 'business user'
    end as user_type
    from PROD_HARMONIZED.PRODUCT.VW_USER_PROF_EML_INCLD
    where crnt_rcrd_ind = 'Y'
    --and actvtn_status_nm = 'ACTIVE'
    order by user_id
)

select 
api.data_cntr_cd as vena_hub,
api.tenant_id,
tenant_nm,
api.user_id,
user_type as user_license_type,
consultant_login as is_user_consultant_or_support,
account_id as salesforce_account_id,
request_endpoint_nm as api_endpoint_name,
request_method_cd as post_or_get,
request_end_dts as action_timestamp,
--request_url,
client_context_hdr_nm as client_context_metadata,
--user_agent,
--filter to show what channel the action was done
case 
when (user_agent ilike '%teams%' or client_context_hdr_nm ilike '%teams%') then 'done through teams'
else 'done through web client'
end as msft_teams_or_web_client,

--filter to show if it was a prompt or not 
case 
when (request_method_cd = 'GET' AND request_endpoint_nm = '/api/ai/topics/{p}/conversations/{p}/messages/{p}/templateAdhoc/') then 'report generation message'
when (request_method_cd = 'POST' and request_endpoint_nm = '/api/ai/topics/') then 'AI model creation'
else 'prompting/question' end as interaction_type, 

/*
case 
    when ((user_agent ilike '%teams%' or client_context_hdr_nm ilike '%teams%') and (request_method_cd = 'GET' AND request_endpoint_nm =            '/api/ai/topics/{p}/conversations/{p}/messages/{p}/templateAdhoc/')) then 'report generation through MSFT teams'
    when ((user_agent not ilike '%teams%' or client_context_hdr_nm not ilike '%teams%') and (request_method_cd = 'GET' AND request_endpoint_nm =    '/api/ai/topics/{p}/conversations/{p}/messages/{p}/templateAdhoc/')) then 'report generation through web client'
    when ((user_agent ilike '%teams%' or client_context_hdr_nm ilike '%teams%') and (request_endpoint_nm ilike '%api/ai/topics/{p}/conversations/{p}/chat/%')) then 'prompts through MSFT teams'
    when ((user_agent not ilike '%teams%'  or client_context_hdr_nm not ilike '%teams%') and (request_endpoint_nm ilike '%api/ai/topics/{p}/conversations/{p}/chat/%')) then 'prompts through web client'
else null end as prompt_action_category,
*/

--filter to show what agent was used
case 
    when (request_method_cd = 'GET' AND request_endpoint_nm = '/api/ai/topics/{p}/conversations/{p}/messages/{p}/templateAdhoc/') then 'reporting agent'
    when (client_context_hdr_nm ilike '%mql_agent%' and request_endpoint_nm = '/api/ai/topics/{p}/conversations/{p}/chat/') then 'MQL agent prompt'
    when (client_context_hdr_nm ilike '%planning_agent%' and request_endpoint_nm = '/api/ai/topics/{p}/conversations/{p}/chat/') then 'Planning agent prompt'
else 'insights agent' end as copilot_agent_type

from PROD_HARMONIZED.PRODUCT.USER_API_ACTIVITY api
inner join prod_tenant_info on prod_tenant_info.tenant_id = api.tenant_id and prod_tenant_info.data_cntr_cd = api.data_cntr_cd
left join user_info on concat(api.data_cntr_cd,'.',api.tenant_id) = user_info.tenant_dc and api.user_id = user_info.user_id 
--left join user_info on api.tenant_id = right(user_info.tenant_dc,19) and api.user_id = user_info.user_id 

where 
to_date(request_end_dts) > ' 2024-02-01'
--general prompts
and ((request_endpoint_nm ilike '%api/ai/topics/{p}/conversations/{p}/chat/%')
--reporting agent
or (request_method_cd = 'GET' AND request_endpoint_nm = '/api/ai/topics/{p}/conversations/{p}/messages/{p}/templateAdhoc/')
-- model creation endpoint
or (request_method_cd = 'POST' and request_endpoint_nm = '/api/ai/topics/'))
and user_imprsntd_ind = 'N'
and request_status_cd = '200'