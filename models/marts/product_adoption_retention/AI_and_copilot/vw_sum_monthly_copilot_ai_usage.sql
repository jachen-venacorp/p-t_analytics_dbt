{{ config(materialized='view') }}

/*
with prod_tenant_info as
(
    select
    data_cntr_cd,
    tenant_id,
    tenant_nm,
    account_id,
    from PROD_HARMONIZED.product.tenant_prof
    where tenant_typ_nm = 'PRODUCTION' --and tenant_enbld_status_nm = 'ENABLED'
    and organization_typ_nm = 'CUSTOMER'
    and crnt_rcrd_ind = 'Y'
 
),

user_info as 
(
    select
    concat(data_cntr_cd,'.',tenant_id) tenant_dc,
    user_id,
    case when 
    (
    --vena employee login
    (login_email ilike '%@vena%.com' or ntfctn_email ilike '%@vena%.com') 
    --admin@ SSO account for consultants
    or (last_impersonation_login_dt is not null and admin_access_ind = 'Y' and login_email ilike 'admin@%' and login_email not ilike '%@vena%.com') 
    )
    then 'Y' else null end as consultant_login,
    case
    when admin_access_ind = 'Y' or mdlr_access_ind = 'Y' or mngr_access_ind = 'Y' then 'power user'
    when (admin_access_ind = 'N' and mdlr_access_ind = 'N' and mngr_access_ind = 'N' and cntrbtr_access_ind = 'Y') then 'business user'
    end as user_type
    from PROD_HARMONIZED.product.user_prof
    where crnt_rcrd_ind = 'Y'
    --and actvtn_status_nm = 'ACTIVE'
    order by user_id
)

select 
last_day(request_end_dts) as end_of_month,
count(distinct api.tenant_id) as unique_tenant_count,
count(distinct api.user_id) as unique_customer_users,
count(request_end_dts) as no_of_questions_asked
from PROD_HARMONIZED.product.user_api_activity api
inner join prod_tenant_info on prod_tenant_info.tenant_id = api.tenant_id and prod_tenant_info.data_cntr_cd = api.data_cntr_cd
left join user_info on concat(api.data_cntr_cd,'.',api.tenant_id) = user_info.tenant_dc and api.user_id = user_info.user_id 
--left join __dbt__cte__stg_accounts_all_fields as acc on left(prod_tenant_info.account_id,15) = left(acc.id,15) 
where request_endpoint_nm ilike '%api/ai/topics/{p}/conversations/{p}/chat/%'
and request_status_cd = '200'
and user_imprsntd_ind = 'N' 
-- added on Apr 07 2026 to remove demo tenants refer #INC-21666
and not (
       coalesce(tenant_nm, '') ilike '%sparkcycle%'
    or coalesce(tenant_nm, '') ilike '%spark cycle%'
    or coalesce(tenant_nm, '') ilike '%demo%'
)
group by last_day(request_end_dts)
  );
  */
/*
  {{ config(
    materialized = 'view'
) }}
*/

/* =========================================================================
   GRAIN:
   - One row per month, focused on prompt volume and targets

   Business Adjustments:
   - FY27 Excelerate (May 2026) demo tenant prompts injected
   - MCP estimated prompts injected via gaps-and-islands methodology

  Data Quality
  - fct table reference includes everything not just prompts, some things may flow through
  - need to include both "prompting" and "report generation", results in some edge cases like digital publishing AG where they dont have any prompts but somehow hit the report gen endpoint 
  - will have slight gaps against old logic but should be basically identical 
    - current version will understate prompts and users bc of stricter filters to remove vena employees
    - current version will overstate tenants possibly due to edge cases with reporting agent 
  
  NOTES:
   - MCP prompts are estimated by clustering API calls occurring within
     5 seconds of each other
   - not_customer_user = TRUE when either:
       - API call was impersonated
       - User is identified as consultant/support/internal
======================================================================== */

SELECT
    LAST_DAY(action_timestamp::DATE) AS end_of_month,

    COUNT(DISTINCT vh_tenant_id) AS unique_tenant_count,

    COUNT(DISTINCT CONCAT(vh_tenant_id, '.', user_id)) AS unique_customer_users,

    COUNT_IF(interaction_type = 'prompting/question') AS no_of_questions_asked,

    COUNT_IF(
        interaction_type = 'prompting/question'
        AND copilot_agent_type = 'Planning agent prompt'
    ) AS no_of_planning_agent_prompts,

       COUNT_IF(
        interaction_type = 'prompting/question'
        AND copilot_agent_type = 'MQL agent prompt'
    ) AS no_of_query_agent_prompts,

    COUNT_IF(
        interaction_type = 'prompting/question'
        AND copilot_agent_type = 'MCP server'
    ) AS no_of_mcp_prompts,

    COUNT_IF(  copilot_agent_type = 'reporting agent'
    ) AS no_of_reporting_agent_prompts,

    COUNT_IF(
        interaction_type = 'prompting/question'
        AND copilot_agent_type = 'insights agent'
    )
    -
    COUNT_IF(
        copilot_agent_type = 'reporting agent'
    ) AS no_of_analytics_agent_prompts

FROM {{ ref('vw_fct_copilot_ai_api_activity_detail') }}

WHERE action_timestamp IS NOT NULL

and not_customer_user = 'FALSE'
and interaction_type in ('prompting/question','report generation message')

GROUP BY
    LAST_DAY(action_timestamp::DATE)

ORDER BY
    end_of_month